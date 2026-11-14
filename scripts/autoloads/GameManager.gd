extends Node

enum Phase { INTRO, BUILD, ROVER, SURVIVE, DEBRIEF }
var current_phase: Phase = Phase.BUILD
var current_sol: int = 1
var mass_budget: float = 2000.0

var inventory: Dictionary = {
	"Life Support": 0,
	"Thermal Control": 0
}

var catalog: Array[Dictionary] = [
	{
		"id": "Life Support",
		"mass": 1000.0,
		"power": 30.0,
		"scene_path": "res://scenes/modules/life_support.tscn",
		"desc": "Generates breathable O2 for the habitat.\nNASA Spec: Crew requires 0.84 kg of O2 per day.\nWithout power, O2 reserves critical in 30s."
	},
	{
		"id": "Thermal Control",
		"mass": 800.0,
		"power": 20.0,
		"scene_path": "res://scenes/modules/thermal.tscn",
		"desc": "Maintains internal cabin temperature against Martian -60°C lows.\nPrevents hypothermia and coolant line freeze."
	}
]

func add_to_inventory(item_id: String) -> void:
	inventory[item_id] = inventory.get(item_id, 0) + 1

func remove_from_inventory(item_id: String) -> bool:
	if inventory.get(item_id, 0) > 0:
		inventory[item_id] -= 1
		return true
	return false

func get_item_count(item_id: String) -> int:
	return inventory.get(item_id, 0)
