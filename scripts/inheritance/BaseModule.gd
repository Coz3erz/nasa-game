extends StaticBody2D
class_name BaseModule

@export var module_name: String = "Module"
@export var mass_cost: float = 1000.0
@export var power_draw: float = 30.0
@export var grid_size: Vector2i = Vector2i(1, 1)

var is_powered: bool = false
var is_broken: bool = false

func _ready() -> void:
	BaseManager.active_modules.append(self)

func break_module() -> void:
	if not is_broken:
		is_broken = true
		is_powered = false
		print(module_name, " has broken!")
