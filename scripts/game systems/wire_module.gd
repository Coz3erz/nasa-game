# CHANGELOG (2026-11-15): Route disconnects through atomic endpoint cleanup, including direct receiver removals.
@tool
extends StaticBody2D

@export var wire_scene: PackedScene
@export var wire_color: Color = Color(0.85, 0.15, 0.15):
	set(value):
		wire_color = value
		queue_redraw()
@export var module_texture: Texture2D

var spawned_wire: Node2D = null
var parent_module: BaseModule = null
var pulse_time: float = 0.0
var _is_hovered: bool = false

var base_plate_style: StyleBoxFlat
var inner_recess_style: StyleBoxFlat
var collar_style: StyleBoxFlat

func _ready() -> void:
	var old_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if old_sprite != null:
		old_sprite.visible = false

	_init_styles()
	queue_redraw()

	if not Engine.is_editor_hint():
		add_to_group("wire_sources")
		if get_parent() is BaseModule:
			parent_module = get_parent() as BaseModule

func _exit_tree() -> void:
	if _is_hovered:
		_is_hovered = false
		WirePort.hover_count = maxi(0, WirePort.hover_count - 1)

func _init_styles() -> void:
	base_plate_style = StyleBoxFlat.new()
	base_plate_style.bg_color = Color(0.18, 0.20, 0.24)
	base_plate_style.border_color = Color(0.08, 0.09, 0.11)
	base_plate_style.set_border_width_all(1)
	base_plate_style.set_corner_radius_all(2)

	inner_recess_style = StyleBoxFlat.new()
	inner_recess_style.bg_color = Color(0.09, 0.10, 0.13)
	inner_recess_style.set_corner_radius_all(1)

	collar_style = StyleBoxFlat.new()
	collar_style.bg_color = Color(0.26, 0.29, 0.34)
	collar_style.border_color = Color(0.12, 0.13, 0.16)
	collar_style.set_border_width_all(1)
	collar_style.set_corner_radius_all(1)

func _process(delta: float) -> void:
	pulse_time += delta
	if not Engine.is_editor_hint():
		_update_hover_state()
	queue_redraw()

func _update_hover_state() -> void:
	var can_rot := WirePort.can_rotate_port(self)
	var mouse_close = false
	if can_rot:
		var local_m := to_local(get_global_mouse_position())
		mouse_close = Rect2(-10, -14, 22, 28).has_point(local_m)

	if mouse_close and not _is_hovered:
		_is_hovered = true
		WirePort.hover_count += 1
	elif not mouse_close and _is_hovered:
		_is_hovered = false
		WirePort.hover_count = maxi(0, WirePort.hover_count - 1)

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _is_hovered:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if WirePort.can_rotate_port(self):
			WirePort.rotate_port_around_module(self)
			get_viewport().set_input_as_handled()
			queue_redraw()

func can_spawn_wire() -> bool:
	if parent_module == null and get_parent() is BaseModule:
		parent_module = get_parent() as BaseModule
	if parent_module != null:
		if parent_module.is_constructing or parent_module.is_broken:
			return false
		if parent_module.has_meta("is_ghost") and bool(parent_module.get_meta("is_ghost")):
			return false
	return spawned_wire == null or not is_instance_valid(spawned_wire)

func spawn_wire() -> Node2D:
	if not can_spawn_wire() or wire_scene == null:
		return null

	var new_wire: Node2D = wire_scene.instantiate() as Node2D
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_parent()
	scene.add_child(new_wire)
	if new_wire.has_method("register_ignored_rid"):
		new_wire.register_ignored_rid(get_rid())
		if parent_module != null:
			new_wire.register_ignored_rid(parent_module.get_rid())
	new_wire.setup(global_position, wire_color, self)
	spawned_wire = new_wire
	queue_redraw()
	return new_wire

func _draw() -> void:
	if base_plate_style == null:
		_init_styles()

	var has_wire_active: bool = spawned_wire != null and is_instance_valid(spawned_wire)
	var pulse: float = 0.75 + 0.25 * sin(pulse_time * 4.5)

	if _is_hovered:
		draw_rect(Rect2(-8, -12, 18, 24), Color(0.42, 1.0, 0.55, 0.35), false, 1.5)

	draw_rect(Rect2(-5, -9, 12, 19), Color(0, 0, 0, 0.4))
	draw_style_box(base_plate_style, Rect2(-6, -10, 12, 20))
	draw_style_box(inner_recess_style, Rect2(-4, -7, 8, 14))

	var rivet_col: Color = Color(0.38, 0.42, 0.48)
	draw_circle(Vector2(-4.0, -8.0), 0.8, rivet_col)
	draw_circle(Vector2(-4.0, 8.0), 0.8, rivet_col)

	draw_line(Vector2(-3.5, -5.5), Vector2(3.5, -5.5), wire_color.darkened(0.15), 1.5)
	draw_line(Vector2(-3.5, 5.5), Vector2(3.5, 5.5), wire_color.darkened(0.15), 1.5)

	draw_style_box(collar_style, Rect2(2, -4.5, 5, 9))

	var glow_col: Color = wire_color.lightened(0.25)
	glow_col.a = 0.35 * pulse if not has_wire_active else 0.6 * pulse
	draw_circle(Vector2(1.0, 0.0), 3.6, glow_col)
	draw_circle(Vector2(1.0, 0.0), 2.3, Color(0.05, 0.06, 0.08))
	draw_circle(Vector2(1.0, 0.0), 1.6, wire_color.lightened(0.15 * pulse))

	var led_col: Color = wire_color.lightened(0.35) if not has_wire_active else Color(0.2, 1.0, 0.4)
	draw_circle(Vector2(-2.2, 0.0), 1.1, led_col)
