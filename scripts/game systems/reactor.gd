extends BaseModule

var active_wires: Array[Line2D] = []
var max_sockets: int = 3

func request_wire() -> Line2D:
	if active_wires.size() >= max_sockets:
		print("Reactor sockets full!")
		return null
		
	var new_wire = Line2D.new()
	new_wire.width = 8.0
	new_wire.default_color = Color.RED
	new_wire.z_index = -1
	add_child(new_wire)
	new_wire.position = Vector2.ZERO
	active_wires.append(new_wire)
	return new_wire

func remove_wire(wire: Line2D) -> void:
	active_wires.erase(wire)
	wire.queue_free()
