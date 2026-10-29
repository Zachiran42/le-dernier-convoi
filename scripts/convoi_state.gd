class_name ConvoiState
extends RefCounted
## Deterministic campaign model. Persisted values are JSON primitives only.
const VERSION = 1
const WIDTH = 13
const HEIGHT = 11
const RESOURCE_KEYS = ["fuel","food","water","scrap","medicine","ammo"]
const MODULES = {
    "serre":{"name":"Serre","cost":{"scrap":10},"weight":1,"description":"Chaque trajet : +2 rations contre 2 eaux. Poids +1 carburant."},
    "citerne":{"name":"Citerne","cost":{"scrap":9},"weight":1,"description":"Capacité carburant 24 → 38. Poids +1 carburant par trajet."},
    "atelier":{"name":"Atelier","cost":{"scrap":12},"weight":1,"description":"Débloque munitions, carburant, remèdes et lame. Toutes les recettes ont un coût."},
    "blindage":{"name":"Blindage","cost":{"scrap":14},"weight":1,"description":"Dégâts de trajet −4, frappes −2. Poids +1 et surconsommation +1 carburant."},
    "infirmerie":{"name":"Infirmerie","cost":{"scrap":12},"weight":1,"description":"Un remède soigne 48 PV au lieu de 28, même en expédition. Poids +1 carburant."},
    "dortoir":{"name":"Dortoir","cost":{"scrap":8},"weight":1,"description":"Permet un quatrième survivant, qui consomme aussi des vivres. Poids +1 carburant."}
}
const RECIPES = {
    "ammo":{"name":"3 munitions","cost":{"scrap":3},"output":{"ammo":3},"requires":"atelier","description":"Trois tirs fabriqués à partir de pièces."},
    "fuel":{"name":"4 carburants","cost":{"scrap":4,"water":1},"output":{"fuel":4},"requires":"atelier","description":"Distiller du carburant consomme aussi une eau."},
    "medicine":{"name":"Un remède","cost":{"scrap":4,"food":1,"water":1},"output":{"medicine":1},"requires":"atelier","description":"Fabriquer un remède avec des fournitures limitées."},
    "blade":{"name":"Affûter la lame","cost":{"scrap":8},"output":{},"requires":"atelier","description":"+2 dégâts de mêlée permanents. Deux améliorations maximum."}
}
const DIRECTIONS = {"N":Vector2i(0,-1),"S":Vector2i(0,1),"E":Vector2i(1,0),"W":Vector2i(-1,0)}
var data: Dictionary = {}
var notice: String = ""

func new_run(seed: int = 0) -> void:
    var actual = seed & 0x7fffffff
    if actual == 0:
        actual = int(Time.get_ticks_usec()) & 0x7fffffff
    if actual == 0:
        actual = 1
    data = {"version":VERSION,"seed":actual,"rng":actual,"phase":"base","step":0,"region":"Vallée des Cendres",
        "resources":{"fuel":18,"food":16,"water":10,"scrap":18,"medicine":2,"ammo":6},"limits":{"fuel":24,"bag":9,"crew":3},"hull":100,
        "crew":[{"id":"mira","name":"Mira","role":"pilote","hp":100,"max_hp":100},{"id":"basile","name":"Basile","role":"mecano","hp":110,"max_hp":110},{"id":"edda","name":"Edda","role":"eclaireuse","hp":85,"max_hp":85}],
        "active_hero":"mira","train":{"slots":["empty","empty","empty"]},"routes":[],"route":{},"pending_event":{},"expedition":{},
        "event_resolved":false,"travel_modifier":0,"blade":0,"turn_total":0,"reason":"","log":[],"last_notice":""}
    _make_routes()
    _note("Huit haltes avant le fort. Ramenez le butin au train ; une expédition peut être abandonnée.")

func snapshot() -> Dictionary:
    return data.duplicate(true)

func act(action: String, arg: Variant = null) -> bool:
    if data.is_empty() or data.phase in ["won","lost"]:
        return false
    if action == "event_choice":
        return _event_choice(arg)
    if action == "continue":
        if data.phase == "travel_event" and data.pending_event.is_empty() and data.event_resolved:
            _start_expedition()
            return true
        _note("Résolvez d’abord le choix de trajet.")
        return false
    if data.phase == "base":
        match action:
            "choose_route": return _choose_route(arg)
            "build": return _build(arg)
            "dismantle": return _dismantle(arg)
            "craft": return _craft(str(arg))
            "repair": return _repair()
            "assign": return _assign(str(arg))
            "heal": return _heal(false)
            "wait":
                _consume_needs()
                data.hull = maxi(0,int(data.hull)-2)
                _note("Une journée immobile consomme les vivres ; les cendres usent la coque.")
                _check_loss()
                return true
        _note("Cette action nécessite une expédition.")
        return false
    if data.phase != "expedition":
        return false
    if action == "retreat":
        _retreat(false)
        return true
    if not data.pending_event.is_empty():
        _note("Choisissez le contenu à emporter avant de continuer.")
        return false
    match action:
        "move": return _move(arg)
        "attack": return _attack(arg)
        "interact": return _interact()
        "heal": return _heal(true)
        "return": return _return_to_train()
        "wait":
            _tick()
            return true
    return false

func _note(text: String) -> void:
    notice = text
    if not data.is_empty():
        data.last_notice = text
        data.log.append(text)
        while data.log.size() > 10:
            data.log.remove_at(0)

func _roll(limit: int) -> int:
    data.rng = (int(data.rng)*1664525+1013904223)&0x7fffffff
    return int(data.rng)%maxi(1,limit)

func _has(id: String, state: Dictionary = {}) -> bool:
    var current = data if state.is_empty() else state
    return id in current.train.slots

func _hero(state: Dictionary = {}) -> Dictionary:
    var current = data if state.is_empty() else state
    for member in current.crew:
        if member.id == current.active_hero:
            return member
    return {}

func _alive(state: Dictionary = {}) -> int:
    var current = data if state.is_empty() else state
    var count = 0
    for member in current.crew:
        if int(member.hp) > 0:
            count += 1
    return count

func _derived(state: Dictionary) -> Dictionary:
    var role = str(_hero(state).get("role","pilote"))
    return {"fuel":38 if _has("citerne",state) else 24,"bag":12 if role == "eclaireuse" else (10 if role == "mecano" else 9),"crew":4 if _has("dortoir",state) else 3}

func _fuel_cost(base: int, state: Dictionary) -> int:
    var weight = 0
    for id in state.train.slots:
        if id != "empty":
            weight += 1
    if _has("blindage",state):
        weight += 1
    if _hero(state).get("role","") == "pilote":
        weight -= 1
    return maxi(1,base+weight)

func _refresh() -> void:
    data.limits = _derived(data)
    data.resources.fuel = mini(int(data.resources.fuel),int(data.limits.fuel))
    for route in data.routes:
        route.fuel = _fuel_cost(int(route.base_fuel),data)

func _can_pay(cost: Dictionary) -> bool:
    for resource in cost:
        if not RESOURCE_KEYS.has(resource) or int(data.resources[resource]) < int(cost[resource]):
            return false
    return true

func _pay(cost: Dictionary) -> void:
    for resource in cost:
        data.resources[resource] -= int(cost[resource])

func _add_resources(reward: Dictionary) -> void:
    for resource in reward:
        if RESOURCE_KEYS.has(resource):
            var cap = int(data.limits.fuel) if resource == "fuel" else (12 if resource == "medicine" else (30 if resource == "ammo" else 99))
            data.resources[resource] = clampi(int(data.resources[resource])+int(reward[resource]),0,cap)

func _consume_needs() -> void:
    if _has("serre") and int(data.resources.water) >= 2:
        data.resources.water -= 2
        _add_resources({"food":2})
    var food_need = _alive()
    var water_need = int(ceil(float(_alive())/2.0))
    var missing = maxi(0,food_need-int(data.resources.food))+maxi(0,water_need-int(data.resources.water))
    data.resources.food = maxi(0,int(data.resources.food)-food_need)
    data.resources.water = maxi(0,int(data.resources.water)-water_need)
    if missing > 0:
        data.hull = maxi(0,int(data.hull)-missing*8)
        for member in data.crew:
            member.hp = maxi(0,int(member.hp)-missing*4)
        _note("Pénurie : équipage affaibli, coque −%d." % (missing*8))

func _make_routes() -> void:
    data.routes = []
    var final_leg = int(data.step) == 7
    var stop = int(data.step)
    var names = [
        ["Dépôt des Brasiers","Halle des Éclisses","Hangar des Veilleurs","Atelier de Roche-Noire","Gare du Vent Mort","Réserve de l’Éperon","Dernier Relais"][mini(stop,6)],
        ["Vergers calcinés","Serres de Vauclaire","Caves de la Verrerie","Silos des Courlis","Jardins de Traverse","Grenier des Cimes","Ferme du Dernier Matin"][mini(stop,6)],
        ["Source sous la cendre","Citernes de l’Orme","Bains abandonnés","Vasque du Vieux Pont","Château d’Eau Muet","Glacier de Brume","Cascade des Signaux"][mini(stop,6)]]
    var kinds = ["depot","farm","well"]
    var rewards = [{"fuel":8},{"food":9},{"water":9}]
    for index in range(3):
        var base_fuel = 2+_roll(3)
        var danger = 1+_roll(2)+(1 if int(data.step) >= 4 and index == 0 else 0)
        data.routes.append({"id":"halte-%d-%d" % [int(data.step)+1,index],"name":("Fort des Cendres — "+["la brèche","les tunnels","le promontoire"][index]) if final_leg else names[index],
            "kind":"fort" if final_leg else kinds[index],"base_fuel":base_fuel,"fuel":_fuel_cost(base_fuel,data),"danger":4 if final_leg else danger,
            "loot":{"scrap":6,"ammo":3} if final_leg else rewards[index].duplicate(true),
            "description":"Dernière menace : neutralisez le gardien, actionnez le verrou puis revenez au train." if final_leg else "Choisissez le lot au poste et ramenez-le au train. Les vivres sont consommés au départ."})

func _choose_route(value: Variant) -> bool:
    if not _integer(value,0,2):
        return false
    var route = data.routes[int(value)]
    if int(data.resources.fuel) < int(route.fuel):
        _note("Carburant insuffisant : %d requis." % int(route.fuel))
        _check_loss()
        return false
    data.resources.fuel -= int(route.fuel)
    _consume_needs()
    var damage = maxi(0,int(route.danger)*2+_roll(3)-(4 if _has("blindage") else 0))
    data.hull = maxi(0,int(data.hull)-damage)
    data.route = route.duplicate(true)
    data.travel_modifier = 0
    data.event_resolved = false
    data.pending_event = _travel_event()
    data.phase = "travel_event"
    _note("Trajet payé, vivres consommés, coque −%d. Un choix vous attend." % damage)
    _check_loss()
    return true

func _choice(id: String,label: String,cost: Dictionary,effects: Dictionary,description: String,requires: String = "") -> Dictionary:
    return {"id":id,"label":label,"cost":cost,"effects":effects,"description":description,"requires":requires}

func _travel_event() -> Dictionary:
    var events = [
        {"id":"bridge","title":"Le pont effondré","text":"Le convoi doit franchir un ravin instable.","choices":[
            _choice("detour","Faire le détour",{"fuel":2,"water":1},{},"Deux carburants et une eau, coque préservée."),
            _choice("brace","Renforcer le tablier",{"scrap":3},{"hull":-3},"Trois ferrailles et trois points de coque."),
            _choice("force","Forcer le passage",{},{"hull":-12},"Aucun matériau, mais douze points de coque perdus.")]},
        {"id":"survivors","title":"Des survivants au bord des rails","text":"Une communauté échange ses réserves. Ilyan cherche une place.","choices":[
            _choice("trade","Échanger des pièces",{"scrap":4},{"resources":{"food":5,"water":2}},"Quatre ferrailles contre cinq rations et deux eaux."),
            _choice("recruit","Accueillir Ilyan",{"food":2},{"join":true},"Dortoir requis. Un équipier supplémentaire consommera des vivres.","dortoir"),
            _choice("pass","Continuer sans échange",{},{},"Préserver les ressources actuelles.")]},
        {"id":"storm","title":"Mur de poussière","text":"Une cendre coupante recouvre la vallée.","choices":[
            _choice("shelter","Attendre à l’abri",{"food":2,"water":1},{},"Des vivres contre une traversée sans dommage."),
            _choice("filter","Fabriquer un filtre",{"scrap":2},{"hull":-1},"Deux ferrailles et un point de coque."),
            _choice("cross","Traverser immédiatement",{},{"hull":-8,"hero_hp":-6},"Huit points de coque et six PV perdus.")]},
        {"id":"dealer","title":"Le distillateur","text":"Un marchand propose quelques bidons.","choices":[
            _choice("scrap","Acheter sept carburants",{"scrap":5},{"resources":{"fuel":7}},"Attention à la capacité du réservoir."),
            _choice("medicine","Troquer un remède",{"medicine":1},{"resources":{"fuel":8}},"Huit carburants, un soin de moins."),
            _choice("refuse","Refuser",{},{},"Ne rien échanger.")]},
        {"id":"water","title":"L’eau trouble","text":"Des réservoirs contaminés subsistent sous un abri.","choices":[
            _choice("purify","Employer un remède",{"medicine":1},{"resources":{"water":8}},"Huit eaux purifiées contre un remède."),
            _choice("filter","Assembler un filtre",{"scrap":3},{"resources":{"water":5}},"Cinq eaux contre trois ferrailles."),
            _choice("leave","Ne prendre aucun risque",{},{},"Laisser ces réserves.")]},
        {"id":"checkpoint","title":"Un barrage de pillards","text":"Des silhouettes exigent un tribut.","choices":[
            _choice("cover","Tirer pour passer",{"ammo":2},{"resources":{"scrap":4},"hull":-2},"Deux tirs, quatre ferrailles récupérées, coque −2."),
            _choice("tribute","Payer en rations",{"food":3},{},"Trois rations pour préserver la coque."),
            _choice("ram","Enfoncer le barrage",{},{"hull":-10,"hero_hp":-5},"Coque −10, PV −5.")]},
        {"id":"beacon","title":"Une balise encore active","text":"Un détour permettrait de récupérer ses réserves.","choices":[
            _choice("search","Inspecter à pied",{"water":2},{"resources":{"ammo":3,"scrap":3}},"Deux eaux contre trois tirs et trois ferrailles."),
            _choice("drive","Faire le détour en train",{"fuel":1},{"resources":{"water":4}},"Un carburant contre quatre eaux."),
            _choice("ignore","Rester sur l’axe",{},{},"Ne pas faire de détour.")]},
        {"id":"last_gate","title":"Le dernier verrou","text":"Le gardien du fort contrôle le passage.","choices":[
            _choice("sabotage","Saboter sa cuirasse",{"scrap":4},{"weaken":4},"Le gardien aura quatre PV de moins."),
            _choice("cover","Préparer une couverture",{"ammo":2},{"weaken":5},"Deux tirs dépensés ; gardien affaibli de cinq PV."),
            _choice("save","Préserver les réserves",{},{},"Affronter le gardien sans préparation.")]}
    ]
    var event = events[int(data.step)].duplicate(true)
    event.context = "travel"
    return event

func _event_choice(value: Variant) -> bool:
    var event = data.pending_event
    if event.is_empty() or not _integer(value,0,event.choices.size()-1):
        return false
    var choice = event.choices[int(value)]
    if not str(choice.get("requires","")).is_empty() and not _has(str(choice.requires)):
        _note("Ce choix nécessite : "+MODULES[str(choice.requires)].name)
        return false
    if not _can_pay(choice.cost):
        _note("Ressources insuffisantes pour ce choix.")
        return false
    if event.context == "loot":
        var reward = choice.effects.get("loot",{})
        if _carried_size()+_sum_resources(reward) > int(data.expedition.capacity):
            _note("Port limité : choisissez l’autre lot ou laissez cette cache.")
            return false
        _pay(choice.cost)
        for resource in reward:
            data.expedition.carried[resource] += int(reward[resource])
        for node in data.expedition.nodes:
            if node.id == event.node_id:
                node.taken = true
                if node.kind == "objective":
                    data.expedition.objective_done = true
        data.pending_event = {}
        _note("Lot choisi. %d / %d unités portées ; revenez au train." % [_carried_size(),int(data.expedition.capacity)])
        _tick()
        return true
    if choice.effects.get("join",false) and (_alive() >= int(data.limits.crew) or data.crew.size() >= 4):
        _note("Le convoi ne peut accueillir personne de plus.")
        return false
    _pay(choice.cost)
    var effects = choice.effects
    _add_resources(effects.get("resources",{}))
    data.hull = clampi(int(data.hull)+int(effects.get("hull",0)),0,100)
    var hero = _hero()
    hero.hp = clampi(int(hero.hp)+int(effects.get("hero_hp",0)),0,int(hero.max_hp))
    data.travel_modifier += int(effects.get("weaken",0))
    if effects.get("join",false):
        data.crew.append({"id":"ilyan","name":"Ilyan","role":"aide","hp":75,"max_hp":75})
    data.pending_event = {}
    data.event_resolved = true
    _note(str(choice.description)+" Prêt à explorer : continuer.")
    _check_loss()
    return true

func _build(value: Variant) -> bool:
    var module = ""
    var slot = -1
    var replace = false
    if value is String:
        module = value
        slot = data.train.slots.find("empty")
    elif value is Dictionary:
        module = str(value.get("module",""))
        if _integer(value.get("slot"),0,2):
            slot = int(value.slot)
        replace = value.get("replace",false) == true
    if not MODULES.has(module) or slot < 0 or slot > 2:
        _note("Choisissez un module et un des trois emplacements.")
        return false
    if module in data.train.slots:
        _note("Ce module est déjà installé.")
        return false
    var old = str(data.train.slots[slot])
    if old != "empty" and not replace:
        _note("Emplacement occupé : confirmez son remplacement ou démontez le module.")
        return false
    if old == "dortoir" and _alive() > 3:
        _note("Quatre survivants ont besoin du dortoir.")
        return false
    if not _can_pay(MODULES[module].cost):
        _note("Le coût entier du nouveau module est requis avant récupération de l’ancien.")
        return false
    _pay(MODULES[module].cost)
    if old != "empty":
        _add_resources({"scrap":int(int(MODULES[old].cost.scrap)/2.0)})
    data.train.slots[slot] = module
    _refresh()
    _note(MODULES[module].name+" installé. Le poids augmente le coût des routes affichées.")
    _check_loss()
    return true

func _dismantle(value: Variant) -> bool:
    if not _integer(value,0,2):
        return false
    var slot = int(value)
    var old = str(data.train.slots[slot])
    if old == "empty":
        return false
    if old == "dortoir" and _alive() > 3:
        _note("Impossible de retirer le dortoir avec quatre survivants.")
        return false
    data.train.slots[slot] = "empty"
    _refresh()
    var amount = int(int(MODULES[old].cost.scrap)/2.0)
    _add_resources({"scrap":amount})
    _note("Module démonté : %d ferrailles. Le carburant excédant la capacité est perdu." % amount)
    _check_loss()
    return true

func _craft(id: String) -> bool:
    if not RECIPES.has(id):
        return false
    var recipe = RECIPES[id]
    if not _has(str(recipe.requires)):
        _note("La recette nécessite un atelier.")
        return false
    if id == "blade" and int(data.blade) >= 2:
        _note("Lame déjà affûtée au maximum.")
        return false
    var cost = recipe.cost.duplicate(true)
    if _hero().role == "mecano":
        cost.scrap = maxi(1,int(cost.scrap)-1)
    if not _can_pay(cost):
        _note("Ressources insuffisantes pour fabriquer : "+recipe.name)
        return false
    _pay(cost)
    _add_resources(recipe.output)
    if id == "blade":
        data.blade += 1
    _note(recipe.name+" fabriqué. Le mécano économise une ferraille par recette.")
    return true

func _repair() -> bool:
    if int(data.hull) >= 100:
        _note("La coque est intacte.")
        return false
    if not _can_pay({"scrap":4}):
        _note("Réparer demande quatre ferrailles.")
        return false
    _pay({"scrap":4})
    var amount = 36 if _hero().role == "mecano" else 24
    data.hull = mini(100,int(data.hull)+amount)
    _note("Coque réparée : +%d, contre quatre ferrailles." % amount)
    return true

func _assign(id: String) -> bool:
    for member in data.crew:
        if member.id == id and int(member.hp) > 0:
            data.active_hero = id
            _refresh()
            _note(member.name+" mène le groupe. Pilote : trajet −1 ; mécano : réparation/recettes ; éclaireuse : visibilité/sac.")
            return true
    _note("Ce survivant est hors de combat.")
    return false

func _heal(in_expedition: bool) -> bool:
    var hero = _hero()
    if int(hero.hp) >= int(hero.max_hp) or int(data.resources.medicine) < 1:
        _note("Un remède et des PV manquants sont nécessaires.")
        return false
    data.resources.medicine -= 1
    var amount = 48 if _has("infirmerie") else 28
    hero.hp = mini(int(hero.max_hp),int(hero.hp)+amount)
    _note("Un remède consommé : +%d PV maximum." % amount)
    if in_expedition:
        _tick()
    return true
func _start_expedition() -> void:
    var grid = []
    var seen = []
    var visible = []
    for y in range(HEIGHT):
        var row = []
        var fog = []
        var light = []
        for x in range(WIDTH):
            row.append(1 if x == 0 or y == 0 or x == WIDTH-1 or y == HEIGHT-1 else 0)
            fog.append(false)
            light.append(false)
        grid.append(row)
        seen.append(fog)
        visible.append(light)
    for attempt in range(24):
        var x = 2+_roll(9)
        var y = 1+_roll(9)
        if y == 5 or x == 11 or grid[y][x] == 1 or Vector2i(x,y) in [Vector2i(7,3),Vector2i(4,7),Vector2i(8,7)]:
            continue
        grid[y][x] = 1
        if not _connected(grid):
            grid[y][x] = 0
    var kind = str(data.route.kind)
    var primary = data.route.loot.duplicate(true)
    var alternate = {"scrap":5,"ammo":2}
    if kind == "farm":
        alternate = {"food":4,"water":3}
    elif kind == "well":
        alternate = {"water":4,"medicine":1}
    elif kind == "fort":
        alternate = {"medicine":2,"scrap":3}
    var nodes = [
        {"id":"objective","x":11,"y":5,"kind":"objective","name":"Verrou du fort" if kind == "fort" else "Réserve du poste","loot":primary,"alternate":alternate,"taken":false},
        {"id":"cache-a","x":7,"y":3,"kind":"cache","name":"Caisse abandonnée","loot":{"scrap":3},"alternate":{"ammo":2},"taken":false},
        {"id":"cache-b","x":4,"y":7,"kind":"cache","name":"Sac de voyage","loot":{"food":2},"alternate":{"water":2},"taken":false}]
    var enemies = []
    if kind == "fort":
        enemies.append(_enemy("warden",10,5,maxi(12,20-int(data.travel_modifier)),true))
        enemies.append(_enemy("raider-a",7,3,10,false))
        enemies.append(_enemy("raider-b",8,7,10,false))
    else:
        enemies.append(_enemy("raider-a",7,5,9+int(int(data.step)/3.0),false))
        if int(data.route.danger) >= 3:
            enemies.append(_enemy("raider-b",8,7,10,false))
    data.expedition = {"width":WIDTH,"height":HEIGHT,"grid":grid,"seen":seen,"visible":visible,
        "player":{"x":1,"y":5,"facing":"E"},"exit":{"x":1,"y":5},"nodes":nodes,"enemies":enemies,
        "turns":0,"carried":_empty_resources(),"capacity":int(data.limits.bag),"objective_done":false}
    data.phase = "expedition"
    data.event_resolved = false
    _vision()
    _note("Explorez, récupérez le lot au poste, puis revenez au train. Les tirs sont rares ; une case rouge annonce la prochaine frappe.")

func _enemy(id: String,x: int,y: int,hp: int,boss: bool) -> Dictionary:
    return {"id":id,"x":x,"y":y,"hp":hp,"max_hp":hp,"boss":boss,"intent":"","intent_x":-1,"intent_y":-1,"stun":0,"cooldown":0,"alert":0}

func _empty_resources() -> Dictionary:
    return {"fuel":0,"food":0,"water":0,"scrap":0,"medicine":0,"ammo":0}

func _sum_resources(resources: Dictionary) -> int:
    var count = 0
    for key in resources:
        count += int(resources[key])
    return count

func _carried_size() -> int:
    return _sum_resources(data.expedition.carried)

func _direction(value: Variant) -> Vector2i:
    if value is Vector2i and absi(value.x)+absi(value.y) == 1:
        return value
    if value is String:
        return DIRECTIONS.get(value.to_upper(),Vector2i.ZERO)
    return Vector2i.ZERO

func _inside(x: int,y: int) -> bool:
    return x > 0 and y > 0 and x < WIDTH-1 and y < HEIGHT-1

func _at_enemy(x: int,y: int) -> Dictionary:
    for enemy in data.expedition.enemies:
        if int(enemy.x) == x and int(enemy.y) == y:
            return enemy
    return {}

func _move(value: Variant) -> bool:
    var delta = _direction(value)
    if delta == Vector2i.ZERO:
        return false
    var player = data.expedition.player
    for key in DIRECTIONS:
        if DIRECTIONS[key] == delta:
            player.facing = key
    var x = int(player.x)+delta.x
    var y = int(player.y)+delta.y
    if not _inside(x,y) or int(data.expedition.grid[y][x]) == 1:
        notice = "Un mur barre le passage."
        return false
    if not _at_enemy(x,y).is_empty():
        notice = "Un adversaire bloque la case : attaquez ou contournez-le."
        return false
    player.x = x
    player.y = y
    _tick()
    return true

func _attack(value: Variant) -> bool:
    var e = data.expedition
    var player = e.player
    var target: Dictionary = {}
    var nearest = 999
    var direction = _direction(value)
    for enemy in e.enemies:
        var distance = absi(int(enemy.x)-int(player.x))+absi(int(enemy.y)-int(player.y))
        if not e.visible[int(enemy.y)][int(enemy.x)] or not _line_clear(e.grid,int(player.x),int(player.y),int(enemy.x),int(enemy.y)):
            continue
        if direction != Vector2i.ZERO:
            var dx = int(enemy.x)-int(player.x)
            var dy = int(enemy.y)-int(player.y)
            if (direction.x != 0 and (dy != 0 or signi(dx) != direction.x)) or (direction.y != 0 and (dx != 0 or signi(dy) != direction.y)):
                continue
        if distance < nearest:
            nearest = distance
            target = enemy
    if target.is_empty() or nearest > 5:
        notice = "Aucun adversaire visible à portée (5 cases)."
        return false
    var damage = 4+int(data.blade)*2+(1 if _hero().role == "mecano" else 0)
    if nearest > 1:
        if int(data.resources.ammo) < 1:
            notice = "Plus de munitions. Approchez pour frapper au corps à corps."
            return false
        data.resources.ammo -= 1
        damage = 7 if _hero().role == "eclaireuse" else 6
    target.hp -= damage
    if int(target.hp) <= 0:
        e.enemies.erase(target)
        _note("Adversaire neutralisé. Le passage est libre ; choisissez les fournitures dans les caches.")
    else:
        notice = "Frappe : −%d PV. Déplacez-vous si une attaque est annoncée." % damage
    _tick()
    return true

func _interact() -> bool:
    var e = data.expedition
    if int(e.player.x) == int(e.exit.x) and int(e.player.y) == int(e.exit.y) and e.objective_done:
        return _return_to_train()
    for node in e.nodes:
        var distance = absi(int(node.x)-int(e.player.x))+absi(int(node.y)-int(e.player.y))
        if node.taken or distance > 1:
            continue
        if node.kind == "objective" and data.route.kind == "fort":
            for enemy in e.enemies:
                if enemy.boss:
                    _note("Le gardien verrouille le fort. Neutralisez-le avant d’actionner la porte.")
                    return false
        data.pending_event = {"id":"loot-"+str(node.id),"context":"loot","node_id":node.id,"title":node.name,
            "text":"Un seul lot. Port : %d / %d. Butin sécurisé seulement au train." % [_carried_size(),int(e.capacity)],
            "choices":[_choice("primary","Emporter le lot annoncé",{},{"loot":node.loot.duplicate(true)},"Récupérer "+_resource_label(node.loot)),
                _choice("alternate","Choisir l’autre lot",{},{"loot":node.alternate.duplicate(true)},"Récupérer "+_resource_label(node.alternate)),
                _choice("leave","Laisser les fournitures",{},{"loot":{}},"Valider le poste sans charger davantage.")]}
        return true
    notice = "Approchez d’une réserve ou du poste pour interagir."
    return false

func _resource_label(resources: Dictionary) -> String:
    var labels = {"fuel":"carburants","food":"rations","water":"eaux","scrap":"ferrailles","medicine":"remèdes","ammo":"munitions"}
    var parts: Array[String] = []
    for key in resources:
        parts.append("%d %s" % [int(resources[key]),labels[key]])
    return ", ".join(parts)

func _return_to_train() -> bool:
    var e = data.expedition
    if int(e.player.x) != int(e.exit.x) or int(e.player.y) != int(e.exit.y):
        _note("Le retour doit être validé sur la case du train.")
        return false
    if not e.objective_done:
        _note("Le poste n’est pas validé. Explorez ou repliez-vous en abandonnant le butin.")
        return false
    _add_resources(e.carried)
    data.step += 1
    data.phase = "base"
    data.route = {}
    data.expedition = {}
    data.pending_event = {}
    if int(data.step) >= 8:
        data.phase = "won"
        data.routes = []
        data.reason = "Le gardien est tombé. Le dernier convoi franchit la Vallée des Cendres."
        _note(data.reason)
    else:
        _make_routes()
        _note("Halte %d / 8 sécurisée. Butin déchargé ; préparez le prochain départ." % int(data.step))
        _check_loss()
    return true

func _retreat(knocked_out: bool) -> void:
    var hero = _hero()
    if not knocked_out:
        hero.hp = maxi(1,int(hero.hp)-12)
    data.hull = maxi(0,int(data.hull)-(18 if knocked_out else 6))
    data.phase = "base"
    data.route = {}
    data.expedition = {}
    data.pending_event = {}
    data.event_resolved = false
    if int(hero.hp) <= 0:
        for member in data.crew:
            if int(member.hp) > 0:
                data.active_hero = member.id
                break
    _refresh()
    _note("Survivant hors de combat : butin perdu, coque −18." if knocked_out else "Repli : butin abandonné, −12 PV, coque −6. Cette halte reste à accomplir.")
    _check_loss()

func _tick() -> void:
    if data.phase != "expedition":
        return
    data.expedition.turns += 1
    data.turn_total += 1
    if int(data.expedition.turns) > 36 and int(data.expedition.turns)%4 == 0:
        data.hull = maxi(0,int(data.hull)-1)
        notice = "L’exposition prolongée aux cendres use la coque."
    _enemy_turn()
    if data.phase == "expedition":
        _vision()
    _check_loss()

func _enemy_turn() -> void:
    var e = data.expedition
    var hero = _hero()
    for enemy in e.enemies:
        if int(enemy.stun) > 0:
            enemy.stun -= 1
            enemy.intent = ""
            enemy.intent_x = -1
            enemy.intent_y = -1
            continue
        if enemy.intent == "strike":
            if int(e.player.x) == int(enemy.intent_x) and int(e.player.y) == int(enemy.intent_y):
                var damage = maxi(1,(13 if enemy.boss else 8)-(2 if _has("blindage") else 0))
                hero.hp = maxi(0,int(hero.hp)-damage)
                _note("Frappe annoncée reçue : −%d PV. Déplacez-vous pour éviter la suivante." % damage)
                if int(hero.hp) <= 0:
                    _retreat(true)
                    return
            enemy.intent = ""
            enemy.intent_x = -1
            enemy.intent_y = -1
            enemy.cooldown = 1
            continue
        if int(enemy.cooldown) > 0:
            enemy.cooldown -= 1
            continue
        var distance = absi(int(enemy.x)-int(e.player.x))+absi(int(enemy.y)-int(e.player.y))
        var clear = _line_clear(e.grid,int(enemy.x),int(enemy.y),int(e.player.x),int(e.player.y))
        if distance <= (2 if enemy.boss else 1) and clear:
            enemy.intent = "strike"
            enemy.intent_x = int(e.player.x)
            enemy.intent_y = int(e.player.y)
            continue
        if distance <= 6 and clear:
            enemy.alert = 5
        if int(enemy.alert) > 0:
            enemy.alert -= 1
            var step = _chase_step(int(enemy.x),int(enemy.y),int(e.player.x),int(e.player.y))
            if step != Vector2i.ZERO:
                enemy.x += step.x
                enemy.y += step.y
            distance = absi(int(enemy.x)-int(e.player.x))+absi(int(enemy.y)-int(e.player.y))
            if distance <= (2 if enemy.boss else 1) and _line_clear(e.grid,int(enemy.x),int(enemy.y),int(e.player.x),int(e.player.y)):
                enemy.intent = "strike"
                enemy.intent_x = int(e.player.x)
                enemy.intent_y = int(e.player.y)

func _chase_step(x: int,y: int,tx: int,ty: int) -> Vector2i:
    var open = [Vector2i(x,y)]
    var parents = {Vector2i(x,y):Vector2i(-1,-1)}
    var destination = Vector2i(tx,ty)
    var head = 0
    while head < open.size():
        var at: Vector2i = open[head]
        head += 1
        if at == destination:
            while parents[at] != Vector2i(x,y):
                at = parents[at]
            return at-Vector2i(x,y)
        for delta in DIRECTIONS.values():
            var next: Vector2i = at+delta
            if not _inside(next.x,next.y) or data.expedition.grid[next.y][next.x] == 1 or parents.has(next):
                continue
            if next != destination and not _at_enemy(next.x,next.y).is_empty():
                continue
            parents[next] = at
            open.append(next)
    return Vector2i.ZERO

func _line_clear(grid: Array,ax: int,ay: int,bx: int,by: int) -> bool:
    # Symmetric centre-to-centre grid traversal, including closed corners.
    # End walls remain visible; walls between the two endpoints stop the ray.
    var x = ax
    var y = ay
    var nx = absi(bx-ax)
    var ny = absi(by-ay)
    var sx = signi(bx-ax)
    var sy = signi(by-ay)
    var ix = 0
    var iy = 0
    while ix < nx or iy < ny:
        var decision = (1+2*ix)*ny-(1+2*iy)*nx
        if decision == 0:
            if grid[y][x+sx] == 1 and grid[y+sy][x] == 1:
                return false
            x += sx
            y += sy
            ix += 1
            iy += 1
        elif decision < 0:
            x += sx
            ix += 1
        else:
            y += sy
            iy += 1
        if x == bx and y == by:
            return true
        if grid[y][x] == 1:
            return false
    return true

func _vision() -> void:
    var e = data.expedition
    var radius = 6 if _hero().role == "eclaireuse" else 4
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var distance = absi(x-int(e.player.x))+absi(y-int(e.player.y))
            var shown = distance <= radius and _line_clear(e.grid,int(e.player.x),int(e.player.y),x,y)
            e.visible[y][x] = shown
            if shown:
                e.seen[y][x] = true

func _connected(grid: Array) -> bool:
    var open = [Vector2i(1,5)]
    var seen = {Vector2i(1,5):true}
    var head = 0
    while head < open.size():
        var at: Vector2i = open[head]
        head += 1
        for delta in DIRECTIONS.values():
            var next: Vector2i = at+delta
            if _inside(next.x,next.y) and grid[next.y][next.x] == 0 and not seen.has(next):
                seen[next] = true
                open.append(next)
    var floor_count = 0
    for row in grid:
        for tile in row:
            if tile == 0:
                floor_count += 1
    return seen.size() == floor_count

func _can_recover_fuel() -> bool:
    # Before declaring defeat, consider legal role changes, dismantling and
    # building/using an atelier. Optional wagon weight can always be removed.
    var base_cost = 999
    for route in data.routes:
        base_cost = mini(base_cost,int(route.base_fuel))
    var pilot = false
    var mechanic = false
    for member in data.crew:
        if int(member.hp) > 0:
            pilot = pilot or member.role == "pilote"
            mechanic = mechanic or member.role == "mecano"
    var compulsory_weight = 1 if _alive() > 3 else 0
    var saving = 1 if pilot else 0
    if int(data.resources.fuel) >= maxi(1,base_cost+compulsory_weight-saving):
        return true
    var scrap = int(data.resources.scrap)
    for module in data.train.slots:
        if module != "empty" and module != "atelier" and not (module == "dortoir" and _alive() > 3):
            scrap += int(int(MODULES[module].cost.scrap)/2.0)
    var construction = 0 if _has("atelier") else int(MODULES.atelier.cost.scrap)
    var factory_fuel = maxi(1,base_cost+compulsory_weight+1-saving)
    var batches = maxi(1,int(ceil(float(factory_fuel-int(data.resources.fuel))/4.0)))
    return int(data.resources.water) >= batches and scrap >= construction+batches*(3 if mechanic else 4)

func _check_loss() -> void:
    if data.phase in ["won","lost"]:
        return
    var reason = ""
    if int(data.hull) <= 0:
        reason = "La coque du dernier convoi a cédé."
    elif _alive() == 0:
        reason = "Aucun survivant ne peut mener le convoi."
    elif data.phase == "base":
        var minimum = 999
        for route in data.routes:
            minimum = mini(minimum,int(route.fuel))
        if int(data.resources.fuel) < minimum and not _can_recover_fuel():
            reason = "Plus de carburant pour atteindre une halte, ni de quoi en fabriquer."
    if not reason.is_empty():
        data.phase = "lost"
        data.reason = reason
        data.pending_event = {}
        data.routes = []
        data.route = {}
        data.expedition = {}
        _note(reason)

func _integer(value: Variant,minimum: int,maximum: int) -> bool:
    if not (value is int or value is float):
        return false
    return is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

func _json_safe(value: Variant,depth: int = 0) -> bool:
    if depth > 14:
        return false
    if value is bool or value == null:
        return true
    if value is int or value is float:
        return _integer(value,-2147483647,2147483647)
    if value is String:
        return value.length() <= 1500
    if value is Array:
        if value.size() > 160:
            return false
        for item in value:
            if not _json_safe(item,depth+1):
                return false
        return true
    if value is Dictionary:
        if value.size() > 80:
            return false
        for key in value:
            if not key is String or not _json_safe(value[key],depth+1):
                return false
        return true
    return false

func _normalise(value: Variant) -> Variant:
    if value is float:
        return int(value)
    if value is Array:
        var array = []
        for item in value:
            array.append(_normalise(item))
        return array
    if value is Dictionary:
        var dictionary = {}
        for key in value:
            dictionary[key] = _normalise(value[key])
        return dictionary
    return value

func _resource_valid(value: Variant,complete: bool = false) -> bool:
    if not value is Dictionary or value.size() > RESOURCE_KEYS.size():
        return false
    if complete and value.size() != RESOURCE_KEYS.size():
        return false
    for key in value:
        if not RESOURCE_KEYS.has(key) or not _integer(value[key],0,99):
            return false
    return true

func _route_valid(route: Variant,state: Dictionary) -> bool:
    if not route is Dictionary or not route.has_all(["id","name","kind","base_fuel","fuel","danger","loot","description"]):
        return false
    return route.id is String and route.name is String and route.description is String and route.kind in ["depot","farm","well","fort"] and _integer(route.base_fuel,2,4) and _integer(route.danger,1,4) and _integer(route.fuel,1,10) and int(route.fuel) == _fuel_cost(int(route.base_fuel),state) and _resource_valid(route.loot)

func _event_valid(event: Variant,state: Dictionary) -> bool:
    if not event is Dictionary:
        return false
    if event.is_empty():
        return true
    if not event.has_all(["id","title","text","context","choices"]):
        return false
    if not event.id is String or not event.title is String or not event.text is String or not event.context in ["travel","loot"] or not event.choices is Array or event.choices.size() < 2 or event.choices.size() > 3:
        return false
    if event.context == "travel" and state.phase != "travel_event":
        return false
    if event.context == "loot":
        if state.phase != "expedition" or not event.has("node_id"):
            return false
        var found = false
        for node in state.expedition.nodes:
            if node.id == event.node_id and not node.taken:
                found = true
        if not found:
            return false
    for choice in event.choices:
        if not choice is Dictionary or not choice.has_all(["id","label","cost","description","effects","requires"]):
            return false
        if not choice.id is String or not choice.label is String or not choice.description is String or not _resource_valid(choice.cost) or not choice.effects is Dictionary or not choice.requires is String:
            return false
        if not choice.requires.is_empty() and not MODULES.has(choice.requires):
            return false
        for effect in choice.effects:
            if effect in ["resources","loot"]:
                if not _resource_valid(choice.effects[effect]):
                    return false
            elif effect in ["hull","hero_hp"]:
                if not _integer(choice.effects[effect],-30,30):
                    return false
            elif effect == "weaken":
                if not _integer(choice.effects[effect],0,6):
                    return false
            elif effect == "join":
                if not choice.effects[effect] is bool:
                    return false
            else:
                return false
    return true

func _expedition_valid(e: Variant,state: Dictionary) -> bool:
    if not e is Dictionary:
        return false
    if state.phase != "expedition":
        return e.is_empty()
    if not e.has_all(["width","height","grid","seen","visible","player","exit","nodes","enemies","turns","carried","capacity","objective_done"]):
        return false
    if e.width != WIDTH or e.height != HEIGHT or not _integer(e.turns,0,10000) or e.capacity != state.limits.bag or not e.objective_done is bool or not _resource_valid(e.carried,true) or _sum_resources(e.carried) > int(e.capacity):
        return false
    for field in ["grid","seen","visible"]:
        if not e[field] is Array or e[field].size() != HEIGHT:
            return false
        for row in e[field]:
            if not row is Array or row.size() != WIDTH:
                return false
            for tile in row:
                if (field == "grid" and not _integer(tile,0,1)) or (field != "grid" and not tile is bool):
                    return false
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if (x == 0 or y == 0 or x == WIDTH-1 or y == HEIGHT-1) and e.grid[y][x] != 1:
                return false
            if e.visible[y][x] and not e.seen[y][x]:
                return false
    if not _connected(e.grid):
        return false
    if not e.player is Dictionary or not e.exit is Dictionary or not e.player.has_all(["x","y","facing"]) or not e.exit.has_all(["x","y"]):
        return false
    for position in [e.player,e.exit]:
        if not _integer(position.x,1,WIDTH-2) or not _integer(position.y,1,HEIGHT-2) or e.grid[int(position.y)][int(position.x)] != 0:
            return false
    if e.exit.x != 1 or e.exit.y != 5 or not DIRECTIONS.has(e.player.facing):
        return false
    if not e.nodes is Array or e.nodes.size() != 3 or not e.enemies is Array or e.enemies.size() > 3:
        return false
    var ids = {}
    var objective = false
    for node in e.nodes:
        if not node is Dictionary or not node.has_all(["id","x","y","kind","name","loot","alternate","taken"]):
            return false
        if not node.id is String or ids.has(node.id) or not node.name is String or not node.kind in ["objective","cache"] or not node.taken is bool or not _integer(node.x,1,WIDTH-2) or not _integer(node.y,1,HEIGHT-2) or e.grid[int(node.y)][int(node.x)] != 0 or not _resource_valid(node.loot) or not _resource_valid(node.alternate):
            return false
        ids[node.id] = true
        if node.kind == "objective":
            if objective or node.taken != e.objective_done:
                return false
            objective = true
    if not objective:
        return false
    var occupied = {Vector2i(int(e.player.x),int(e.player.y)):true}
    for enemy in e.enemies:
        if not enemy is Dictionary or not enemy.has_all(["id","x","y","hp","max_hp","boss","intent","intent_x","intent_y","stun","cooldown","alert"]):
            return false
        if not enemy.id is String or ids.has(enemy.id) or not _integer(enemy.x,1,WIDTH-2) or not _integer(enemy.y,1,HEIGHT-2) or e.grid[int(enemy.y)][int(enemy.x)] != 0 or not _integer(enemy.max_hp,1,30) or not _integer(enemy.hp,1,int(enemy.max_hp)) or not enemy.boss is bool or not enemy.intent in ["","strike"] or not _integer(enemy.stun,0,1) or not _integer(enemy.cooldown,0,1) or not _integer(enemy.alert,0,5):
            return false
        var position = Vector2i(int(enemy.x),int(enemy.y))
        if occupied.has(position):
            return false
        occupied[position] = true
        ids[enemy.id] = true
        if enemy.intent == "strike":
            if not _integer(enemy.intent_x,1,WIDTH-2) or not _integer(enemy.intent_y,1,HEIGHT-2) or e.grid[int(enemy.intent_y)][int(enemy.intent_x)] != 0:
                return false
        elif enemy.intent_x != -1 or enemy.intent_y != -1:
            return false
    return true

func restore(value: Variant) -> bool:
    if not value is Dictionary or not _json_safe(value):
        return false
    var candidate: Dictionary = _normalise(value)
    var required = ["version","seed","rng","phase","step","region","resources","limits","hull","crew","active_hero","train","routes","route","pending_event","expedition","event_resolved","travel_modifier","blade","turn_total","reason","log","last_notice"]
    if not candidate.has_all(required) or candidate.version != VERSION or not _integer(candidate.seed,1,2147483647) or not _integer(candidate.rng,0,2147483647) or not candidate.phase in ["base","travel_event","expedition","won","lost"] or not _integer(candidate.step,0,8) or candidate.region != "Vallée des Cendres":
        return false
    if not _resource_valid(candidate.resources,true) or not candidate.limits is Dictionary or not _integer(candidate.hull,0,100) or not candidate.crew is Array or candidate.crew.size() < 3 or candidate.crew.size() > 4 or not candidate.active_hero is String:
        return false
    if not candidate.train is Dictionary or not candidate.train.has("slots") or not candidate.train.slots is Array or candidate.train.slots.size() != 3:
        return false
    var modules = {}
    for id in candidate.train.slots:
        if not id is String or (id != "empty" and (not MODULES.has(id) or modules.has(id))):
            return false
        if id != "empty":
            modules[id] = true
    var crew_ids = {}
    var active_found = false
    for member in candidate.crew:
        if not member is Dictionary or not member.has_all(["id","name","role","hp","max_hp"]):
            return false
        if not member.id is String or member.id.is_empty() or crew_ids.has(member.id) or not member.name is String or not member.role in ["pilote","mecano","eclaireuse","aide"] or not _integer(member.max_hp,40,150) or not _integer(member.hp,0,int(member.max_hp)):
            return false
        crew_ids[member.id] = true
        if member.id == candidate.active_hero:
            active_found = true
            if candidate.phase != "lost" and int(member.hp) == 0:
                return false
    if not active_found or candidate.limits != _derived(candidate) or _alive(candidate) > int(candidate.limits.crew) or int(candidate.resources.fuel) > int(candidate.limits.fuel) or int(candidate.resources.medicine) > 12 or int(candidate.resources.ammo) > 30:
        return false
    if not candidate.routes is Array or not candidate.route is Dictionary or not candidate.event_resolved is bool or not _integer(candidate.travel_modifier,0,6) or not _integer(candidate.blade,0,2) or not _integer(candidate.turn_total,0,100000) or not candidate.reason is String or not candidate.last_notice is String or not candidate.log is Array or candidate.log.size() > 10:
        return false
    for line in candidate.log:
        if not line is String:
            return false
    if candidate.phase in ["won","lost"]:
        if not candidate.routes.is_empty() or not candidate.route.is_empty() or not candidate.pending_event.is_empty() or not candidate.expedition.is_empty():
            return false
        if candidate.phase == "won" and (candidate.step != 8 or candidate.hull <= 0 or _alive(candidate) == 0):
            return false
    else:
        if candidate.step >= 8 or candidate.routes.size() != 3 or candidate.hull <= 0 or _alive(candidate) == 0:
            return false
        var route_ids = {}
        for route in candidate.routes:
            if not _route_valid(route,candidate) or route_ids.has(route.id):
                return false
            route_ids[route.id] = true
        if candidate.phase == "base" and not candidate.route.is_empty():
            return false
        if candidate.phase in ["travel_event","expedition"]:
            if not _route_valid(candidate.route,candidate) or not candidate.route in candidate.routes:
                return false
    if not _expedition_valid(candidate.expedition,candidate) or not _event_valid(candidate.pending_event,candidate):
        return false
    if candidate.phase == "base" and not candidate.pending_event.is_empty():
        return false
    if candidate.phase == "travel_event" and candidate.pending_event.is_empty() != candidate.event_resolved:
        return false
    data = candidate
    notice = str(data.last_notice)
    return true
