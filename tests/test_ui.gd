extends SceneTree
## Portable headless integration tests; no UI automation or global preferences.
## Run with APPDATA (Windows) or XDG_DATA_HOME (Linux) pointing to a temporary
## directory whose path contains "convoi-ui-test", then:
## godot --headless --path . --script res://tests/test_ui.gd
const Scene = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/convoi_state.gd")
const SAVE_PATH = "user://convoi-save.json"
var ui
var checks = 0
var failures: Array[String] = []

# Record actual rendered labels without replacing gameplay or input handling.
class TracedUI:
	extends "res://scripts/main.gd"
	var rendered: Array[Dictionary] = []
	var paragraphs: Array[Dictionary] = []
	func _draw() -> void:
		rendered.clear()
		paragraphs.clear()
		super._draw()
	func _text(value: String, point: Vector2, pixels: int = 20, color: Color = Color.WHITE) -> void:
		rendered.append({"value":value,"point":point,"pixels":pixels,"color":color})
		super._text(value, point, pixels, color)
	func _paragraph(value: String, point: Vector2, width: float, pixels: int = 20, color: Color = Color.WHITE, line_height: float = 29.0, max_lines: int = 20) -> float:
		paragraphs.append({"value":value,"point":point,"width":width,"pixels":pixels,"max_lines":max_lines})
		return super._paragraph(value, point, width, pixels, color, line_height, max_lines)


func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("UI TEST: " + message)

func _settle() -> void:
	ui.queue_redraw()
	await process_frame
	await process_frame

func _button(id: String) -> Dictionary:
	for item in ui.buttons:
		if str(item.id) == id:
			return item
	return {}

func _mouse(logical: Vector2, device: int = 0) -> void:
	var physical: Vector2 = ui.ui_offset + logical * ui.ui_scale
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.device = device
		event.position = physical
		event.pressed = down
		ui._input(event)

func _touch(logical: Vector2) -> void:
	var physical: Vector2 = ui.ui_offset + logical * ui.ui_scale
	for down in [true, false]:
		var event = InputEventScreenTouch.new()
		event.position = physical
		event.pressed = down
		ui._input(event)

func _click(id: String) -> void:
	var item = _button(id)
	_check(not item.is_empty(), "button exists: " + id)
	if not item.is_empty():
		_mouse(item.rect.get_center())

func _key(code: Key) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	ui._input(event)

func _base(seed: int = 12345) -> void:
	ui.model.new_run(seed)
	ui.screen = "game"
	ui.base_tab = "train"
	ui.selected_slot = 0
	ui.inspected_region = -1
	ui.paused = false
	ui.help_open = false
	ui.credits_open = false
	ui.confirm_action = ""
	ui.last_phase = "base"
	ui.buttons.clear()

func _expedition(seed: int = 12345) -> void:
	_base(seed)
	_check(ui.model.act("choose_route", 0), "legal route starts a journey")
	var choices = ui.model.data.pending_event.choices
	_check(ui.model.act("event_choice", choices.size() - 1), "a free travel choice resolves")
	_check(ui.model.act("continue"), "arrival starts an expedition")
	_check(ui.model.data.phase == "expedition", "core contract exposes expedition phase")
	ui.last_phase = "expedition"

func _test_save_and_resume() -> void:
	_base(24680)
	ui._save()
	_check(FileAccess.file_exists(SAVE_PATH), "new run creates a save")
	ui._action("build", {"module":"serre", "slot":0})
	var expected = ui.model.snapshot()
	ui._activate("home")
	_check(ui.screen == "home", "return to menu changes screen")
	var saved_text = FileAccess.get_file_as_string(SAVE_PATH)
	var probe = Model.new()
	_check(probe.restore(JSON.parse_string(saved_text)), "repeated atomic saves overwrite with valid JSON")
	_check(probe.snapshot() == expected, "menu return preserves the latest run, not the initial one")
	ui.model.new_run(98765)
	ui._save()
	_check(FileAccess.get_file_as_string(SAVE_PATH) == saved_text, "home-screen save guard cannot overwrite a journey")
	ui.free()
	ui = Scene.instantiate()
	root.add_child(ui)
	await _settle()
	_check(ui.saved_run, "startup detects the saved run")
	_check(ui.model.snapshot() == expected, "startup restores the exact saved journey")
	_check(not _button("resume").is_empty(), "menu offers resume")
	_click("resume")
	_check(ui.screen == "game" and not ui.paused, "resume returns to the saved game")
	_check(ui.model.snapshot() == expected, "resuming does not restart or charge resources")

func _test_modal_races() -> void:
	_base()
	await _settle()
	var old_build = _button("build:serre")
	_check(not old_build.is_empty(), "real build rectangle was rendered")
	var before = ui.model.snapshot()
	_click("pause")
	_check(ui.paused, "pause opens immediately")
	_check(ui.buttons.is_empty(), "activation invalidates hit rectangles before the next frame")
	if not old_build.is_empty():
		ui._pointer(old_build.rect.get_center(), old_build.rect.get_center())
	_check(ui.model.snapshot() == before, "rapid second click cannot buy underneath pause")
	for overlay in ["pause", "help", "credits", "confirmation"]:
		_base()
		if overlay == "pause": ui.paused = true
		if overlay == "help": ui.help_open = true
		if overlay == "credits": ui.credits_open = true
		if overlay == "confirmation": ui.confirm_action = "dismantle"
		before = ui.model.snapshot()
		# Simulate an old input-region cache surviving until the next drawing frame.
		ui.buttons.append({"id":"build:serre", "rect":Rect2(0,0,720,1280), "enabled":true})
		ui._pointer(Vector2(100,100), Vector2(100,100))
		_check(ui.model.snapshot() == before, overlay + " blocks stale background click regions")
		ui._activate("build:serre")
		_check(ui.model.snapshot() == before, overlay + " blocks direct stale activation as well")
	_base()
	ui.confirm_action = "new"
	ui.paused = true # Android background notification while confirmation is open.
	before = ui.model.snapshot()
	ui._activate("cancel")
	_check(ui.confirm_action.is_empty(), "top confirmation remains cancellable after application pause")
	_check(ui.paused and ui.model.snapshot() == before, "cancelling top modal preserves paused game and resources")
	_base()
	ui._action("choose_route", 0)
	before = ui.model.snapshot()
	ui._activate("build:serre")
	_check(ui.model.snapshot() == before, "pending event rejects stale non-event actions")
	await _settle()
	_check(ui.buttons.all(func(item): return str(item.id).begins_with("event:")), "only event choices remain clickable under event overlay")

func _test_keyboard_and_coordinates() -> void:
	_expedition()
	for overlay in ["pause", "help", "credits", "confirmation"]:
		ui.paused = overlay == "pause"
		ui.help_open = overlay == "help"
		ui.credits_open = overlay == "credits"
		ui.confirm_action = "retreat" if overlay == "confirmation" else ""
		var before = ui.model.snapshot()
		for code in [KEY_ENTER, KEY_E, KEY_SPACE, KEY_R, KEY_RIGHT]: _key(code)
		_check(ui.model.snapshot() == before, "keyboard cannot play through " + overlay)
	ui.paused = false
	ui.help_open = false
	ui.credits_open = false
	ui.confirm_action = ""
	var turns = int(ui.model.data.turn_total)
	_key(KEY_ENTER)
	_check(int(ui.model.data.turn_total) == turns + 1, "keyboard resumes after modal closes")
	_expedition(13579)
	ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(689.5, 1187.25)
	await _settle()
	_check(ui.ui_scale > 0.0 and ui.ui_scale < 1.0, "fractional viewport scale is active")
	_check(absf(ui.ui_offset.x) > 0.1 or absf(ui.ui_offset.y) > 0.1, "fractional viewport includes a letterbox offset")
	var logical = Vector2(612.25, 1001.75)
	_check(ui._to_ui(ui.ui_offset + logical * ui.ui_scale).distance_to(logical) < 0.001, "fractional coordinates round-trip accurately")
	var expedition = ui.model.data.expedition
	var tile = 672.0 / float(expedition.width)
	var player = expedition.player
	var origin = Vector2(24,258)
	var center = origin + (Vector2(player.x,player.y) + Vector2.ONE * 0.5) * tile
	var previous = Vector2i(player.x,player.y)
	_touch(center + Vector2(tile * 3.0, 0))
	_check(Vector2i(expedition.player.x,expedition.player.y) == previous + Vector2i.RIGHT, "distant side tap moves exactly one logical cell at fractional scale")
	_mouse(origin + (Vector2(previous) + Vector2.ONE * 0.5) * tile)
	_check(Vector2i(expedition.player.x,expedition.player.y) == previous, "real mouse still works after touching the screen")
	var before = ui.model.snapshot()
	_mouse(center + Vector2(tile * 3.0, 0), -1)
	_check(ui.model.snapshot() == before, "synthetic mouse event does not duplicate a touch action")
	_base()
	await _settle()
	_click("tab:routes")
	_check(ui.base_tab == "routes", "fractionally scaled button hit testing selects the intended tab")

func _test_crafting_contract() -> void:
	_base()
	ui.base_tab = "crew"
	await _settle()
	_check(not _button("craft:ammo").enabled, "crafting cannot appear available before an atelier exists")
	_check(ui.model.act("build", {"module":"atelier", "slot":0}), "atelier can be legally installed")
	_check(ui.model.act("assign", "basile"), "Basile can be selected")
	ui.model.data.resources.scrap = 2
	await _settle()
	_check(_button("craft:ammo").enabled, "mecano's actual two-scrap recipe is clickable")
	var ammunition = int(ui.model.data.resources.ammo)
	_click("craft:ammo")
	_check(int(ui.model.data.resources.scrap) == 0, "craft click charges the displayed role-adjusted price")
	_check(int(ui.model.data.resources.ammo) == ammunition + 3, "craft click grants exactly one batch")
	ui.model.data.blade = 2
	ui.model.data.resources.scrap = 20
	await _settle()
	_check(not _button("craft:blade").enabled, "maximum blade upgrade cannot offer a paid no-op")

func _test_button_bounds() -> void:
	_base()
	for tab in ["train", "routes", "crew"]:
		ui.base_tab = tab
		await _settle()
		_check(not ui.buttons.is_empty(), "buttons rendered for " + tab)
		for item in ui.buttons:
			var rect: Rect2 = item.rect
			_check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 720 and rect.end.y <= 1280, "interactive bounds remain inside logical canvas: " + str(item.id))
	_expedition()
	await _settle()
	for item in ui.buttons:
		_check(not item.rect.intersects(Rect2(24, 842, 672, 94)), "expedition actions remain clear of transient notices")
		if str(item.id).begins_with("move:") or item.id in ["interact", "attack", "heal", "wait", "retreat"]:
			_check(item.rect.size.y >= 88, "tactical touch target is at least 44 pixels high on a 360-pixel phone")

func _run() -> void:
	# Never overwrite an actual player's save. The caller must isolate this process.
	if not OS.get_user_data_dir().to_lower().contains("convoi-ui-test"):
		push_error("Set APPDATA/XDG_DATA_HOME to an isolated temporary convoi-ui-test directory. Actual path: " + OS.get_user_data_dir())
		quit(2)
		return
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	ui = Scene.instantiate()
	root.add_child(ui)
	await _settle()
	await _test_save_and_resume()
	await _test_modal_races()
	await _test_keyboard_and_coordinates()
	await _test_crafting_contract()
	await _test_button_bounds()
	await _test_regions_and_atlas()
	await _test_hazard_visibility()
	await _test_region_event_and_migration()
	await _test_recruitment_availability()
	await _test_text_layout()
	ui.free()
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if failures.is_empty():
		print("PASS: ", checks, " UI integration assertions (save/resume, modal races, keyboard, fractional touch/mouse, crafting and bounds)")
		quit(0)
	else:
		print("FAIL: ", failures.size(), " / ", checks, " UI assertions")
		quit(1)

func _traced_scene() -> void:
	ui.free()
	ui = TracedUI.new()
	root.add_child(ui)
	ui.size = Vector2(720,1280)
	await _settle()

func _has_text(fragment: String) -> bool:
	for label in ui.rendered:
		if str(label.value).contains(fragment): return true
	return false

func _count_text(value: String) -> int:
	var result = 0
	for label in ui.rendered:
		if label.value == value: result += 1
	return result

func _region_state(index: int, completed: int = 0) -> void:
	_base(551 + index)
	ui.model.data.region_index = index
	ui.model.data.region = Model.REGIONS[index].name
	ui.model.data.step = index * Model.STEPS_PER_REGION + completed
	ui.model._make_routes()
	ui.base_tab = "routes"

func _test_regions_and_atlas() -> void:
	await _traced_scene()
	var palettes = {}
	for index in range(Model.REGIONS.size()):
		_region_state(index, 2)
		var probe = Model.new()
		_check(probe.restore(ui.model.snapshot()), "atlas region fixture respects save/model contract")
		var before = ui.model.snapshot()
		await _settle()
		_check(ui._local_halt() == 3, "regional halt uses local progress")
		_check(ui._progress_text().contains(str(index * Model.STEPS_PER_REGION + 2) + "/" + str(Model.TOTAL_STEPS)), "global progress retains completed halt count")
		_check(_has_text(str(Model.REGIONS[index].name)), "current region is actually drawn")
		_check(_count_text("ICI") == 1 and _count_text("TRAVERSÉE") == index, "atlas marks current and completed regions distinctly")
		_check(_count_text("VERROUILLÉE") == Model.REGIONS.size() - index - 1, "future regions retain visible lock labels")
		for number in range(Model.REGIONS.size()):
			var node = _button("region:" + str(number))
			_check(not node.is_empty() and node.rect.size.y >= 88, "atlas node is a large inspectable target")
		for item in ui.buttons:
			_check(item.rect.size.y >= 88, "atlas and departure actions retain 88px touch targets")
			_check(item.rect.end.x <= 720 and item.rect.end.y <= 1280, "atlas action remains inside logical viewport")
		var needs = ui.model.departure_needs()
		_check(_has_text("DÉPART NET : " + str(needs.food) + " rations · " + str(needs.water) + " eaux"), "rendered departure bill comes from the regional net-cost contract")
		for route in ui.model.data.routes:
			_check(_has_text(str(route.fuel) + " CARBURANT · poids et terrain inclus"), "route displays its existing total cost without adding terrain twice")
		palettes[Model.REGIONS[index].floor + Model.REGIONS[index].wall + Model.REGIONS[index].accent] = true
		_check(ui.model.snapshot() == before, "drawing atlas never changes the journey")
	_check(palettes.size() == Model.REGIONS.size(), "all regions have distinct palettes")
	_region_state(0)
	await _settle()
	var unchanged = ui.model.snapshot()
	_click("region:" + str(Model.REGIONS.size() - 1))
	await _settle()
	_check(ui._inspected_region() == Model.REGIONS.size() - 1, "future region can be inspected")
	_check(ui._region_index() == 0 and ui.model.snapshot() == unchanged, "inspection neither teleports nor unlocks the future region")
	_check(_has_text("APERÇU · VERROUILLÉE"), "future inspection clearly remains locked")
	_region_state(2)
	_check(ui.model.act("build", {"module":"serre","slot":0}), "net-cost UI test installs a legal greenhouse")
	await _settle()
	var needs = ui.model.departure_needs()
	_check(int(needs.water) >= 5 and int(needs.food) == 1, "desert heat and greenhouse costs are combined")
	_check(_has_text("DÉPART NET : " + str(needs.food) + " rations · " + str(needs.water) + " eaux"), "serre and heat are shown with exact net figures")
	# A region-end label never turns the eighth halt into a campaign ending.
	_region_state(1)
	await _settle()
	_check(not _has_text("L’AUBE RÉPOND."), "eighth completed halt does not display final victory")
	_region_state(Model.REGIONS.size() - 1, Model.STEPS_PER_REGION - 1)
	for route in ui.model.data.routes:
		var label_width = ui.font.get_string_size(str(route.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
		_check(label_width <= 660, "route/boss names fit the route cards")
	# Check actual title geometry for every final halt, including long boss names.
	for index in range(Model.REGIONS.size()):
		_region_state(index, Model.STEPS_PER_REGION - 1)
		_check(ui.model.act("choose_route", 2), "regional guardian route is selectable")
		_check(ui.model.act("event_choice", ui.model.data.pending_event.choices.size() - 1), "regional travel event resolves")
		_check(ui.model.act("continue"), "guardian expedition enters")
		await _settle()
		var title = ui.rendered.filter(func(label): return label.value == str(ui.model.data.route.name) and label.point == Vector2(26,208))
		_check(title.size() == 1, "expedition renders its complete route name")
		if not title.is_empty():
			var width = ui.font.get_string_size(str(title[0].value), HORIZONTAL_ALIGNMENT_LEFT, -1, int(title[0].pixels)).x
			_check(26 + width < 512 and int(title[0].pixels) >= 18, "actual title fits without colliding with R/H progress: " + str(ui.model.data.route.name))

func _test_hazard_visibility() -> void:
	_region_state(Model.REGIONS.size() - 1, Model.STEPS_PER_REGION - 1)
	_check(ui.model.act("choose_route", 0), "hazard fixture chooses last-region route")
	_check(ui.model.act("event_choice", ui.model.data.pending_event.choices.size() - 1), "hazard fixture resolves event")
	_check(ui.model.act("continue"), "hazard fixture enters")
	var expedition = ui.model.data.expedition
	_check(expedition.hazards.size() >= 2, "regional expedition supplies multiple hazards")
	for y in range(expedition.height):
		for x in range(expedition.width):
			expedition.seen[y][x] = true
			expedition.visible[y][x] = false
	var hazard = expedition.hazards[0]
	expedition.visible[int(hazard.y)][int(hazard.x)] = true
	await _settle()
	_check(ui._visible_hazards(expedition).size() == 1, "only visible hazards leave the fog")
	_check(_count_text("−" + str(hazard.damage)) == 1, "actual draw emits one damage marker, not remembered or unseen hazards")
	_check(ui._hazard_legend(expedition).contains("−" + str(hazard.damage) + " PV"), "legend states exact visible hazard cost")
	_check(ui._visible_boss(expedition).is_empty(), "unseen guardian is not named on tactical HUD")
	expedition.visible[int(hazard.y)][int(hazard.x)] = false
	await _settle()
	_check(_count_text("−" + str(hazard.damage)) == 0, "remembered terrain does not reveal a currently unseen hazard")
	var boss = expedition.enemies.filter(func(enemy): return enemy.boss)[0]
	expedition.visible[int(boss.y)][int(boss.x)] = true
	await _settle()
	_check(not ui._visible_boss(expedition).is_empty(), "guardian HUD appears once it is visible")
	_check(_has_text(str(Model.REGIONS.back().boss_name)), "regional guardian name is rendered dynamically")
	var before = ui.model.snapshot()
	await _settle()
	_check(ui.model.snapshot() == before, "drawing hazards, fog and boss names never mutates world state")

func _test_region_event_and_migration() -> void:
	var legacy = FileAccess.get_file_as_string("res://tests/fixtures/v01-won.json")
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(legacy)
	file.close()
	await _traced_scene()
	_check(ui.saved_run, "startup accepts a real v0.1 victory save through migration")
	_check(int(ui.model.data.step) == Model.STEPS_PER_REGION and int(ui.model.data.region_index) == 1, "old victory resumes after region one, not at a new game")
	_check(ui.model.data.pending_event.get("context") == "region", "migrated campaign opens a regional stop")
	_click("resume")
	await _settle()
	_check(_has_text("ESCALE DE RÉGION"), "new-region stop has its own visible heading")
	_check(ui.buttons.all(func(item): return str(item.id).begins_with("event:")), "regional stop exposes only its own actions")
	var before = ui.model.snapshot()
	for code in [KEY_ENTER, KEY_RIGHT, KEY_SPACE]: _key(code)
	ui._activate("region:4")
	ui._activate("route:0")
	_check(ui.model.snapshot() == before, "regional stop blocks underlying route/atlas/keyboard actions")
	var pass_index = -1
	for index in range(ui.model.data.pending_event.choices.size()):
		if ui.model.data.pending_event.choices[index].id == "pass": pass_index = index
	_check(pass_index >= 0, "stop always has a free continue option")
	_click("event:" + str(pass_index))
	_check(ui.model.data.pending_event.is_empty() and ui.model.data.phase == "base", "resolving the stop unlocks base planning")
	_check(ui.model.data.resources == before.resources and ui.model.data.crew == before.crew and ui.model.data.hull == before.hull, "free regional continuation never resets or refills supplies and crew")
	var probe = Model.new()
	_check(probe.restore(JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))), "migrated run persists in the current schema after action")

func _test_recruitment_availability() -> void:
	_region_state(1,1)
	_check(ui.model.act("build", {"module":"dortoir","slot":0}), "recruit test has a legal dormitory")
	_check(ui.model.act("choose_route",0), "recruitment route is legal")
	await _settle()
	var index = -1
	for i in range(ui.model.data.pending_event.choices.size()):
		if ui.model.data.pending_event.choices[i].effects.get("join",false): index = i
	_check(index >= 0, "recruitment event offers Ilyan")
	_check(_button("event:" + str(index)).enabled, "dormitory with a free berth enables recruitment")
	ui.model.data.crew.append({"id":"ilyan","name":"Ilyan","role":"aide","hp":75,"max_hp":75})
	await _settle()
	var recruit = _button("event:" + str(index))
	_check(not recruit.enabled and str(recruit.reason).contains("déjà"), "already-recruited Ilyan is visibly disabled")
	var before = ui.model.snapshot()
	_click("event:" + str(index))
	_check(ui.model.snapshot() == before, "disabled duplicate recruitment spends no food or action")
	ui.model.data.crew[ui.model.data.crew.size()-1].id = "other-aide"
	await _settle()
	recruit = _button("event:" + str(index))
	_check(not recruit.enabled and str(recruit.reason).contains("complet"), "full crew shows a full-capacity reason")

func _wrapped_lines(value: String, width: float, pixels: int) -> int:
	var total = 0
	for raw in value.split("\n"):
		var current = ""
		for word in raw.split(" "):
			var trial = word if current.is_empty() else current + " " + word
			if ui.font.get_string_size(trial,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x > width and not current.is_empty():
				total += 1
				current = word
			else: current = trial
		total += 1
	return total

func _test_text_layout() -> void:
	for index in range(Model.REGIONS.size()):
		_region_state(index)
		ui.inspected_region = index
		await _settle()
		for paragraph in ui.paragraphs:
			if paragraph.point == Vector2(43,511):
				_check(_wrapped_lines(paragraph.value,paragraph.width,paragraph.pixels) <= paragraph.max_lines, "regional story and hazard description are fully readable: " + str(Model.REGIONS[index].name))
	ui.help_open = true
	await _settle()
	var last_body_baseline = 0.0
	for label in ui.rendered:
		if int(label.pixels) == 21: last_body_baseline = maxf(last_body_baseline,label.point.y)
	_check(last_body_baseline <= 1021.0, "expanded campaign guide does not overlap keyboard instructions")
	ui.help_open = false
