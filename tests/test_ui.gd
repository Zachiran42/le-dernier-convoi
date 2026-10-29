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
	ui.free()
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if failures.is_empty():
		print("PASS: ", checks, " UI integration assertions (save/resume, modal races, keyboard, fractional touch/mouse, crafting and bounds)")
		quit(0)
	else:
		print("FAIL: ", failures.size(), " / ", checks, " UI assertions")
		quit(1)
