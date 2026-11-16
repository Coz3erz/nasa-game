# CHANGELOG (2026-11-15): Route disconnects through atomic endpoint cleanup, including direct receiver removals.
@tool
extends StaticBody2D
class_name WireReceiver

@export var standby_color: Color = Color(0.25, 0.75, 1.0):
	set(value):
		standby_color = value
		queue_redraw()
@export var accepted_sources: PackedStringArray = PackedStringArray()
@export var capacity: int = 1
@export var target_module: BaseModule

var receiver_point: Marker2D = null
var connected_wire: Node2D = null
var connected_wires: Array[Node2D] = []
var pulse_time: float = 0.0
var _is_hovered: bool = false

var shadow_style: StyleBoxFlat
var housing_style: StyleBoxFlat
var well_style: StyleBoxFlat
var flange_style: StyleBoxFlat

func _ready() -> void:
	var old_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if old_sprite != null:
		old_sprite.visible = false

	receiver_point = get_node_or_null("ReceiverPoint") as Marker2D
	if receiver_point == null:
		receiver_point = get_node_or_null("RecieverPoint") as Marker2D

	_init_styles()
	queue_redraw()

	if not Engine.is_editor_hint():
		add_to_group("wire_receivers")
		if target_module == null and get_parent() is BaseModule:
			target_module = get_parent() as BaseModule

func _exit_tree() -> void:
	if _is_hovered:
		_is_hovered = false
		WirePort.hover_count = maxi(0, WirePort.hover_count - 1)

func _init_styles() -> void:
	shadow_style = StyleBoxFlat.new()
	shadow_style.bg_color = Color(0, 0, 0, 0.42)
	shadow_style.set_corner_radius_all(6)

	housing_style = StyleBoxFlat.new()
	housing_style.bg_color = Color(0.17, 0.19, 0.23)
	housing_style.border_color = Color(0.07, 0.08, 0.10)
	housing_style.set_border_width_all(2)
	housing_style.set_corner_radius_all(5)

	well_style = StyleBoxFlat.new()
	well_style.bg_color = Color(0.08, 0.09, 0.12)
	well_style.border_color = Color(0.25, 0.28, 0.33)
	well_style.set_border_width_all(1)
	well_style.set_corner_radius_all(3)

	flange_style = StyleBoxFlat.new()
	flange_style.bg_color = Color(0.24, 0.27, 0.32)
	flange_style.border_color = Color(0.09, 0.10, 0.12)
	flange_style.set_border_width_all(1)
	flange_style.set_corner_radius_all(2)

func _process(delta: float) -> void:
	pulse_time += delta
	if not Engine.is_editor_hint():
		_update_hover_state()
	queue_redraw()

func _update_hover_state() -> void:
	var can_rot := WirePort.can_rotate_port(self)
	var mouse_close := false
	if can_rot:
		var local_m := to_local(get_global_mouse_position())
		mouse_close = Rect2(-22, -36, 44, 72).has_point(local_m)

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

func _clean_wires() -> void:
	for i in range(connected_wires.size() - 1, -1, -1):
		if not is_instance_valid(connected_wires[i]):
			connected_wires.remove_at(i)
	connected_wire = connected_wires.back() if not connected_wires.is_empty() else null

func get_receiver_position() -> Vector2:
	if receiver_point != null:
		return receiver_point.global_position
	return global_position

func accepts_wire(wire_node: Node2D = null) -> bool:
	if target_module == null and get_parent() is BaseModule:
		target_module = get_parent() as BaseModule
	if wire_node == null:
		return true
	if "source_module" in wire_node and is_instance_valid(wire_node.source_module):
		var src_mod: BaseModule = wire_node.source_module
		if src_mod == target_module:
			return false
		if target_module != null and target_module.module_name == "Reactor":
			return src_mod.module_name == "Solar Panel"
		if not accepted_sources.is_empty() and not accepted_sources.has(src_mod.module_name):
			return false
	return true

func can_accept_wire(wire_node: Node2D = null) -> bool:
	_clean_wires()
	if target_module == null and get_parent() is BaseModule:
		target_module = get_parent() as BaseModule
	if target_module == null:
		return false
	if target_module.is_constructing or target_module.is_broken or not target_module.can_accept_wires:
		return false

	# Reactor has infinite capacity for Solar Panel wires; other modules obey capacity
	var is_reactor: bool = (target_module.module_name == "Reactor")
	if not is_reactor and connected_wires.size() >= maxi(1, capacity):
		return false

	return accepts_wire(wire_node)

func accept_wire(wire_node: Node2D) -> void:
	if not is_instance_valid(wire_node):
		return
	if wire_node.is_plugged and wire_node.plugged_receiver == self:
		return
	if not can_accept_wire(wire_node):
		return
	if wire_node.is_plugged:
		wire_node.disconnect_wire(wire_node.hand_pos)
	_clean_wires()
	if target_module == null and get_parent() is BaseModule:
		target_module = get_parent() as BaseModule
	if not connected_wires.has(wire_node):
		connected_wires.append(wire_node)
	connected_wire = wire_node
	if target_module != null:
		target_module.accept_wire(wire_node)
	wire_node.plug_in(self) # emits only after both logical endpoints are committed
	queue_redraw()

func remove_wire(wire_node: Node2D) -> void:
	if is_instance_valid(wire_node) and wire_node.is_plugged and wire_node.plugged_receiver == self:
		wire_node.disconnect_wire(get_receiver_position())
		return
	connected_wires.erase(wire_node)
	_clean_wires()
	if target_module != null:
		target_module.remove_wire(wire_node)
	queue_redraw()

func _get_active_color() -> Color:
	_clean_wires()
	if connected_wire != null and is_instance_valid(connected_wire) and "wire_color" in connected_wire:
		return connected_wire.wire_color
	if target_module != null and target_module.is_broken:
		return Color(1.0, 0.15, 0.15)
	return standby_color

func _draw() -> void:
	if housing_style == null or shadow_style == null:
		_init_styles()

	_clean_wires()
	var is_plugged_in: bool = not connected_wires.is_empty()
	var active_col: Color = _get_active_color()
	var pulse: float = 0.7 + 0.3 * sin(pulse_time * (6.0 if is_plugged_in else 3.0))

	if _is_hovered:
		draw_rect(Rect2(-20, -35, 40, 70), Color(0.42, 1.0, 0.55, 0.4), false, 2.0)

	draw_style_box(shadow_style, Rect2(-14, -30, 32, 64))
	draw_style_box(flange_style, Rect2(-18, -26, 8, 52))
	draw_style_box(housing_style, Rect2(-14, -32, 30, 64))
	draw_style_box(well_style, Rect2(-8, -22, 20, 44))

	var bolt_col: Color = Color(0.40, 0.44, 0.50)
	draw_circle(Vector2(-10, -27), 1.8, bolt_col)
	draw_circle(Vector2(11, -27), 1.8, bolt_col)
	draw_circle(Vector2(-10, 27), 1.8, bolt_col)
	draw_circle(Vector2(11, 27), 1.8, bolt_col)

	var rail_col: Color = active_col if is_plugged_in else active_col.darkened(0.45)
	rail_col.a = 0.95 if is_plugged_in else 0.55 * pulse
	draw_line(Vector2(-4, -25), Vector2(10, -25), rail_col, 2.5)
	draw_line(Vector2(-4, 25), Vector2(10, 25), rail_col, 2.5)
	draw_line(Vector2(-11, -16), Vector2(-11, 16), rail_col, 2.0)

	var sock_pos: Vector2 = Vector2(6, 0)
	if receiver_point != null:
		sock_pos = receiver_point.position - Vector2(6, 0)

	if is_plugged_in:
		var glow: Color = active_col.lightened(0.25)
		glow.a = 0.35 * pulse
		draw_circle(sock_pos, 12.0, glow)

	draw_circle(sock_pos, 9.0, Color(0.14, 0.16, 0.20))
	draw_arc(sock_pos, 9.0, 0.0, TAU, 24, rail_col, 2.0, true)

	var slot_col: Color = active_col.lightened(0.2) if is_plugged_in else Color(0.03, 0.04, 0.05)
	draw_rect(Rect2(sock_pos + Vector2(-3, -6), Vector2(6, 3.5)), slot_col)
	draw_rect(Rect2(sock_pos + Vector2(-3, 2.5), Vector2(6, 3.5)), slot_col)

	var led_top_col: Color = active_col.lightened(0.25) if is_plugged_in else Color(0.18, 0.20, 0.24)
	draw_circle(Vector2(0, -15), 2.2, led_top_col)
	draw_circle(Vector2(0, 15), 2.2, led_top_col)
