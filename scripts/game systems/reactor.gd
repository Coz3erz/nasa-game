extends BaseModule

var active_wires: Array = []

func _ready() -> void:
	module_name = "Reactor"
	can_accept_wires = false
	is_powered = true
	super._ready()
func request_new_wire(player_pos: Vector2) -> Dictionary:
	var center = global_position + Vector2(64, 64)
	var dir = (player_pos - center).normalized()
	if dir == Vector2.ZERO: dir = Vector2.RIGHT
	var socket_pos = center + dir * 64.0

	var wire = Line2D.new()
	wire.top_level = true
	wire.width = 12.0
	wire.default_color = Color(0.8, 0.1, 0.1)
	wire.joint_mode = Line2D.LINE_JOINT_ROUND
	wire.begin_cap_mode = Line2D.LINE_CAP_ROUND
	wire.end_cap_mode = Line2D.LINE_CAP_ROUND
	wire.antialiased = true
	wire.z_index = 1
	get_parent().add_child(wire)

	var shadow = Line2D.new()
	shadow.top_level = true
	shadow.width = 16.0
	shadow.default_color = Color(0, 0, 0, 0.45)
	shadow.joint_mode = Line2D.LINE_JOINT_ROUND
	shadow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	shadow.end_cap_mode = Line2D.LINE_CAP_ROUND
	shadow.antialiased = true
	shadow.position = Vector2(4, 6)
	shadow.z_index = -1
	get_parent().add_child(shadow)

	var wire_data = {
		"wire": wire,
		"shadow": shadow,
		"socket_pos": socket_pos,
		"is_active": true
	}
	active_wires.append(wire_data)
	return wire_data

func release_wire(wire_data: Dictionary) -> void:
	active_wires.erase(wire_data)
	if is_instance_valid(wire_data["wire"]): wire_data["wire"].queue_free()
	if is_instance_valid(wire_data["shadow"]): wire_data["shadow"].queue_free()
