extends Node

var oxygen_level: float = 100.0
var temp_level: float = 100.0
var total_power: float = 0.0
var current_power_draw: float = 0.0
var active_modules: Array = []

func _ready() -> void:
	print("BaseManager Ready")

func calculate_power() -> void:
	current_power_draw = 0.0
	total_power = 0.0
	
	for mod in active_modules:
		if mod.module_name == "Reactor":
			total_power += 30.0
			if mod.is_powered:
				total_power += 70.0
		elif mod.is_powered and not mod.is_broken:
			current_power_draw += mod.power_draw
			
	EventBus.power_changed.emit(current_power_draw, total_power)
