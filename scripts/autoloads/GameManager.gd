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
		"id": "Solar Panel",
		"mass": 400.0,
		"power": 0.0,
		"scene_path": "res://scenes/modules/solar_panel.tscn",
		"desc": "Makes free power from the sun.",
		"color": Color(1.0, 0.8, 0.25)
	},
	{
		"id": "Life Support",
		"mass": 1000.0,
		"power": 30.0,
		"scene_path": "res://scenes/modules/life_support.tscn",
		"desc": "Gives you air to breathe.",
		"color": Color(0.35, 0.85, 1.0)
	},
	{
		"id": "Thermal Control",
		"mass": 800.0,
		"power": 20.0,
		"scene_path": "res://scenes/modules/thermal.tscn",
		"desc": "Keeps the base nice and warm.",
		"color": Color(1.0, 0.55, 0.3)
	},
	{
		"id": "Shield",
		"mass": 600.0,
		"power": 25.0,
		"scene_path": "res://scenes/modules/shield.tscn",
		"desc": "Protects the base from space storms.",
		"color": Color(0.7, 0.55, 1.0)
	},
	{
		"id": "Comms",
		"mass": 500.0,
		"power": 15.0,
		"scene_path": "res://scenes/modules/comms.tscn",
		"desc": "A big dish to call home.",
		"color": Color(0.45, 1.0, 0.6)
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
