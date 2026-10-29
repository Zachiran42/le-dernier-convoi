extends Control
## UI tactile à résolution logique fixe. Le modèle est indépendant du rendu.
const Model = preload("res://scripts/convoi_state.gd")
const SAVE_PATH = "user://convoi-save.json"
const INK = Color("#0c171d")
const PANEL = Color("#15262e")
const PANEL_LIGHT = Color("#1b333b")
const LINE = Color("#31505a")
const PAPER = Color("#e8e5d7")
const MUTED = Color("#9aafb0")
const AMBER = Color("#e9b36c")
const MINT = Color("#8dc7ad")
const RED = Color("#f18b7c")
const RESOURCE_NAMES = {"fuel":"carburant", "food":"rations", "water":"eau", "scrap":"ferraille", "medicine":"soins", "ammo":"munitions"}
const MODULE_MARKS = {"serre":"S", "citerne":"C", "atelier":"A", "blindage":"B", "infirmerie":"+", "dortoir":"D"}
var model = Model.new()
var screen = "home"
var base_tab = "train"
var selected_slot = 0
var buttons: Array[Dictionary] = []
var font: Font
var keyart: Texture2D
var saved_run = false
var paused = false
var help_open = false
var credits_open = false
var confirm_action = ""
var toast = ""
var toast_timer = 0.0
var visual_time = 0.0
var pointer_start = Vector2.ZERO
var pointer_down = false
var touch_used = false
var aim = Vector2i(1, 0)
var ui_scale = 1.0
var ui_offset = Vector2.ZERO
var last_phase = ""

func _ready() -> void:
	Engine.max_fps = 30
	font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://art/key-art.png"):
		keyart = load("res://art/key-art.png")
	get_tree().auto_accept_quit = false
	model.new_run(0)
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var value = JSON.parse_string(file.get_as_text())
			saved_run = model.restore(value)
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	visual_time += delta
	if toast_timer > 0.0:
		toast_timer = maxf(0.0, toast_timer - delta)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if screen == "game":
			paused = true
			_save()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if help_open or credits_open:
			help_open = false
			credits_open = false
		elif not confirm_action.is_empty():
			confirm_action = ""
		elif screen == "game":
			paused = not paused
			_save()
		else:
			get_tree().quit()

func _save() -> void:
	if screen != "game":
		return
	var temporary = SAVE_PATH + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		_message("Sauvegarde indisponible sur cet appareil.")
		return
	file.store_string(JSON.stringify(model.snapshot()))
	file.flush()
	file.close()
	var result = DirAccess.rename_absolute(temporary, SAVE_PATH)
	if result != OK:
		_message("La sauvegarde n’a pas pu être finalisée.")
	else:
		saved_run = true

func _message(value: String) -> void:
	toast = value
	toast_timer = 4.5

func _action(action: String, arg: Variant = null) -> void:
	buttons.clear()
	var previous_notice = model.notice
	var previous_hp = int(_active_hero().get("hp", 0))
	var accepted = model.act(action, arg)
	_save()
	if accepted and not model.data.get("pending_event", {}).is_empty():
		toast_timer = 0.0
	elif not model.notice.is_empty() and (model.notice != previous_notice or not accepted or action not in ["move", "wait"] or int(_active_hero().get("hp", 0)) != previous_hp):
		_message(model.notice)
	if str(model.data.get("phase", "")) != last_phase:
		base_tab = "train"
		last_phase = str(model.data.get("phase", ""))
	queue_redraw()

func _to_ui(point: Vector2) -> Vector2:
	return (point - ui_offset) / ui_scale

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		touch_used = true
		if event.pressed:
			pointer_start = _to_ui(event.position)
			pointer_down = true
		elif pointer_down:
			pointer_down = false
			_pointer(pointer_start, _to_ui(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		if event.pressed:
			pointer_start = _to_ui(event.position)
			pointer_down = true
		elif pointer_down:
			pointer_down = false
			_pointer(pointer_start, _to_ui(event.position))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if help_open or credits_open:
				help_open = false
				credits_open = false
			elif not confirm_action.is_empty():
				confirm_action = ""
			elif screen == "game":
				paused = not paused
			return
		if screen != "game" or paused or help_open or credits_open or not confirm_action.is_empty():
			return
		var pending = model.data.get("pending_event", {})
		if not pending.is_empty():
			if event.keycode >= KEY_1 and event.keycode <= KEY_3:
				_action("event_choice", event.keycode - KEY_1)
			return
		if model.data.get("phase") != "expedition":
			if base_tab == "routes" and event.keycode >= KEY_1 and event.keycode <= KEY_3:
				_action("choose_route", event.keycode - KEY_1)
			return
		match event.keycode:
			KEY_LEFT, KEY_A, KEY_Q: _move(Vector2i(-1, 0))
			KEY_RIGHT, KEY_D: _move(Vector2i(1, 0))
			KEY_UP, KEY_W, KEY_Z: _move(Vector2i(0, -1))
			KEY_DOWN, KEY_S: _move(Vector2i(0, 1))
			KEY_E: _action("interact")
			KEY_F: _action("heal")
			KEY_SPACE: _action("attack")
			KEY_ENTER: _action("wait")
			KEY_R: _action("return")
		queue_redraw()

func _move(direction: Vector2i) -> void:
	aim = direction
	_action("move", direction)

func _pointer(start: Vector2, finish: Vector2) -> void:
	if start.distance_to(finish) > 46.0 and screen == "game" and model.data.get("phase") == "expedition" and not paused and not help_open and not credits_open and model.data.get("pending_event", {}).is_empty() and confirm_action.is_empty():
		var delta = finish - start
		_move(Vector2i(signi(int(delta.x)), 0) if absf(delta.x) > absf(delta.y) else Vector2i(0, signi(int(delta.y))))
		return
	for index in range(buttons.size() - 1, -1, -1):
		var item = buttons[index]
		if item.rect.has_point(finish):
			if item.enabled:
				_activate(item.id)
			else:
				_message(str(item.get("reason", "Ressources insuffisantes ou action indisponible. Consultez le coût indiqué.")))
			return
	if screen == "game" and model.data.get("phase") == "expedition" and not paused and not help_open and not credits_open and confirm_action.is_empty() and model.data.get("pending_event", {}).is_empty():
		var expedition = model.data.get("expedition", {})
		var tile = 672.0 / float(expedition.get("width", 13))
		var board = Rect2(24, 258, 672, tile * float(expedition.get("height", 11)))
		if board.has_point(finish):
			var player = expedition.get("player", {})
			var center = Vector2(24 + (float(player.get("x", 1)) + 0.5) * tile, 258 + (float(player.get("y", 1)) + 0.5) * tile)
			var offset = finish - center
			if offset.length() < tile * 0.45:
				_action("interact")
			else:
				_move(Vector2i(signi(int(offset.x)), 0) if absf(offset.x) > absf(offset.y) else Vector2i(0, signi(int(offset.y))))

func _activate(id: String) -> void:
	# Only the topmost overlay may handle an action, even before redraw.
	if not confirm_action.is_empty():
		if id not in ["confirm", "cancel"]: return
	elif help_open or credits_open:
		if id != "close": return
	elif paused:
		if id not in ["pause", "help", "home", "credits"]: return
	elif screen == "game" and not model.data.get("pending_event", {}).is_empty():
		if not id.begins_with("event:"): return
	buttons.clear()
	if id == "resume":
		screen = "game"
		paused = false
		last_phase = str(model.data.get("phase", "base"))
	elif id == "new":
		if saved_run:
			confirm_action = "new"
		else:
			_start_new()
	elif id == "confirm":
		var task = confirm_action
		confirm_action = ""
		if task == "new": _start_new()
		elif task == "retreat": _action("retreat")
		elif task.begins_with("build:"):
			_action("build", {"module":task.get_slice(":", 1), "slot":selected_slot})
		elif task.begins_with("replace:"):
			_action("build", {"module":task.get_slice(":", 1), "slot":selected_slot, "replace":true})
		elif task == "dismantle": _action("dismantle", selected_slot)
	elif id == "cancel":
		confirm_action = ""
	elif id == "pause":
		paused = not paused
		_save()
	elif id == "home":
		_save()
		screen = "home"
		paused = false
	elif id == "help":
		help_open = true
	elif id == "credits":
		credits_open = true
	elif id == "close":
		help_open = false
		credits_open = false
	elif id.begins_with("tab:"):
		base_tab = id.get_slice(":", 1)
	elif id.begins_with("slot:"):
		selected_slot = int(id.get_slice(":", 1))
	elif id.begins_with("route:"):
		_action("choose_route", int(id.get_slice(":", 1)))
	elif id.begins_with("event:"):
		_action("event_choice", int(id.get_slice(":", 1)))
	elif id.begins_with("build:"):
		var module_id = id.get_slice(":", 1)
		var slots = model.data.get("train", {}).get("slots", [])
		if selected_slot < slots.size() and str(slots[selected_slot]) != "empty" and not str(slots[selected_slot]).is_empty():
			confirm_action = "replace:" + module_id
		else:
			confirm_action = "build:" + module_id
	elif id.begins_with("craft:"):
		_action("craft", id.get_slice(":", 1))
	elif id.begins_with("assign:"):
		_action("assign", id.get_slice(":", 1))
	elif id.begins_with("move:"):
		var direction = id.get_slice(":", 1)
		_move({"N":Vector2i.UP,"S":Vector2i.DOWN,"W":Vector2i.LEFT,"E":Vector2i.RIGHT}[direction])
	elif id == "attack": _action("attack")
	elif id == "retreat": confirm_action = "retreat"
	elif id == "dismantle": confirm_action = "dismantle"
	else:
		_action(id)
	queue_redraw()

func _start_new() -> void:
	model.new_run(int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec()))
	screen = "game"
	base_tab = "train"
	selected_slot = 0
	paused = false
	_save()
	_message("Le phare du Col répond encore. Préparez le convoi, puis choisissez une route.")

func _draw() -> void:
	if not font:
		return
	buttons.clear()
	ui_scale = minf(size.x / 720.0, size.y / 1280.0)
	ui_offset = (size - Vector2(720, 1280) * ui_scale) * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	draw_set_transform(ui_offset, 0, Vector2.ONE * ui_scale)
	if screen == "home":
		_draw_home()
	else:
		_draw_header()
		var phase = str(model.data.get("phase", "base"))
		if phase == "expedition":
			_draw_expedition()
		elif phase == "won" or phase == "lost":
			_draw_ending(phase == "won")
		else:
			_draw_base()
		if not model.data.get("pending_event", {}).is_empty():
			_draw_event()
		if paused:
			_draw_pause()
	if help_open:
		_draw_help()
	if credits_open:
		_draw_credits()
	if not confirm_action.is_empty():
		_draw_confirmation()
	if toast_timer > 0.0 and not help_open and not credits_open and confirm_action.is_empty():
		var tactical = screen == "game" and model.data.get("phase") == "expedition" and model.data.get("pending_event", {}).is_empty()
		var notice_rect = Rect2(24, 842, 672, 94) if tactical else Rect2(24, 172, 672, 72)
		_panel(notice_rect, Color("#223b42"), LINE, 12)
		_paragraph(toast, notice_rect.position + Vector2(16, 26), 636, 19, PAPER, 25, 3 if tactical else 2)
	draw_set_transform(Vector2.ZERO)

func _panel(rect: Rect2, color: Color = PANEL, border: Color = LINE, radius: int = 14) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func _text(value: String, point: Vector2, pixels: int = 20, color: Color = PAPER) -> void:
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pixels, color)

func _center(value: String, rect: Rect2, pixels: int = 20, color: Color = PAPER) -> void:
	var width = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	_text(value, Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + rect.size.y * 0.5 + pixels * 0.36), pixels, color)

func _paragraph(value: String, point: Vector2, width: float, pixels: int = 20, color: Color = MUTED, line_height: float = 29.0, max_lines: int = 20) -> float:
	var y = point.y
	var count = 0
	for raw_line in value.split("\n"):
		var line = ""
		for word in raw_line.split(" "):
			var trial = word if line.is_empty() else line + " " + word
			if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x > width and not line.is_empty():
				_text(line, Vector2(point.x, y), pixels, color)
				y += line_height
				count += 1
				line = word
				if count >= max_lines:
					return y
			else:
				line = trial
		if count >= max_lines:
			return y
		_text(line, Vector2(point.x, y), pixels, color)
		y += line_height
		count += 1
	return y

func _button(id: String, rect: Rect2, title: String, subtitle: String = "", enabled: bool = true, primary: bool = false) -> void:
	var color = AMBER if primary else PANEL_LIGHT
	if not enabled:
		color = Color("#142229")
	_panel(rect, color, AMBER if primary else LINE, 12)
	var ink = INK if primary else PAPER
	if not enabled:
		ink = Color("#728285")
	if title in ["←", "↑", "↓", "→"]:
		var direction = {"←":Vector2.LEFT, "↑":Vector2.UP, "↓":Vector2.DOWN, "→":Vector2.RIGHT}[title]
		var perpendicular = Vector2(-direction.y, direction.x)
		var center = rect.get_center()
		draw_line(center - direction * 20, center + direction * 20, ink, 4, true)
		draw_line(center + direction * 20, center + direction * 7 + perpendicular * 12, ink, 4, true)
		draw_line(center + direction * 20, center + direction * 7 - perpendicular * 12, ink, 4, true)
	elif subtitle.is_empty():
		_center(title, rect, 22, ink)
	else:
		_center(title, Rect2(rect.position.x, rect.position.y + 8, rect.size.x, 29), 21, ink)
		_center(subtitle, Rect2(rect.position.x + 5, rect.position.y + 37, rect.size.x - 10, 25), 15, INK if primary else MUTED)
	buttons.append({"id":id, "rect":rect, "enabled":enabled})

func _bar(rect: Rect2, value: float, maximum: float, color: Color) -> void:
	_panel(rect, INK, INK, int(rect.size.y / 2))
	var fraction = clampf(value / maxf(maximum, 1.0), 0.0, 1.0)
	if fraction > 0.0:
		_panel(Rect2(rect.position, Vector2(rect.size.x * fraction, rect.size.y)), color, color, int(rect.size.y / 2))

func _cost(value: Variant) -> String:
	if value is String:
		return value
	if not value is Dictionary:
		return ""
	var parts: PackedStringArray = []
	for key in value:
		if int(value[key]) == 0: continue
		parts.append(str(int(value[key])) + " " + str(RESOURCE_NAMES.get(key, key)))
	return " · ".join(parts)

func _can_pay(cost: Variant) -> bool:
	if not cost is Dictionary:
		return true
	var resources = model.data.get("resources", {})
	for key in cost:
		if float(resources.get(key, 0)) < float(cost[key]):
			return false
	return true

func _active_hero() -> Dictionary:
	for hero in model.data.get("crew", []):
		if str(hero.get("id")) == str(model.data.get("active_hero")):
			return hero
	return {}

func _draw_home() -> void:
	if keyart:
		draw_texture_rect(keyart, Rect2(-350, 0, 1420, 800), false, Color(0.8, 0.9, 0.9))
	for i in range(24):
		draw_rect(Rect2(0, 470 + i * 15, 720, 18), Color(0.047, 0.09, 0.114, float(i) / 24.0))
	_text("UNE LUMIÈRE AU BOUT DES RAILS", Vector2(40, 82), 18, AMBER)
	_text("LE DERNIER", Vector2(38, 615), 68)
	_text("CONVOI", Vector2(38, 690), 82)
	_text("VALLÉE DES CENDRES", Vector2(42, 742), 20, AMBER)
	_paragraph("Votre refuge avance dans la brume. Chaque wagon est une promesse. Chaque détour a un prix.", Vector2(42, 796), 626, 24, MUTED, 34)
	if saved_run:
		_button("resume", Rect2(40, 905, 640, 74), "REPRENDRE LE VOYAGE", "Étape " + str(int(model.data.get("step", 0))) + " / 8 · sauvegarde locale", true, true)
		_button("new", Rect2(40, 995, 640, 82), "Nouveau convoi")
	else:
		_button("new", Rect2(40, 905, 640, 80), "PRENDRE LES COMMANDES", "Un train · trois wagons · huit étapes", true, true)
		_button("help", Rect2(40, 1002, 640, 82), "Comment survivre")
	_button("help", Rect2(40, 1090, 310, 82), "Guide de voyage")
	_button("credits", Rect2(370, 1090, 310, 82), "Crédits et licence")
	_center("0.1.0 · PREMIÈRE RÉGION JOUABLE · HORS LIGNE", Rect2(25, 1170, 670, 36), 15, MUTED)

func _draw_header() -> void:
	_text("LE DERNIER CONVOI", Vector2(25, 44), 24)
	_text("VALLÉE DES CENDRES", Vector2(26, 70), 14, AMBER)
	_button("pause", Rect2(570, 3, 126, 82), "Ⅱ PAUSE")
	var resource = model.data.get("resources", {})
	var keys = ["fuel", "food", "water", "scrap", "medicine", "ammo"]
	var titles = ["CARBURANT", "RATIONS", "EAU", "FERRAILLE", "SOINS", "MUNITIONS"]
	for i in range(6):
		var rect = Rect2(24 + i * 114, 91, 104, 77)
		_panel(rect, PANEL, LINE, 10)
		_text(titles[i], rect.position + Vector2(9, 23), 16, MUTED)
		_text(str(int(resource.get(keys[i], 0))), rect.position + Vector2(10, 58), 28, AMBER if i == 0 else PAPER)

func _draw_base() -> void:
	if model.data.get("phase") == "travel_event" and model.data.get("pending_event", {}).is_empty():
		_draw_arrival()
		return
	var step = int(model.data.get("step", 0))
	_text("ÉTAPE " + str(step) + " / 8", Vector2(28, 209), 17, MINT)
	_text("Le prochain départ se prépare ici.", Vector2(28, 237), 26)
	_button("tab:train", Rect2(24, 246, 218, 88), "LE CONVOI", "", true, base_tab == "train")
	_button("tab:routes", Rect2(252, 246, 218, 88), "LES ROUTES", "", true, base_tab == "routes")
	_button("tab:crew", Rect2(480, 246, 216, 88), "L’ÉQUIPAGE", "", true, base_tab == "crew")
	if base_tab == "routes":
		_draw_routes()
	elif base_tab == "crew":
		_draw_crew()
	else:
		_draw_train()

func _draw_train() -> void:
	var slots = model.data.get("train", {}).get("slots", ["empty", "empty", "empty"])
	_panel(Rect2(24, 340, 672, 228), Color("#12242c"), LINE, 16)
	_text("UN REFUGE À VOTRE IMAGE", Vector2(44, 372), 16, MUTED)
	for i in range(16):
		draw_line(Vector2(39 + i * 41, 503), Vector2(55 + i * 41, 521), Color("#344954"), 5)
	draw_line(Vector2(39, 505), Vector2(679, 505), Color("#70828b"), 4)
	_draw_locomotive(Vector2(52, 414))
	for i in range(3):
		var id = str(slots[i]) if i < slots.size() else "empty"
		var module = Model.MODULES.get(id, {})
		var rect = Rect2(190 + i * 158, 400, 142, 94)
		_panel(rect, PANEL_LIGHT, AMBER if i == selected_slot else LINE, 8)
		for w in range(3):
			draw_rect(Rect2(rect.position + Vector2(17 + w * 38, 18), Vector2(25, 30)), Color("#cc9756") if id != "empty" else Color("#243d47"))
		for wheel in [31, 110]:
			draw_circle(rect.position + Vector2(wheel, 96), 12, INK)
			draw_arc(rect.position + Vector2(wheel, 96), 12, 0, TAU, 16, MUTED, 2)
		_center(str(module.get("name", "À AMÉNAGER")), Rect2(rect.position + Vector2(2, 58), Vector2(138, 27)), 16, PAPER)
		buttons.append({"id":"slot:" + str(i), "rect":Rect2(rect.position, Vector2(142, 123)), "enabled":true})
	var hull = float(model.data.get("hull", 100))
	_text("COQUE " + str(int(hull)) + " %", Vector2(43, 550), 14, MINT if hull > 40 else RED)
	_bar(Rect2(169, 540, 504, 10), hull, 100, MINT if hull > 40 else RED)
	_text("AMÉNAGER LE WAGON " + str(selected_slot + 1), Vector2(28, 608), 20)
	_text("Chaque module ajoute du poids au convoi.", Vector2(28, 638), 17, MUTED)
	var module_ids = Model.MODULES.keys()
	for i in range(mini(module_ids.size(), 6)):
		var id = str(module_ids[i])
		var item = Model.MODULES[id]
		var rect = Rect2(24 + (i % 2) * 344, 659 + (i / 2) * 112, 328, 100)
		_panel(rect, PANEL, LINE, 12)
		_text(str(item.get("name", id)).to_upper(), rect.position + Vector2(16, 27), 20, PAPER if _can_pay(item.get("cost", {})) else MUTED)
		_text(_cost(item.get("cost", {})), rect.position + Vector2(16, 51), 16, AMBER)
		_paragraph(str(item.get("description", "")), rect.position + Vector2(16, 73), 296, 18, MUTED, 21, 2)
		buttons.append({"id":"build:" + id,"rect":rect,"enabled":_can_pay(item.get("cost", {}))})
	_button("repair", Rect2(24, 1010, 326, 88), "RÉPARER LA COQUE", "4 ferrailles · +24 / +36 mécano", int(model.data.get("hull", 100)) < 100 and _can_pay({"scrap":4}))
	_button("dismantle", Rect2(370, 1010, 326, 88), "DÉMONTER", "Récupère 50 % du coût", str(slots[selected_slot]) != "empty")
	_button("tab:routes", Rect2(24, 1110, 672, 88), "CHOISIR LA PROCHAINE ROUTE", "Le voyage consomme des réserves.", true, true)

func _draw_locomotive(origin: Vector2) -> void:
	_panel(Rect2(origin, Vector2(119, 77)), Color("#46636a"), MUTED, 7)
	draw_rect(Rect2(origin + Vector2(10, -20), Vector2(45, 36)), Color("#597c80"))
	draw_rect(Rect2(origin + Vector2(17, -12), Vector2(27, 22)), AMBER)
	draw_rect(Rect2(origin + Vector2(85, -12), Vector2(17, 25)), Color("#6e817f"))
	for i in range(3):
		draw_circle(origin + Vector2(20 + i * 38, 79), 13, INK)
		draw_arc(origin + Vector2(20 + i * 38, 79), 13, 0, TAU, 18, MUTED, 2)
	draw_circle(origin + Vector2(112, 36), 7, AMBER)
	for i in range(3):
		var shift = fmod(visual_time * 11.0 + i * 17.0, 52.0)
		draw_circle(origin + Vector2(93 - shift * 0.5, -21 - shift), 8 + shift * 0.16, Color(0.40, 0.54, 0.57, (1.0 - shift / 52.0) * 0.4))

func _draw_routes() -> void:
	_text("QUEL RISQUE POUVEZ-VOUS PRENDRE ?", Vector2(28, 362), 18, AMBER)
	_paragraph("Le carburant affiché inclut le poids des wagons. Pensez aussi aux besoins de l’équipage à chaque départ.", Vector2(28, 395), 660, 18, MUTED, 26, 2)
	var alive = 0
	for member in model.data.get("crew", []):
		if float(member.get("hp", 0)) > 0: alive += 1
	_text("Par départ : " + str(alive) + " rations · " + str(int(ceil(float(alive) / 2.0))) + " eaux (+2 si serre active)", Vector2(28, 449), 16, AMBER)
	var routes = model.data.get("routes", [])
	for i in range(mini(routes.size(), 3)):
		var route = routes[i]
		var rect = Rect2(24, 468 + i * 226, 672, 208)
		_panel(rect, PANEL, LINE, 15)
		_text("0" + str(i + 1) + "   " + str({"depot":"DÉPÔT", "farm":"VERGER", "well":"SOURCE", "fort":"FORT"}.get(str(route.get("kind", "")), "ROUTE")), rect.position + Vector2(21, 32), 15, AMBER)
		_text(str(route.get("name", "Destination")), rect.position + Vector2(21, 72), 28)
		_paragraph(str(route.get("description", "")), rect.position + Vector2(21, 105), 620, 18, MUTED, 25, 2)
		_text("Lot annoncé : " + _cost(route.get("loot", {})), rect.position + Vector2(21, 150), 16, MINT)
		var cost = int(route.get("fuel", 0))
		var danger = int(route.get("danger", 1))
		_text(str(cost) + " CARBURANT", rect.position + Vector2(21, 180), 17, AMBER)
		_text("DANGER " + "!".repeat(clampi(danger, 1, 5)), rect.position + Vector2(241, 180), 17, RED if danger >= 3 else MINT)
		buttons.append({"id":"route:" + str(i), "rect":rect, "enabled":float(model.data.get("resources", {}).get("fuel", 0)) >= cost})
		_button("route:" + str(i), Rect2(rect.position + Vector2(455, 152), Vector2(195, 43)), "PARTIR", "", float(model.data.get("resources", {}).get("fuel", 0)) >= cost, true)
	if int(model.data.get("step", 0)) >= 7:
		_text("DERNIER TRONÇON · LA MENACE DU COL VOUS ATTEND", Vector2(28, 1184), 15, RED)

func _draw_crew() -> void:
	_text("CEUX QUI COMPTENT SUR VOUS", Vector2(28, 361), 20)
	_text("Choisissez la personne qui mènera l’expédition.", Vector2(28, 393), 18, MUTED)
	var crew = model.data.get("crew", [])
	for i in range(mini(crew.size(), 4)):
		var hero = crew[i]
		var rect = Rect2(24, 418 + i * 121, 672, 108)
		_panel(rect, PANEL, AMBER if str(hero.get("id")) == str(model.data.get("active_hero")) else LINE, 14)
		draw_circle(rect.position + Vector2(45, 43), 23, Color("#355460"))
		_center(str(hero.get("name", "?" )).left(1), Rect2(rect.position + Vector2(20, 17), Vector2(50, 48)), 27, AMBER)
		_text(str(hero.get("name", "Survivant")), rect.position + Vector2(85, 36), 25)
		_text(str({"pilote":"Pilote · trajet −1 carburant", "mecano":"Mécano · recettes −1 ferraille", "eclaireuse":"Éclaireuse · sac et vision accrus"}.get(str(hero.get("role", "")), "Équipage")), rect.position + Vector2(85, 63), 16, MUTED)
		var hp = float(hero.get("hp", 0))
		var maximum = float(hero.get("max_hp", 100))
		_bar(Rect2(rect.position + Vector2(85, 79), Vector2(325, 9)), hp, maximum, MINT if hp > 30 else RED)
		_text(str(int(hp)) + "/" + str(int(maximum)), rect.position + Vector2(424, 88), 16, MUTED)
		buttons.append({"id":"assign:" + str(hero.get("id", "")), "rect":rect, "enabled":hp > 0})
		_button("assign:" + str(hero.get("id", "")), Rect2(rect.position + Vector2(514, 23), Vector2(135, 60)), "CHOISIR", "", hp > 0)
	var y = 935.0
	_text("FABRICATION AU CONVOI", Vector2(28, y), 18, AMBER)
	var recipe_ids = Model.RECIPES.keys()
	for i in range(mini(recipe_ids.size(), 4)):
		var recipe_id = str(recipe_ids[i])
		var recipe = Model.RECIPES[recipe_id]
		var effective_cost = recipe.get("cost", {}).duplicate(true)
		if str(_active_hero().get("role", "")) == "mecano" and effective_cost.has("scrap"):
			effective_cost.scrap = maxi(1, int(effective_cost.scrap) - 1)
		var ready = str(recipe.get("requires", "")) in model.data.get("train", {}).get("slots", [])
		var maximum = recipe_id == "blade" and int(model.data.get("blade", 0)) >= 2
		var subtitle = "Atelier requis" if not ready else ("Lame maximale" if maximum else _cost(effective_cost))
		_button("craft:" + recipe_id, Rect2(24 + (i % 2) * 344, y + 22 + (i / 2) * 90, 328, 82), str(recipe.get("name", recipe_id)), subtitle, ready and not maximum and _can_pay(effective_cost))
	_button("heal", Rect2(24, 1134, 326, 88), "SOIGNER", "1 soin · bonus infirmerie")
	_button("help", Rect2(370, 1134, 326, 88), "CONSEILS", "Ne partez pas sans réserves")

func _draw_expedition() -> void:
	var expedition = model.data.get("expedition", {})
	if expedition.is_empty():
		return
	var route = model.data.get("route", {})
	var hero = _active_hero()
	_text(str(route.get("name", "EXPÉDITION")), Vector2(26, 208), 26)
	_text(str(hero.get("name", "Éclaireur")) + "  " + str(int(hero.get("hp", 0))) + "/" + str(int(hero.get("max_hp", 100))) + " PV", Vector2(26, 238), 18, MINT)
	var capacity = int(expedition.get("capacity", 6))
	var carried = expedition.get("carried", {})
	var load_count = 0
	if carried is Dictionary:
		for key in carried:
			load_count += int(carried[key])
	_text("SAC " + str(load_count) + " / " + str(capacity), Vector2(498, 238), 18, AMBER)
	var width = int(expedition.get("width", 13))
	var height = int(expedition.get("height", 11))
	var tile = 672.0 / float(width)
	var origin = Vector2(24, 258)
	var player = expedition.get("player", {"x":1,"y":1})
	_panel(Rect2(origin - Vector2(3, 3), Vector2(678, tile * height + 6)), Color("#060f15"), LINE, 8)
	var grid = expedition.get("grid", [])
	var seen = expedition.get("seen", [])
	var visible = expedition.get("visible", [])
	for y in range(height):
		for x in range(width):
			var point = origin + Vector2(x, y) * tile
			var explored = bool(seen[y][x]) if y < seen.size() and x < seen[y].size() else false
			var lit = bool(visible[y][x]) if y < visible.size() and x < visible[y].size() else false
			if not explored:
				continue
			var wall = int(grid[y][x]) == 1
			var kind = str(route.get("kind", "depot"))
			var floor_color = {"farm":Color("#293b31"), "well":Color("#1c3546"), "fort":Color("#352b31")}.get(kind, Color("#1d3339"))
			var color = Color("#394b50") if wall else floor_color
			if not lit:
				color = color.darkened(0.72)
			draw_rect(Rect2(point + Vector2(1, 1), Vector2.ONE * (tile - 2)), color)
			if wall and lit:
				draw_line(point + Vector2(3, 4), point + Vector2(tile - 3, 4), Color("#69817f"), 2)
			if not wall and lit and (x * 11 + y * 3) % 4 == 0:
				draw_line(point + Vector2(8, tile * 0.7), point + Vector2(16, tile * 0.7 - 5), Color("#304a4f"), 1)
	var exit_cell = expedition.get("exit", {"x":1,"y":1})
	var exit_point = origin + Vector2(float(exit_cell.get("x", 1)) + 0.5, float(exit_cell.get("y", 1)) + 0.5) * tile
	if _cell_seen(seen, int(exit_cell.get("x", 1)), int(exit_cell.get("y", 1))):
		draw_rect(Rect2(exit_point - Vector2.ONE * tile * 0.37, Vector2.ONE * tile * 0.74), Color("#3b645b"))
		_center("TRAIN", Rect2(exit_point - Vector2.ONE * tile * 0.5, Vector2.ONE * tile), 11, MINT)
	for node in expedition.get("nodes", []):
		var x = int(node.get("x", 0))
		var y = int(node.get("y", 0))
		if bool(node.get("taken", false)) or not _cell_seen(visible, x, y):
			continue
		var point = origin + Vector2(x + 0.5, y + 0.5) * tile
		var kind = str(node.get("kind", "cache"))
		var color = AMBER
		var symbol = "+"
		if kind in ["objective", "signal", "relay"]:
			symbol = "!"
			color = MINT
		elif kind in ["fuel", "citerne"]:
			symbol = "C"
		elif kind in ["survivor", "survivant"]:
			symbol = "?"
		draw_circle(point, tile * 0.28, color.darkened(0.5))
		draw_arc(point, tile * 0.29, 0, TAU, 16, color, 2)
		_center(symbol, Rect2(point - Vector2.ONE * tile * 0.4, Vector2.ONE * tile * 0.8), int(tile * 0.43), color)
	for enemy in expedition.get("enemies", []):
		var ex = int(enemy.get("x", 0))
		var ey = int(enemy.get("y", 0))
		if float(enemy.get("hp", 0)) <= 0 or not _cell_seen(visible, ex, ey):
			continue
		if str(enemy.get("intent", "")) == "strike":
			var tx = int(enemy.get("intent_x", ex))
			var ty = int(enemy.get("intent_y", ey))
			if _cell_seen(visible, tx, ty):
				var danger_rect = Rect2(origin + Vector2(tx, ty) * tile + Vector2(2, 2), Vector2.ONE * (tile - 4))
				draw_rect(danger_rect, Color(0.9, 0.28, 0.24, 0.35 + sin(visual_time * 5.0) * 0.10))
				draw_rect(danger_rect, RED, false, 2)
		var point = origin + Vector2(ex + 0.5, ey + 0.5) * tile
		var boss = bool(enemy.get("boss", false)) or str(enemy.get("kind", "")) == "boss"
		var radius = tile * (0.38 if boss else 0.29)
		draw_circle(point, radius, Color("#7c5554"))
		draw_circle(point + Vector2(-radius * 0.3, -4), 3, RED)
		draw_circle(point + Vector2(radius * 0.3, -4), 3, RED)
		_bar(Rect2(point + Vector2(-tile * 0.32, tile * 0.34), Vector2(tile * 0.64, 4)), float(enemy.get("hp", 1)), float(enemy.get("max_hp", 1)), RED)
	var player_point = origin + Vector2(float(player.get("x", 1)) + 0.5, float(player.get("y", 1)) + 0.5) * tile
	draw_circle(player_point, tile * 0.44, Color(0.9, 0.7, 0.4, 0.12))
	draw_circle(player_point, tile * 0.25, Color("#89b6b6"))
	draw_circle(player_point + Vector2(0, -4), tile * 0.14, PAPER)
	draw_circle(player_point + Vector2(aim) * tile * 0.3, 5, AMBER)
	var end_y = origin.y + height * tile
	_text("ROUGE : FRAPPE AU PROCHAIN TOUR", Vector2(27, end_y + 24), 14, RED)
	var status = "Objectif accompli : ramenez votre butin au train." if bool(expedition.get("objective_done", false)) else "Repérez le signal. Les caches sont facultatives."
	_paragraph(status, Vector2(27, end_y + 54), 661, 18, MINT if bool(expedition.get("objective_done", false)) else MUTED, 24, 2)
	var loot_text = _cost(carried)
	if loot_text.is_empty():
		loot_text = "Sac vide · touchez une cache, puis INTERAGIR."
	_paragraph(loot_text, Vector2(27, 928), 661, 16, AMBER, 22, 1)
	_button("move:W", Rect2(24, 944, 156, 88), "←")
	_button("move:N", Rect2(196, 944, 156, 88), "↑")
	_button("move:S", Rect2(368, 944, 156, 88), "↓")
	_button("move:E", Rect2(540, 944, 156, 88), "→")
	_button("interact", Rect2(24, 1042, 326, 88), "INTERAGIR", "Cache · signal · sortie", true, true)
	_button("attack", Rect2(370, 1042, 326, 88), "ATTAQUER", "Cible proche · tir jusqu’à 5 cases")
	_button("heal", Rect2(24, 1140, 213, 88), "SOIN")
	_button("wait", Rect2(254, 1140, 213, 88), "ATTENDRE")
	_button("retreat", Rect2(484, 1140, 212, 88), "REPLI")

func _cell_seen(matrix: Variant, x: int, y: int) -> bool:
	return matrix is Array and y >= 0 and y < matrix.size() and x >= 0 and x < matrix[y].size() and bool(matrix[y][x])

func _dim() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.02, 0.045, 0.06, 0.94))

func _draw_event() -> void:
	_dim()
	var event = model.data.get("pending_event", {})
	_text("CHAQUE DÉCISION LAISSE UNE TRACE", Vector2(44, 118), 17, AMBER)
	_paragraph(str(event.get("title", "Un choix à faire")), Vector2(44, 183), 627, 36, PAPER, 45, 3)
	_paragraph(str(event.get("text", "")), Vector2(44, 325), 627, 23, MUTED, 34, 7)
	var choices = event.get("choices", [])
	for i in range(mini(choices.size(), 3)):
		var choice = choices[i]
		var rect = Rect2(32, 620 + i * 174, 656, 155)
		var requirement = str(choice.get("requires", ""))
		var affordable = _can_pay(choice.get("cost", {})) and (requirement.is_empty() or requirement in model.data.get("train", {}).get("slots", []))
		_panel(rect, PANEL, LINE, 14)
		_paragraph(str(i + 1) + ". " + str(choice.get("label", "Choisir")), rect.position + Vector2(20, 34), 612, 25, PAPER if affordable else MUTED, 30, 2)
		_paragraph(str(choice.get("description", "")), rect.position + Vector2(20, 81), 612, 18, MUTED, 25, 2)
		_text(_cost(choice.get("cost", {})), rect.position + Vector2(20, 136), 17, AMBER if affordable else RED)
		buttons.append({"id":"event:" + str(i),"rect":rect,"enabled":affordable})
	_center("Un coût affiché est payé une seule fois au choix.", Rect2(32, 1154, 656, 35), 17, MUTED)

func _draw_ending(won: bool) -> void:
	if keyart:
		draw_texture_rect(keyart, Rect2(-350, 192, 1420, 740), false, Color(0.5, 0.6, 0.6))
	draw_rect(Rect2(0, 500, 720, 780), Color(0.04, 0.08, 0.10, 0.90))
	_text("LE COL RÉPOND." if won else "LE CONVOI S’IMMOBILISE.", Vector2(35, 617), 35, AMBER if won else RED)
	var ending = str(model.data.get("ending", model.data.get("reason", "")))
	if ending.is_empty():
		ending = "La première région est traversée. Votre train a survécu à la brume." if won else "Les réserves ou le convoi n’ont pas tenu. Un autre itinéraire reste possible."
	_paragraph(ending, Vector2(36, 680), 648, 24, PAPER, 35, 5)
	_text(str(int(model.data.get("step", 0))) + " étapes · " + str(int(model.data.get("hull", 0))) + " % de coque", Vector2(36, 910), 22, MUTED)
	_button("new", Rect2(32, 1005, 656, 88), "UN NOUVEAU VOYAGE", "Essayez un autre convoi.", true, true)
	_button("home", Rect2(32, 1110, 656, 88), "RETOUR AU TITRE")

func _draw_pause() -> void:
	_dim()
	_text("LE TRAIN PEUT ATTENDRE.", Vector2(40, 303), 35)
	_paragraph("Le voyage est sauvegardé sur cet appareil. Prenez le temps de préparer la suite.", Vector2(40, 361), 640, 24, MUTED, 35, 3)
	_button("pause", Rect2(40, 536, 640, 88), "REPRENDRE", "", true, true)
	_button("help", Rect2(40, 632, 640, 88), "GUIDE DE VOYAGE")
	_button("home", Rect2(40, 728, 640, 88), "SAUVEGARDER ET QUITTER")
	_button("credits", Rect2(40, 824, 640, 88), "CRÉDITS ET LICENCE")

func _draw_help() -> void:
	_dim()
	_text("GUIDE DE VOYAGE", Vector2(36, 87), 34, AMBER)
	var sections = [
		["01 · PRÉPARER", "Trois emplacements, six modules : votre train ne peut pas tout faire. Chaque wagon alourdit le trajet. Conservez du carburant et de quoi nourrir l’équipage."],
		["02 · CHOISIR SA ROUTE", "Comparez le carburant, le danger et les réserves espérées. Les destinations et les événements changent à chaque voyage."],
		["03 · EXPLORER", "Tapotez une direction autour du héros, les flèches ou glissez. Chaque déplacement joue un tour. Une case rouge sera frappée au prochain tour : écartez-vous."],
		["04 · RAPPORTER", "INTERAGIR ouvre les caches et active les signaux. Le sac est limité : choisissez votre prise. Revenez sur la case TRAIN et interagissez pour conserver le butin."],
		["05 · SAVOIR RENONCER", "REPLI ramène l’éclaireur avec des blessures et sans butin. Une attaque lointaine consomme une munition. Un soin vaut parfois plus qu’un trésor."]
	]
	var y = 150.0
	for section in sections:
		_text(section[0], Vector2(37, y), 22)
		y = _paragraph(section[1], Vector2(37, y + 37), 644, 21, MUTED, 30, 4) + 32
	_text("CLAVIER", Vector2(37, 1047), 18, AMBER)
	_paragraph("Flèches / ZQSD : marcher · E : interagir · ESPACE : attaquer · F : soin · ENTRÉE : attendre · ÉCHAP : pause", Vector2(37, 1079), 644, 18, MUTED, 26, 3)
	_button("close", Rect2(36, 1160, 648, 88), "BIEN REÇU", "", true, true)

func _draw_credits() -> void:
	_dim()
	_text("UN JEU LIBRE", Vector2(36, 80), 35, AMBER)
	_text("Le Dernier Convoi · Zachiran42 · 2026", Vector2(36, 122), 23)
	_paragraph("Code, textes, graphismes procéduraux et illustration originale : licence MIT. Illustration créée avec l’outil intégré de génération d’images. Sans publicité, sans compte, sans télémétrie.", Vector2(36, 165), 648, 19, MUTED, 28, 5)
	_text("GODOT ENGINE", Vector2(36, 349), 24)
	_paragraph(Engine.get_license_text(), Vector2(36, 389), 648, 16, MUTED, 23, 31)
	_paragraph("Les licences des bibliothèques du moteur sont incluses dans GODOT_THIRD_PARTY_LICENSES.txt, dans le projet et sur la page du jeu.", Vector2(36, 1090), 648, 17, MUTED, 24, 3)
	_button("close", Rect2(36, 1170, 648, 88), "RETOUR", "", true, true)

func _draw_confirmation() -> void:
	_dim()
	_text("CONFIRMER CE CHOIX", Vector2(40, 352), 33, AMBER)
	var message = "Une nouvelle partie remplacera votre sauvegarde actuelle."
	if confirm_action == "retreat":
		message = "Le repli abandonne le butin de cette expédition et peut blesser l’éclaireur. Vous pourrez préparer la prochaine étape au train."
	elif confirm_action == "dismantle":
		message = "Démonter ce wagon rend 50 % de son coût en ferraille. Son avantage disparaît immédiatement."
	elif confirm_action.begins_with("build:") or confirm_action.begins_with("replace:"):
		var id = confirm_action.get_slice(":", 1)
		var item = Model.MODULES.get(id, {})
		message = str(item.get("name", id)) + " · " + _cost(item.get("cost", {})) + ". " + str(item.get("description", ""))
		if confirm_action.begins_with("replace:"):
			message += " Le coût neuf entier est requis ; l’ancien module est ensuite recyclé à 50 %."
	_paragraph(message, Vector2(40, 421), 640, 25, PAPER, 37, 7)
	_button("confirm", Rect2(40, 788, 640, 88), "CONFIRMER", "", true, true)
	_button("cancel", Rect2(40, 884, 640, 88), "ANNULER")

func _draw_arrival() -> void:
	if keyart:
		draw_texture_rect(keyart, Rect2(-260, 224, 1240, 620), false, Color(0.7, 0.8, 0.8))
	_panel(Rect2(24, 762, 672, 387), INK, LINE, 18)
	_text("LE TRAIN S’ARRÊTE", Vector2(44, 807), 20, AMBER)
	_paragraph(str(model.data.get("route", {}).get("name", "Nouvelle escale")), Vector2(44, 859), 628, 32, PAPER, 40, 2)
	_paragraph("Choisissez ce que vous rapporterez. Les réserves du trajet ont été consommées ; le butin ne sera acquis qu’au retour au train.", Vector2(44, 951), 628, 22, MUTED, 31, 3)
	_button("continue", Rect2(44, 1056, 632, 88), "PARTIR EN EXPÉDITION", "", true, true)
