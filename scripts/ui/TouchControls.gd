extends CanvasLayer
## Dynamic (floating) touch controls. Web-safe, glitch-resilient.
## Left half = movement stick. Right half (build mode) = aim stick.
## Added to /root as last child by InputSupport so _input runs before the game
## scene — otherwise aim touches get eaten as "place module" in build mode.
## Shop check applies in BOTH scenes (tutorial has a shop too).
## Phase check applies only in game.tscn (tutorial doesn't set Phase.SURVIVE).

const BASE_R := 64.0
const DEADZONE := 0.08
const FOLLOW := false
const GRACE := 0.3
const FADE_SPEED := 14.0

var _surface: Control
var _fingers: Dictionary = {}
var _sent: Dictionary = {}
var _buttons: Dictionary = {}
var _enabled := false
var _grace := 0.0
var _dirty := true
var _swallow_mouse := false
var _last_size := Vector2.ZERO

var _u := 1.0
var _r := BASE_R
var _move_zone := Rect2()
var _aim_zone := Rect2()
var _move_home := Vector2.ZERO
var _aim_home := Vector2.ZERO
var _build_mode := false

var _move_base := Vector2.ZERO
var _move_val := Vector2.ZERO
var _move_alpha := 0.0
var _aim_base := Vector2.ZERO
var _aim_val := Vector2.ZERO
var _aim_alpha := 0.0

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_surface = Control.new()
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.draw.connect(_draw_controls)
	add_child(_surface)
	_surface.visible = false

func _current_scene_name() -> String:
	var s := get_tree().current_scene
	if s == null:
		return ""
	return s.scene_file_path.get_file()

func _in_game_scene() -> bool:
	var n := _current_scene_name()
	return n == "game.tscn" or n == "tutorial.tscn"

func _should_be_enabled() -> bool:
	if not _in_game_scene():
		return false
	if get_tree().paused:
		return false

	# Shop check applies in BOTH scenes — tutorial has a shop too.
	for n in get_tree().get_nodes_in_group("shop_ui"):
		if n is CanvasItem and n.is_visible_in_tree():
			return false

	# Phase check applies only to game.tscn — tutorial uses its own state machine
	# and never sets Phase.SURVIVE, so gating on phase there kills touch entirely.
	var scene_name := _current_scene_name()
	if scene_name == "game.tscn":
		if "current_phase" in GameManager and GameManager.current_phase != GameManager.Phase.SURVIVE:
			return false

	if not InputSupport.touch_active():
		return false
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var active_val = player.get("is_active")
	if active_val != null and bool(active_val) == false:
		return false
	var locked_val = player.get("input_locked")
	if locked_val != null and bool(locked_val) == true:
		return false
	return true

func _process(delta: float) -> void:
	var want := _should_be_enabled()
	if want:
		_grace = 0.0
		_enabled = true
	else:
		_grace += delta
		if _enabled and (get_tree().paused or _grace > GRACE):
			_release_all()
			_enabled = false
			_dirty = true
	_surface.visible = _enabled
	if not _enabled:
		return
	var player := get_tree().get_first_node_in_group("player")
	var build: bool = player != null and player.get("is_build_mode") == true
	if build != _build_mode:
		_build_mode = build
		if not build:
			for i in _fingers.keys():
				if _fingers[i] == "aim":
					_release_finger(i)
		_dirty = true
	var size := get_viewport().get_visible_rect().size
	if size != _last_size:
		_last_size = size
		_layout(size)
		_dirty = true
	var t := clampf(delta * FADE_SPEED, 0.0, 1.0)
	var mt := 1.0 if _fingers.values().has("move") else 0.0
	var at := 1.0 if _fingers.values().has("aim") else 0.0
	if not is_equal_approx(_move_alpha, mt) or not is_equal_approx(_aim_alpha, at):
		_move_alpha = lerpf(_move_alpha, mt, t)
		_aim_alpha = lerpf(_aim_alpha, at, t)
		if absf(_move_alpha - mt) < 0.01: _move_alpha = mt
		if absf(_aim_alpha - at) < 0.01: _aim_alpha = at
		_dirty = true
	if _dirty:
		_dirty = false
		_surface.queue_redraw()

func _insets(size: Vector2) -> Vector4:
	if not InputSupport.is_native_mobile():
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return Vector4.ZERO
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0:
		return Vector4.ZERO
	var k := size / win
	return Vector4(
		maxf(0.0, safe.position.x) * k.x,
		maxf(0.0, safe.position.y) * k.y,
		maxf(0.0, win.x - safe.end.x) * k.x,
		maxf(0.0, win.y - safe.end.y) * k.y
	)

func _layout(size: Vector2) -> void:
	_u = clampf(minf(size.x, size.y) / 720.0, 0.75, 1.4)
	_r = BASE_R * _u
	var ins := _insets(size)
	var m := 20.0 * _u
	var left := ins.x + m
	var right := size.x - ins.z - m
	var bottom := size.y - ins.w - m
	var top := ins.y + m

	var big := 108.0 * _u
	var sm := 62.0 * _u
	var gap := 10.0 * _u

	_buttons = {
		"interact":     Rect2(right - big, bottom - big, big, big),
		"rotate_port":  Rect2(right - big, bottom - big - gap - sm, big, sm),
		"use_medkit":   Rect2(right - big, bottom - big - gap - sm - gap - sm, big, sm),
		"build_mode":   Rect2(right - big - gap - sm, bottom - sm, sm, sm),
		"cycle_module": Rect2(right - big - gap - sm, bottom - sm * 2.0 - gap, sm, sm),
		"pause_game":   Rect2(right - 78.0 * _u, size.y * 0.18, 78.0 * _u, 68.0 * _u)
	}

	_move_home = Vector2(left + _r + 8.0 * _u, bottom - _r - 8.0 * _u)
	_aim_home = Vector2(right - _r - 8.0 * _u, size.y * 0.42)

	_move_zone = Rect2(0.0, size.y * 0.18, size.x * 0.5, size.y * 0.82)
	_aim_zone = Rect2(
		size.x * 0.5,
		size.y * 0.20,
		size.x * 0.5,
		size.y * 0.58
	)

func _input(event: InputEvent) -> void:
	if not _enabled:
		return
	if _swallow_mouse and event is InputEventMouse:
		if event is InputEventMouseButton and not event.pressed:
			_swallow_mouse = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			if _fingers.has(event.index):
				_release_finger(event.index)
				get_viewport().set_input_as_handled()
			return
		if _fingers.has(event.index):
			return
		var control := _pick_control(event.position)
		if control == "":
			return
		_fingers[event.index] = control
		if event.index == 0 and control in ["move", "aim"]:
			_swallow_mouse = true
		if control == "move":
			_move_base = _clamp_base(event.position)
			_move_val = Vector2.ZERO
			_update_stick("move", event.position)
		elif control == "aim":
			_aim_base = _clamp_base(event.position)
			_aim_val = Vector2.ZERO
			_update_stick("aim", event.position)
		else:
			_send(control, true)
			_buzz()
		_dirty = true
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		var c: String = _fingers[event.index]
		if c in ["move", "aim"]:
			_update_stick(c, event.position)
		get_viewport().set_input_as_handled()

func _pick_control(point: Vector2) -> String:
	for action in _buttons:
		if (_buttons[action] as Rect2).grow(6.0 * _u).has_point(point):
			if not _fingers.values().has(action):
				return action
			return ""
	if _move_zone.has_point(point) and not _fingers.values().has("move"):
		return "move"
	if _build_mode and _aim_zone.has_point(point) and not _fingers.values().has("aim"):
		return "aim"
	return ""

func _clamp_base(p: Vector2) -> Vector2:
	var s := get_viewport().get_visible_rect().size
	return Vector2(clampf(p.x, _r * 0.6, s.x - _r * 0.6), clampf(p.y, _r * 0.6, s.y - _r * 0.6))

func _update_stick(which: String, point: Vector2) -> void:
	var base := _move_base if which == "move" else _aim_base
	var offset := point - base
	var dist := offset.length()
	if dist > _r:
		if FOLLOW:
			base += offset.normalized() * (dist - _r)
			base = _clamp_base(base)
			offset = point - base
		offset = offset.limit_length(_r)
		dist = offset.length()
	var mag := dist / _r
	var out := Vector2.ZERO
	if mag > DEADZONE and dist > 0.0:
		out = offset / dist * ((mag - DEADZONE) / (1.0 - DEADZONE))
	if which == "move":
		_move_base = base
		_move_val = offset / _r
		_apply_move(out)
	else:
		_aim_base = base
		_aim_val = offset / _r
		InputSupport.touch_aim = out
	_dirty = true

func _apply_move(v: Vector2) -> void:
	_send("ui_left", v.x < 0.0, maxf(0.0, -v.x))
	_send("ui_right", v.x > 0.0, maxf(0.0, v.x))
	_send("ui_up", v.y < 0.0, maxf(0.0, -v.y))
	_send("ui_down", v.y > 0.0, maxf(0.0, v.y))

func _send(action: StringName, pressed: bool, strength: float = 1.0) -> void:
	if pressed:
		if _sent.has(action) and absf(float(_sent[action]) - strength) < 0.02:
			return
		_sent[action] = strength
		Input.action_press(action, strength)
		# action_press does NOT fire _input events. Movement code that polls
		# is_action_pressed() works, but interact/build/cycle/rotate code that
		# uses event.is_action_pressed() needs a real InputEventAction.
		# Skip ui_* actions — those are polled, and injecting them can
		# double-fire menu focus traversal.
		if not str(action).begins_with("ui_"):
			var ev := InputEventAction.new()
			ev.action = action
			ev.pressed = true
			ev.strength = strength
			get_viewport().push_input(ev)
	else:
		if not _sent.has(action):
			return
		_sent.erase(action)
		Input.action_release(action)
		if not str(action).begins_with("ui_"):
			var ev := InputEventAction.new()
			ev.action = action
			ev.pressed = false
			ev.strength = 0.0
			get_viewport().push_input(ev)

func _buzz() -> void:
	if InputSupport.is_native_mobile():
		Input.vibrate_handheld(12)

func _release_finger(index: int) -> void:
	if not _fingers.has(index):
		return
	var control: String = _fingers[index]
	_fingers.erase(index)
	if control == "move":
		_move_val = Vector2.ZERO
		_apply_move(Vector2.ZERO)
	elif control == "aim":
		_aim_val = Vector2.ZERO
		InputSupport.touch_aim = Vector2.ZERO
	else:
		_send(control, false, 0.0)
	_dirty = true

func _release_all() -> void:
	for index in _fingers.keys():
		_release_finger(index)
	for action in _sent.keys():
		_send(action, false, 0.0)
	_fingers.clear()
	_swallow_mouse = false
	_move_val = Vector2.ZERO
	_aim_val = Vector2.ZERO
	InputSupport.touch_aim = Vector2.ZERO
	_dirty = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()

func _exit_tree() -> void:
	_release_all()

func _draw_stick(base: Vector2, val: Vector2, alpha: float, label: String) -> void:
	var rim := Color(0.5, 0.88, 1.0, 0.55 * alpha)
	_surface.draw_circle(base, _r, Color(0.02, 0.06, 0.10, 0.40 * alpha))
	_surface.draw_arc(base, _r, 0.0, TAU, 64, rim, 2.0 * _u, true)
	_surface.draw_arc(base, _r * 0.45, 0.0, TAU, 40, Color(0.5, 0.88, 1.0, 0.18 * alpha), 1.5 * _u, true)
	var thumb := base + val.limit_length(1.0) * _r
	_surface.draw_circle(thumb, 26.0 * _u, Color(0.5, 0.88, 1.0, 0.38 * alpha))
	_surface.draw_arc(thumb, 26.0 * _u, 0.0, TAU, 32, Color(1, 1, 1, 0.5 * alpha), 1.5 * _u, true)
	if label != "":
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_surface.draw_string(font, base + Vector2(-w * 0.5, 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6 * alpha))

func _draw_controls() -> void:
	if not _enabled:
		return
	var font := ThemeDB.fallback_font
	if _move_alpha < 0.99:
		_draw_stick(_move_home, Vector2.ZERO, 0.35 * (1.0 - _move_alpha), "MOVE")
	if _move_alpha > 0.01:
		_draw_stick(_move_base, _move_val, _move_alpha, "")
	if _build_mode:
		if _aim_alpha < 0.99:
			_draw_stick(_aim_home, Vector2.ZERO, 0.35 * (1.0 - _aim_alpha), "AIM")
		if _aim_alpha > 0.01:
			_draw_stick(_aim_base, _aim_val, _aim_alpha, "")
	for action in _buttons:
		var rect: Rect2 = _buttons[action]
		var held := _sent.has(action)
		var tint := Color(0.5, 0.88, 1.0, 0.55 if held else 0.24)
		var fill := Color(0.10, 0.28, 0.38, 0.85) if held else Color(0.03, 0.08, 0.12, 0.65)
		_surface.draw_style_box(GlassUI.panel(fill, tint, 10, 10), rect)
		var c := rect.get_center()
		if action == "pause_game":
			# Classic pause icon — two vertical bars
			var bar_w := 9.0 * _u
			var bar_h := 28.0 * _u
			var bar_gap := 12.0 * _u
			var x0 := c.x - bar_gap * 0.5 - bar_w
			var x1 := c.x + bar_gap * 0.5
			var y0 := c.y - bar_h * 0.5
			_surface.draw_rect(Rect2(x0, y0, bar_w, bar_h), Color.WHITE)
			_surface.draw_rect(Rect2(x1, y0, bar_w, bar_h), Color.WHITE)
		elif action == "interact":
			var text := "Place / Use"
			var fs := 14
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_surface.draw_string(font, c + Vector2(-width * 0.5, 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		else:
			var text := InputSupport.label(action)
			var fs := 13
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_surface.draw_string(font, c + Vector2(-width * 0.5, 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
