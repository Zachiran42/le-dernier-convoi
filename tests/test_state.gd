extends SceneTree
const Model = preload("res://scripts/convoi_state.gd")
var failures = 0
var cases = 0

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)

func _case(name: String, callable: Callable) -> void:
    cases += 1
    var before = failures
    callable.call()
    print(("PASS " if before == failures else "FAIL ")+name)

func _new(seed: int = 17):
    var state = Model.new()
    state.new_run(seed)
    return state

func _enter(state, route: int = 0, choice: int = 2) -> void:
    _check(state.act("choose_route",route),"route should be available")
    _check(state.act("event_choice",choice),"event choice should be affordable")
    _check(state.act("continue"),"continue should enter expedition")

func _hero(state) -> Dictionary:
    for member in state.data.crew:
        if member.id == state.data.active_hero:
            return member
    return {}

func _size(resources: Dictionary) -> int:
    var result = 0
    for value in resources.values():
        result += int(value)
    return result

func _at_enemy(e: Dictionary, point: Vector2i) -> bool:
    for enemy in e.enemies:
        if Vector2i(int(enemy.x),int(enemy.y)) == point:
            return true
    return false

func _safe_delta(state, target: Vector2i) -> Vector2i:
    var e = state.data.expedition
    var start = Vector2i(int(e.player.x),int(e.player.y))
    var open = [start]
    var parents = {start:Vector2i(-1,-1)}
    var head = 0
    var closest = start
    var best_distance = absi(start.x-target.x)+absi(start.y-target.y)
    while head < open.size():
        var at: Vector2i = open[head]
        head += 1
        var distance = absi(at.x-target.x)+absi(at.y-target.y)
        if distance < best_distance:
            closest = at
            best_distance = distance
        if at == target:
            closest = at
            break
        for delta in Model.DIRECTIONS.values():
            var next: Vector2i = at+delta
            if next.x < 1 or next.y < 1 or next.x >= Model.WIDTH-1 or next.y >= Model.HEIGHT-1 or e.grid[next.y][next.x] != 0 or parents.has(next) or _at_enemy(e,next):
                continue
            parents[next] = at
            open.append(next)
    if closest == start:
        return Vector2i.ZERO
    while parents[closest] != start:
        closest = parents[closest]
    return closest-start

func _bot_event(state) -> void:
    var event = state.data.pending_event
    if event.context == "loot":
        for index in range(event.choices.size()):
            var incoming = event.choices[index].effects.get("loot",{})
            if _size(state.data.expedition.carried)+_size(incoming) <= int(state.data.expedition.capacity):
                state.act("event_choice",index)
                return
        return
    var choice = 2
    match event.id:
        "bridge": choice = 1 if int(state.data.resources.scrap) >= 3 else 2
        "survivors": choice = 0 if int(state.data.resources.scrap) >= 4 else 2
        "storm": choice = 1 if int(state.data.resources.scrap) >= 2 else 2
        "dealer": choice = 0 if int(state.data.resources.fuel) < 12 and int(state.data.resources.scrap) >= 5 else 2
        "water": choice = 1 if int(state.data.resources.water) < 9 and int(state.data.resources.scrap) >= 3 else 2
        "checkpoint": choice = 1 if int(state.data.resources.food) >= 9 else (0 if int(state.data.resources.ammo) >= 3 else 2)
        "beacon": choice = 0 if int(state.data.resources.water) >= 6 else (1 if int(state.data.resources.fuel) >= 4 else 2)
        "last_gate": choice = 0 if int(state.data.resources.scrap) >= 4 else 2
    if not state.act("event_choice",choice):
        state.act("event_choice",2)

func _bot_expedition(state) -> void:
    var e = state.data.expedition
    var player = Vector2i(int(e.player.x),int(e.player.y))
    var destination = Vector2i(1,5) if e.objective_done else Vector2i(11,5)
    var threatened = false
    for enemy in e.enemies:
        if enemy.intent == "strike" and Vector2i(int(enemy.intent_x),int(enemy.intent_y)) == player:
            threatened = true
    if threatened:
        var candidates = []
        for delta in Model.DIRECTIONS.values():
            var next: Vector2i = player+delta
            if next.x < 1 or next.y < 1 or next.x >= Model.WIDTH-1 or next.y >= Model.HEIGHT-1 or e.grid[next.y][next.x] != 0 or _at_enemy(e,next):
                continue
            var dangerous = false
            for enemy in e.enemies:
                if enemy.intent == "strike" and Vector2i(int(enemy.intent_x),int(enemy.intent_y)) == next:
                    dangerous = true
            if not dangerous:
                candidates.append({"delta":delta,"distance":absi(next.x-destination.x)+absi(next.y-destination.y)})
        candidates.sort_custom(func(a,b): return a.distance < b.distance)
        if not candidates.is_empty():
            state.act("move",candidates[0].delta)
            return
    var nearest = 999
    var target: Dictionary = {}
    for enemy in e.enemies:
        var distance = absi(int(enemy.x)-player.x)+absi(int(enemy.y)-player.y)
        if e.visible[int(enemy.y)][int(enemy.x)] and distance < nearest:
            nearest = distance
            target = enemy
    if not target.is_empty():
        if nearest <= 1 or (state.data.route.kind == "fort" and int(state.data.resources.ammo) > 0 and nearest <= 5):
            if state.act("attack"):
                return
        if nearest > 1 and int(target.cooldown) == 0:
            state.act("wait")
            return
        var neighbor = Vector2i.ZERO
        var distance_best = 999
        for delta in Model.DIRECTIONS.values():
            var next = Vector2i(int(target.x),int(target.y))+delta
            if next == player:
                continue
            var move_delta = _safe_delta(state,next)
            var distance = absi(next.x-player.x)+absi(next.y-player.y)
            if move_delta != Vector2i.ZERO and distance < distance_best:
                neighbor = move_delta
                distance_best = distance
        if neighbor != Vector2i.ZERO:
            state.act("move",neighbor)
            return
    if target.is_empty():
        for enemy in e.enemies:
            if int(enemy.alert) > 0:
                state.act("wait")
                return
    if not e.objective_done and absi(player.x-11)+absi(player.y-5) <= 1:
        if state.act("interact"):
            return
    if e.objective_done and player == Vector2i(1,5):
        state.act("return")
        return
    var delta = _safe_delta(state,destination)
    if delta != Vector2i.ZERO:
        state.act("move",delta)
    else:
        state.act("wait")

func _run_bot(seed: int, module: String = ""):
    var state = _new(seed)
    if not module.is_empty():
        _check(state.act("build",module), "starter wagon should be affordable")
    var turns = 0
    while not state.data.phase in ["won","lost"] and turns < 2500:
        turns += 1
        if state.data.phase == "expedition" and int(state.data.expedition.turns) == 60:
            print("TRACE seed=",seed," step=",state.data.step," player=",state.data.expedition.player," enemies=",state.data.expedition.enemies)
        if not state.data.pending_event.is_empty():
            _bot_event(state)
        elif state.data.phase == "travel_event":
            state.act("continue")
        elif state.data.phase == "base":
            if int(_hero(state).hp) < 50 and int(state.data.resources.medicine) > 0:
                state.act("heal")
            if int(state.data.hull) < 50 and int(state.data.resources.scrap) >= 4:
                state.act("repair")
            var route = 0
            if int(state.data.resources.food) < 8:
                route = 1
            elif int(state.data.resources.water) < 5:
                route = 2
            elif int(state.data.resources.fuel) < 7:
                route = 0
            else:
                var cost = 999
                for index in range(3):
                    var score = int(state.data.routes[index].fuel)*2+int(state.data.routes[index].danger)
                    if score < cost:
                        route = index
                        cost = score
            if not state.act("choose_route",route):
                for index in range(3):
                    if state.act("choose_route",index):
                        break
        else:
            _bot_expedition(state)
    if state.data.phase != "won":
        print("BOT seed=",seed," phase=",state.data.phase," step=",state.data.step," turns=",turns," hull=",state.data.hull," resources=",state.data.resources," hero=",_hero(state)," notice=",state.notice)
    return state

func _initialize() -> void:
    _case("seeded initial campaign and routes are deterministic",func():
        var a = _new(7)
        var b = _new(7)
        var c = _new(8)
        _check(a.snapshot() == b.snapshot(),"same seed should produce same campaign")
        _check(a.data.routes != c.data.routes,"different seed should change routes")
        _check(a.data.resources == {"fuel":18,"food":16,"water":10,"scrap":18,"medicine":2,"ammo":6},"initial resources")
        _check(a.data.train.slots == ["empty","empty","empty"],"three initial slots")
    )
    _case("JSON floats restore as integers; PRNG and maps survive round trip",func():
        var a = _new(83)
        a.act("choose_route",1)
        var json = JSON.parse_string(JSON.stringify(a.snapshot()))
        var b = _new(999)
        _check(b.restore(json),"valid JSON should restore")
        _check(b.snapshot() == a.snapshot(),"restored campaign should match")
        a.act("event_choice",2)
        b.act("event_choice",2)
        a.act("continue")
        b.act("continue")
        _check(a.snapshot() == b.snapshot(),"future generation should use saved PRNG")
        var copy = a.snapshot()
        copy.resources.fuel = 0
        _check(a.data.resources.fuel > 0,"snapshot should be independent")
        _check(b.restore(JSON.parse_string(JSON.stringify(a.snapshot()))),"expedition round trip should restore")
    )
    _case("corrupted saves are rejected transactionally",func():
        var a = _new()
        _enter(a)
        var before = a.snapshot()
        var old_notice = a.notice
        var variants = []
        var bad = before.duplicate(true)
        bad.resources.fuel = -1
        variants.append(bad)
        bad = before.duplicate(true)
        bad.expedition.player.x = 0
        variants.append(bad)
        bad = before.duplicate(true)
        bad.expedition.grid = [[0]]
        variants.append(bad)
        bad = before.duplicate(true)
        bad.crew[1].id = bad.crew[0].id
        variants.append(bad)
        bad = before.duplicate(true)
        bad.expedition.carried.food = 99
        variants.append(bad)
        bad = before.duplicate(true)
        bad.rng = 0.5
        variants.append(bad)
        bad = before.duplicate(true)
        bad.train.slots = ["serre","serre","empty"]
        variants.append(bad)
        variants.append({})
        variants.append(null)
        for value in variants:
            _check(not a.restore(value),"corrupted save should be rejected")
            _check(a.snapshot() == before and a.notice == old_notice,"failure must not contaminate state/notice")
    )
    _case("modules spend constrained scrap, add route weight and refund only half",func():
        var a = _new()
        var original = int(a.data.routes[0].fuel)
        _check(a.act("build",{"module":"serre","slot":0}),"serre should build")
        _check(a.data.resources.scrap == 8,"serre costs ten")
        _check(a.data.routes[0].fuel == original+1,"module weight affects route")
        _check(not a.act("build",{"module":"atelier","slot":1}),"shared budget prevents second expensive module")
        _check(a.act("dismantle",0),"module should dismantle")
        _check(a.data.resources.scrap == 13,"only five scrap recovered")
        _check(a.act("build","atelier"),"workshop should now be affordable")
        var fuel = int(a.data.resources.fuel)
        _check(not a.act("craft","fuel"),"fuel is never free")
        _check(a.data.resources.fuel == fuel,"failed craft must not replenish")
    )
    _case("replacement requires full cost before refund; crafting and role bonuses have costs",func():
        var a = _new()
        var save = a.snapshot()
        save.resources.scrap = 60
        _check(a.restore(save),"rich fixture")
        a.act("build",{"module":"serre","slot":0})
        a.act("build",{"module":"atelier","slot":1})
        var before = int(a.data.resources.scrap)
        _check(not a.act("build",{"module":"blindage","slot":0}),"replacement needs explicit consent token")
        _check(a.act("build",{"module":"blindage","slot":0,"replace":true}),"confirmed replacement")
        _check(a.data.resources.scrap == before-14+5,"new full cost, old half refund")
        a.act("assign","basile")
        before = int(a.data.resources.scrap)
        _check(a.act("craft","ammo"),"workshop recipe")
        _check(a.data.resources.scrap == before-2 and a.data.resources.ammo == 9,"mechanic saves one scrap")
        _check(a.act("assign","edda") and a.data.limits.bag == 12,"scout carries more")
    )
    _case("crew needs and greenhouse consume finite water",func():
        var a = _new()
        a.act("build","serre")
        a.act("choose_route",0)
        _check(a.data.resources.food == 15,"greenhouse adds2 before three meals")
        _check(a.data.resources.water == 6,"greenhouse2 plus crew2 waters")
        _check(not a.data.pending_event.is_empty(),"travel presents a saved choice")
        _check(not a.act("continue"),"unresolved event blocks expedition")
    )
    _case("healing at base consumes medicine and infirmary changes efficiency",func():
        var a = _new()
        var save = a.snapshot()
        save.crew[0].hp = 30
        save.resources.scrap = 30
        a.restore(save)
        _check(a.act("heal") and a.data.crew[0].hp == 58 and a.data.resources.medicine == 1,"base healing consumes remède")
        a.act("build","infirmerie")
        _check(a.act("heal") and a.data.crew[0].hp == 100 and a.data.resources.medicine == 0,"infirmary heals up to48")
        _check(not a.act("heal"),"no unlimited healing")
    )
    _case("fog has line-of-sight occlusion and remembered cells",func():
        var a = _new()
        _enter(a)
        a.data.expedition.enemies = []
        a.data.expedition.grid[5][2] = 1
        a.act("wait")
        _check(a.data.expedition.visible[5][2],"blocking wall itself visible")
        _check(not a.data.expedition.visible[5][3],"wall hides cell behind")
        a.data.expedition.grid[5][2] = 0
        for index in range(9):
            a.act("move","E")
        _check(a.data.expedition.seen[5][1] and not a.data.expedition.visible[5][1],"old train cell stays remembered")
    )
    _case("enemy strikes are announced one turn before damage and can be evaded",func():
        var a = _new()
        _enter(a)
        a.data.expedition.enemies = [a._enemy("test",2,5,30,false)]
        var hp = int(_hero(a).hp)
        a.act("wait")
        _check(a.data.expedition.enemies[0].intent == "strike" and _hero(a).hp == hp,"warning must precede damage")
        a.act("move","N")
        _check(_hero(a).hp == hp,"moving out of announced cell evades")
        for index in range(4):
            a.act("wait")
        _check(_hero(a).hp < hp,"remaining on an announced cell is dangerous")
    )
    _case("ranged attacks consume ammo; melee does not",func():
        var a = _new()
        _enter(a)
        a.data.expedition.enemies = [a._enemy("test",4,5,9,false)]
        a._vision()
        a.act("attack")
        _check(a.data.resources.ammo == 5,"ranged shot costs one")
        a.data.expedition.enemies = [a._enemy("test",2,5,9,false)]
        a._vision()
        a.act("attack")
        _check(a.data.resources.ammo == 5,"melee preserves scarce ammunition")
    )
    _case("loot must be carried home and the retreat abandons it",func():
        var a = _new()
        _enter(a,1)
        a.data.expedition.enemies = []
        a.data.expedition.player.x = 10
        var food = int(a.data.resources.food)
        _check(a.act("interact"),"objective should open loot choice")
        _check(a.act("event_choice",0),"primary lot fits nine-unit bag")
        _check(a.data.expedition.carried.food == 9 and a.data.resources.food == food,"loot not banked remotely")
        _check(not a.act("return"),"remote return is not allowed")
        a.act("retreat")
        _check(a.data.phase == "base" and a.data.step == 0 and a.data.resources.food == food,"retreat loses loot and progress")
    )
    _case("inventory overflow refuses the lot but allows an alternative choice",func():
        var a = _new()
        _enter(a,1)
        a.data.expedition.enemies = []
        a.data.expedition.player.x = 10
        a.data.expedition.carried.scrap = 1
        a.act("interact")
        _check(not a.act("event_choice",0),"nine foods plus scrap exceed port")
        _check(a.act("event_choice",1),"smaller mixed lot should fit")
        _check(_size(a.data.expedition.carried) == 8,"limited carried inventory")
    )
    _case("dormitory enables a fourth survivor and cannot be removed while occupied",func():
        var a = _new()
        a.act("build","dortoir")
        a.data.step = 1
        a._make_routes()
        a.act("choose_route",1)
        _check(a.act("event_choice",1),"dormitory should allow recruitment")
        _check(a.data.crew.size() == 4,"fourth survivor joined")
        a.act("continue")
        a.act("retreat")
        _check(not a.act("dismantle",0),"occupied dormitory cannot be removed")
    )
    _case("passive camp waiting loses rather than completing the campaign",func():
        var a = _new()
        for index in range(100):
            if a.data.phase == "lost":
                break
            a.act("wait")
        _check(a.data.phase == "lost" and a.data.step == 0,"passivity should exhaust resources and hull")
        _check(not a.act("choose_route",0),"terminal state cannot keep generating loot")
    )
    _case("sight is symmetric and closed corners block visibility",func():
        var a = _new(19)
        _enter(a)
        var grid = a.data.expedition.grid
        for ay in range(1,Model.HEIGHT-1):
            for ax in range(1,Model.WIDTH-1):
                if grid[ay][ax] == 1: continue
                for by in range(1,Model.HEIGHT-1):
                    for bx in range(1,Model.WIDTH-1):
                        if grid[by][bx] == 1: continue
                        _check(a._line_clear(grid,ax,ay,bx,by) == a._line_clear(grid,bx,by,ax,ay),"player and enemy see the same unobstructed line")
        grid[1][2] = 1
        grid[2][1] = 1
        grid[1][1] = 0
        grid[2][2] = 0
        _check(not a._line_clear(grid,1,1,2,2),"a closed wall corner stops a diagonal ray")
    )
    _case("fuel defeat respects dismantling and workshop recovery",func():
        var a = _new(7)
        _check(a.act("build","blindage"),"install heavy armour")
        for route in a.data.routes: route.base_fuel = 2
        a.data.resources.fuel = 1
        a._refresh()
        a._check_loss()
        _check(a.data.phase == "base","removable weight must not cause premature defeat")
        _check(a.act("dismantle",0),"remove heavy armour")
        _check(a.act("choose_route",0),"lighter convoi can depart legally")
        var b = _new(7)
        for route in b.data.routes: route.base_fuel = 2
        b.data.resources.fuel = 0
        b._refresh()
        b._check_loss()
        _check(b.data.phase == "base","construction and manufacturing can rescue an empty tank")
        _check(b.act("assign","basile"),"select mechanic")
        _check(b.act("build","atelier"),"build affordable atelier")
        _check(b.act("craft","fuel"),"manufacture fuel from finite supplies")
        _check(b.act("choose_route",0),"recovered convoi can depart")
        var c = _new()
        c.data.resources.fuel = 0
        c.data.resources.scrap = 0
        c._check_loss()
        _check(c.data.phase == "lost","unrecoverable fuel exhaustion still ends the run")
    )
    _case("legal decisions can win all eight stages including the final threat",func():
        for seed in [1,2,3,7,19,41,83,217]:
            var a = _run_bot(seed)
            _check(a.data.phase == "won" and a.data.step == 8,"bot campaign should win seed %d" % seed)
            var b = _new()
            _check(b.restore(JSON.parse_string(JSON.stringify(a.snapshot()))),"terminal campaign should round trip")
    )
    _case("different starter wagons support complete legal campaigns",func():
        for module in ["serre","blindage","atelier"]:
            for seed in [1,7,41]:
                var a = _run_bot(seed,module)
                _check(a.data.phase == "won" and a.data.step == 8, "starter %s must support a winning route on seed %d" % [module,seed])
    )
    print("STATE TESTS: %d cases, %d failures" % [cases,failures])
    quit(1 if failures else 0)
