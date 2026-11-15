extends Node
## Device-aware labels and additive bindings. No gameplay rules live here.
signal device_changed
var device_kind := "keyboard"
var aim_direction := Vector2.DOWN
var touch_aim := Vector2.ZERO
var _saw_touch := false
var _last_touch_msec := -100000
var _axis_latches: Dictionary = {}
var _touch_controls: CanvasLayer
var _scene: Node

func is_web() -> bool:
	return OS.has_feature("web")

func is_native_mobile() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")

func has_touch() -> bool:
	# Unlike OS.get_name(), this detects touch inside desktop-class Web exports too.
	return _saw_touch or is_native_mobile() or DisplayServer.is_touchscreen_available()

func desktop_window_controls() -> bool:
	return not is_web() and not is_native_mobile()

func _enter_tree() -> void:
	_ensure_action("build_mode", KEY_SPACE, JOY_BUTTON_Y)
	_ensure_action("cycle_module", KEY_TAB, JOY_BUTTON_RIGHT_SHOULDER)
	_ensure_action("rotate_port", KEY_R, JOY_BUTTON_X)
	_ensure_action("use_medkit", KEY_H, JOY_BUTTON_LEFT_SHOULDER)
	_ensure_action("pause_game", KEY_ESCAPE, JOY_BUTTON_START)
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact", 0.2)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	if not InputMap.action_has_event("interact", pad):
		InputMap.action_add_event("interact", pad)
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		InputMap.action_set_deadzone(action, 0.22)

func _ensure_action(action: StringName, key: Key, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.22)
		var keyboard := InputEventKey.new()
		keyboard.physical_keycode = key
		InputMap.action_add_event(action, keyboard)
	var pad := InputEventJoypadButton.new()
	pad.button_index = button
	if not InputMap.action_has_event(action, pad):
		InputMap.action_add_event(action, pad)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	device_kind = "touch" if has_touch() else ("gamepad" if not Input.get_connected_joypads().is_empty() else "keyboard")
	Input.joy_connection_changed.connect(_joy_changed)

func _joy_changed(_id: int, connected: bool) -> void:
	_axis_latches.clear()
	if not connected and Input.get_connected_joypads().is_empty() and device_kind == "gamepad":
		device_kind = "touch" if has_touch() else "keyboard"
	elif connected:
		device_kind = "gamepad"
	device_changed.emit()

func _input(event: InputEvent) -> void:
	var kind := device_kind
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		kind = "touch"
		_saw_touch = true
		_last_touch_msec = Time.get_ticks_msec()
	elif event is InputEventJoypadButton and event.pressed:
		kind = "gamepad"
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		kind = "gamepad"
	elif event is InputEventKey and event.pressed:
		kind = "keyboard"
	elif event is InputEventMouseMotion and event.device != -1 and event.relative.length_squared() > 9.0 and Time.get_ticks_msec() - _last_touch_msec > 2500:
		kind = "keyboard"
	if kind != device_kind:
		device_kind = kind
		device_changed.emit()

func label(action: StringName) -> String:
	if device_kind == "touch":
		return {"interact": "◎", "build_mode": "Build", "cycle_module": "Next", "rotate_port": "Rotate", "ui_accept": "Tap", "pause_game": "Pause", "use_medkit": "Heal"}.get(str(action), "Touch")
	if not InputMap.has_action(action):
		return "Unbound"
	var events := InputMap.action_get_events(action)
	for event in events:
		if device_kind == "gamepad" and event is InputEventJoypadButton:
			var playstation := false
			var ids := Input.get_connected_joypads()
			if not ids.is_empty():
				var name_lower := Input.get_joy_name(ids[0]).to_lower()
				playstation = "playstation" in name_lower or "dualsense" in name_lower or "dualshock" in name_lower or "sony" in name_lower
			var names := {JOY_BUTTON_A: "Cross" if playstation else "A", JOY_BUTTON_B: "Circle" if playstation else "B", JOY_BUTTON_X: "Square" if playstation else "X", JOY_BUTTON_Y: "Triangle" if playstation else "Y", JOY_BUTTON_LEFT_SHOULDER: "L1" if playstation else "LB", JOY_BUTTON_RIGHT_SHOULDER: "R1" if playstation else "RB", JOY_BUTTON_START: "Options" if playstation else "Start"}
			return names.get(event.button_index, "Pad %d" % event.button_index)
		if device_kind != "gamepad":
			if event is InputEventKey:
				var code: int = event.keycode
				if code == KEY_NONE:
					# keyboard_get_keycode_from_physical is NOT implemented on Web or headless.
					var ds := DisplayServer.get_name()
					if ds == "headless" or ds == "web" or OS.has_feature("web"):
						code = event.physical_keycode
					else:
						code = DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
					if code == KEY_NONE:
						code = event.physical_keycode
				return OS.get_keycode_string(code)
			if event is InputEventMouseButton:
				return "Mouse %d" % event.button_index
	return "Unbound"

func movement_label() -> String:
	if device_kind == "touch":
		return "left stick"
	if device_kind == "gamepad":
		return "left stick / D-pad"
	return "%s/%s/%s/%s" % [label("ui_up"), label("ui_left"), label("ui_down"), label("ui_right")]

func expand(text: String) -> String:
	# Explicit tokens only: never replace ordinary letters in narrative prose.
	for action in ["interact", "build_mode", "cycle_module", "rotate_port", "ui_accept", "use_medkit", "pause_game"]:
		text = text.replace("{" + action + "}", label(action))
	return text.replace("{move}", movement_label())

func menu_event(event: InputEvent) -> InputEvent:
	# Local adapter for the existing custom-drawn menus; never inject fake keys globally.
	if event is InputEventJoypadMotion:
		var axis_key := "%d:%d" % [event.device, event.axis]
		if absf(event.axis_value) < 0.22:
			_axis_latches.erase(axis_key)
			return event
		if absf(event.axis_value) < 0.55:
			return event
		var direction := int(signf(event.axis_value))
		if _axis_latches.get(axis_key, 0) == direction:
			return event
		_axis_latches[axis_key] = direction
	elif not (event is InputEventJoypadButton and event.pressed):
		return event
	for pair in [["ui_up", KEY_UP], ["ui_down", KEY_DOWN], ["ui_left", KEY_LEFT], ["ui_right", KEY_RIGHT], ["ui_accept", KEY_ENTER], ["ui_cancel", KEY_ESCAPE]]:
		if event.is_action_pressed(pair[0]):
			var key := InputEventKey.new()
			key.pressed = true
			key.keycode = pair[1]
			return key
	return event

func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _scene:
		_scene = scene
		if is_instance_valid(_touch_controls):
			_touch_controls.queue_free()
		_touch_controls = null
		if scene != null and scene.scene_file_path.get_file() in ["game.tscn", "tutorial.tscn"] and has_touch():
			_touch_controls = load("res://scripts/ui/TouchControls.gd").new()
			add_child(_touch_controls)
	if not is_instance_valid(_touch_controls) and scene != null and scene.scene_file_path.get_file() in ["game.tscn", "tutorial.tscn"] and has_touch():
		_touch_controls = load("res://scripts/ui/TouchControls.gd").new()
		add_child(_touch_controls)
	if device_kind == "gamepad":
		var ids := Input.get_connected_joypads()
		if not ids.is_empty():
			var aim := Vector2(Input.get_joy_axis(ids[0], JOY_AXIS_RIGHT_X), Input.get_joy_axis(ids[0], JOY_AXIS_RIGHT_Y))
			if aim.length() > 0.25:
				aim_direction = aim.normalized()
	elif device_kind == "touch" and touch_aim.length() > 0.2:
		aim_direction = touch_aim.normalized()
	# Make the existing hovered socket UI reachable with the right stick as well.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and device_kind == "gamepad" and not get_tree().paused and player.get("is_build_mode") == true:
		var point := player.get_global_transform_with_canvas() * (aim_direction * 230.0)
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		motion.device = -1
		get_viewport().push_input(motion, true)
