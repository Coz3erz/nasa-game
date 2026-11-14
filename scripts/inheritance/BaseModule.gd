extends StaticBody2D
class_name BaseModule

@export var module_name: String = "Module"
@export var mass_cost: float = 1000.0
@export var power_draw: float = 30.0
@export var grid_size: Vector2i = Vector2i(1, 1)
@export var can_accept_wires: bool = true

var is_powered: bool = false
var is_broken: bool = false
var connected_wires: Array = []

func _ready() -> void:
	BaseManager.active_modules.append(self)

func break_module() -> void:
	if not is_broken:
		is_broken = true
		is_powered = false
		_disconnect_all_wires()
		print(module_name, " has broken!")

func accept_wire(wire_data: Dictionary) -> void:
	if not can_accept_wires:
		return
	connected_wires.append(wire_data)
	is_powered = true
	BaseManager.calculate_power()

func remove_wire(wire_data: Dictionary) -> void:
	connected_wires.erase(wire_data)
	if connected_wires.is_empty():
		is_powered = false
	BaseManager.calculate_power()

func _disconnect_all_wires() -> void:
	for w in connected_wires:
		if is_instance_valid(w["wire"]):
			w["wire"].queue_free()
		if is_instance_valid(w["shadow"]):
			w["shadow"].queue_free()
	connected_wires.clear()
