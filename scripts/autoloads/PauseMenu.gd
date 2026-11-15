# CHANGELOG (2026-11-15): Persistent pause/options owner; frozen gameplay and survival timers; global F11 shortcut.
extends CanvasLayer

var menu: Control
var panel: PanelContainer
var options: Control
var opened := false
var _quitting := false
var _fullscreen_down := false

func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.005, 0.01, 0.025, 0.86)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.add_theme_stylebox_override("panel", GlassUI.panel())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SIGNAL PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", GameFont.get_font())
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	for item in [["RESUME", resume], ["OPTIONS", open_options], ["QUIT TO MAIN MENU", quit_to_menu]]:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(300, 50)
		button.add_theme_font_override("font", GameFont.get_font())
		GlassUI.style_button(button, 20)
		button.pressed.connect(item[1])
		button.mouse_entered.connect(button.grab_focus)
		box.add_child(button)
	menu.hide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not event.is_echo():
		if opened:
			if is_instance_valid(options):
				options._exit_action()
			else:
				resume()
		else:
			var scene := get_tree().current_scene
			if scene != null and scene.scene_file_path.get_file() in ["game.tscn", "tutorial.tscn"] and not Transition.transitioning and not _quitting:
				pause_game()
			else:
				return
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F11 or event.physical_keycode == KEY_F11:
		if not InputSupport.desktop_window_controls():
			return
		if not _fullscreen_down:
			toggle_fullscreen()
		_fullscreen_down = true
		get_viewport().set_input_as_handled()
		return
	if event.keycode not in [KEY_ESCAPE, KEY_P]:
		return
	if _quitting:
		return
	if opened:
		get_viewport().set_input_as_handled()
		if is_instance_valid(options):
			if event.keycode == KEY_ESCAPE:
				options._exit_action()
		else:
			resume()
		return
	var scene := get_tree().current_scene
	if scene == null or Transition.transitioning:
		return
	if scene.scene_file_path not in ["res://scenes/main scenes/game.tscn", "res://scenes/main scenes/tutorial.tscn"]:
		return
	get_viewport().set_input_as_handled()
	pause_game()

func pause_game() -> void:
	if opened:
		return
	opened = true
	menu.show()
	get_tree().paused = true
	panel.get_child(0).get_child(1).grab_focus()

func resume() -> void:
	if is_instance_valid(options):
		options.queue_free()
	options = null
	opened = false
	menu.hide()
	get_tree().paused = false

func open_options() -> void:
	if not opened or is_instance_valid(options):
		return
	options = load("res://scenes/main scenes/options.tscn").instantiate()
	options.process_mode = Node.PROCESS_MODE_ALWAYS
	options.set_meta("embedded_options", true)
	options.tree_exited.connect(_options_closed)
	menu.hide()
	add_child(options)

func _options_closed() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	options = null
	if opened and not _quitting:
		if is_instance_valid(menu):
			menu.show()
		tree.paused = true
func quit_to_menu() -> void:
	if _quitting:
		return
	_quitting = true
	resume()
	Dialogue.hide_dialogue()
	Hazards.clear()
	GameManager.current_phase = GameManager.Phase.INTRO
	await Transition.change_scene("res://scenes/main scenes/main_menu.tscn", 0.5)
	_quitting = false

func toggle_fullscreen() -> void:
	if not InputSupport.desktop_window_controls():
		return
	var fullscreen := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	var mode := "Windowed" if fullscreen else "Fullscreen"
	GameSettings.settings["window_mode"] = mode
	GameSettings._apply_display()
	GameSettings.save_settings()

func _process(_delta: float) -> void:
	if not InputSupport.desktop_window_controls():
		return
	# Polling fallback survives any scene/custom UI consuming the original key event.
	var down := Input.is_physical_key_pressed(KEY_F11) or Input.is_key_pressed(KEY_F11)
	if down and not _fullscreen_down:
		toggle_fullscreen()
	_fullscreen_down = down
