@tool
extends StaticBody2D
class_name WirePort

signal rotated(new_side: int)

@export var rotatable: bool = true
@export var click_radius: float = 14.0
@export var reach: float = 300.0
@export var edge_margin: float = 0.0

const DIRS := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
const SLOT_SPACING := 56.0
const RING_R := 42.0
const TAG_TEXT := "Click to rotate"

static var hover_count: int = 0

var side: int = 0
var hovered: bool = false
var flash: float = 0.0
var pulse_time: float = 0.0

var _center := Vector2.ZERO
var _half := Vector2(64, 64)
var _rot_target: float = 0.0
var _tween: Tween
var _tag_style: StyleBoxFlat

func _ready() -> void:
	if not Engine.is_editor_hint() and scale.x < 0.0 and scale.y < 0.0:
		rotation += PI
		scale = Vector2(absf(scale.x), absf(scale.y))
	_rot_target = rotation
	side = posmod(roundi(rotation / (PI * 0.5)), 4)
	_measure()
	if Engine.is_editor_hint():
		return
	var p := get_parent()
	if p != null and p.has_meta("is_ghost"):
		material = ModuleArt.make_ghost_material()
		rotatable = false
	_snap_to_edge.call_deferred()

func _exit_tree() -> void:
	if hovered:
		hovered = false
		hover_count = maxi(0, hover_count - 1)
		if hover_count == 0:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _measure() -> void:
	var p := get_parent()
	if p == null:
		return
	for n in p.get_children():
		if n is CollisionShape2D and (n as CollisionShape2D).shape is RectangleShape2D:
			var cs := n as CollisionShape2D
			_half = (cs.shape as RectangleShape2D).size * 0.5
			_center = cs.position
			return

func _edge_position(s: int, slot: float) -> Vector2:
	var d: Vector2 = DIRS[s]
	var edge := _half.x if d.x != 0.0 else _half.y
	var tangent := Vector2(-d.y, d.x)
	return _center + d * (edge + edge_margin) + tangent * slot * SLOT_SPACING

func _snap_to_edge() -> void:
	if not is_inside_tree():
		return
	var mates := _ports_on_side(side)
	var slot := float(mates.find(self)) - float(mates.size() - 1) * 0.5
	position = _edge_position(side, slot)

func _ports_on_side(s: int) -> Array:
	var out: Array = []
	var p := get_parent()
	if p == null:
		return out
	for c in p.get_children():
		if c is WirePort and (c as WirePort).side == s:
			out.append(c)
	return out

func _port_on_side(s: int) -> WirePort:
	var p := get_parent()
	if p == null:
		return null
	for c in p.get_children():
		if c != self and c is WirePort and (c as WirePort).side == s:
			return c as WirePort
	return null

func _build_mode_on() -> bool:
	var pl := get_tree().get_first_node_in_group("player") as Node2D
	if pl == null or not pl.visible:
		return false
	return pl.get("is_build_mode") == true

func _interactive() -> bool:
	if not rotatable:
		return false
	var p := get_parent()
	if p == null:
		return false
	if p is BaseModule and (p as BaseModule).is_constructing:
		return false
	return _build_mode_on()

func _mouse_hit() -> bool:
	return get_global_mouse_position().distance_to(global_position) <= RING_R

func _process(delta: float) -> void:
	pulse_time += delta
	flash = maxf(0.0, flash - delta * 2.2)
	if not Engine.is_editor_hint():
		var h := _interactive() and _mouse_hit()
		if h != hovered:
			hovered = h
			if hovered:
				hover_count += 1
			else:
				hover_count = maxi(0, hover_count - 1)
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hover_count > 0 else Input.CURSOR_ARROW)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not hovered:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			rotate_side(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			rotate_side(-1)
			get_viewport().set_input_as_handled()

func rotate_side(step: int) -> void:
	var old_side := side
	var new_side := posmod(side + step, 4)
	var other := _port_on_side(new_side)
	_apply_side(new_side, step)
	if other != null:
		other._apply_side(old_side, -step)

func _apply_side(new_side: int, step: int) -> void:
	side = new_side
	var target := _edge_position(side, 0.0)
	_rot_target += float(step) * PI * 0.5
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position", target, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation", _rot_target, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flash = 1.0
	rotated.emit(side)

func _draw_port_fx(_rad: float) -> void:
	if Engine.is_editor_hint():
		return
	var build := _interactive()
	if not build and flash <= 0.01:
		return
	var sc := maxf(absf(global_scale.x), 0.01)
	var r := RING_R / sc
	var w := 2.5 / sc
	var pulse := 0.5 + 0.5 * sin(pulse_time * 6.0)
	var a := 0.0
	if hovered:
		a = 0.6 + 0.3 * pulse
	elif build:
		a = 0.18 + 0.08 * pulse
	if a > 0.0:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.55, 1.0, 1.0, a), w, true)
	if flash > 0.01:
		draw_arc(Vector2.ZERO, r * (1.0 + (1.0 - flash) * 0.8), 0.0, TAU, 40, Color(1, 1, 1, flash * 0.8), w * 1.5, true)
	if hovered:
		_draw_tag()

func _draw_tag() -> void:
	if _tag_style == null:
		_tag_style = StyleBoxFlat.new()
		_tag_style.bg_color = Color(0.07, 0.09, 0.17, 0.92)
		_tag_style.border_color = Color(0.55, 1.0, 1.0, 0.85)
		_tag_style.set_border_width_all(1)
		_tag_style.set_corner_radius_all(8)
	var f := ThemeDB.fallback_font
	var fs := 16
	var tw := f.get_string_size(TAG_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cam := get_viewport().get_camera_2d()
	var z := maxf(cam.zoom.x, 0.1) if cam != null else 1.0
	var anchor := global_position + Vector2(0.0, -(RING_R + 26.0) / z)
	draw_set_transform_matrix(get_global_transform().affine_inverse() * Transform2D(0.0, Vector2.ONE / z, 0.0, anchor))
	draw_style_box(_tag_style, Rect2(-tw * 0.5 - 10.0, -fs - 4.0, tw + 20.0, fs + 14.0))
	draw_string(f, Vector2(-tw * 0.5, 0.0), TAG_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 1))
	draw_set_transform_matrix(Transform2D.IDENTITY)

static func is_player_in_build_mode(tree: SceneTree) -> bool:
	if tree == null:
		return false
	var p := tree.get_first_node_in_group("player")
	if p != null and "is_build_mode" in p:
		return bool(p.is_build_mode)
	return false

static func can_rotate_port(port: Node2D) -> bool:
	if port == null or not port.is_inside_tree():
		return false
	if not is_player_in_build_mode(port.get_tree()):
		return false
	var parent_mod := port.get_parent()
	if parent_mod != null:
		if parent_mod.has_meta("is_ghost") and bool(parent_mod.get_meta("is_ghost")):
			return true
		if "is_constructing" in parent_mod and bool(parent_mod.is_constructing):
			return true
	return false

static func rotate_port_around_module(port: Node2D) -> void:
	var parent_mod := port.get_parent() as Node2D
	if parent_mod == null:
		port.rotation += PI * 0.5
		return

	var center := Vector2.ZERO
	var col := parent_mod.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		center = col.position

	var rel := port.position - center
	port.position = center + Vector2(-rel.y, rel.x)
	port.rotation = fposmod(port.rotation + PI * 0.5, TAU)
