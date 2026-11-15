
extends Node

enum Phase { INTRO, BUILD, ROVER, SURVIVE, DEBRIEF }
var current_phase: Phase = Phase.BUILD
var current_sol: int = 1
var mass_budget: float = 2400.0
var total_days: int = 5
var day_length: float = 240.0

signal day_failed(reason: String)

var inventory: Dictionary = {
	"Solar Panel": 0,
	"Life Support": 0,
	"Thermal Control": 0,
	"Shield": 0,
	"Comms": 0,
	"Med Kit": 0
}

var pending_delivery: Dictionary = {
	"Solar Panel": 0,
	"Life Support": 0,
	"Thermal Control": 0,
	"Shield": 0,
	"Comms": 0,
	"Med Kit": 0
}

var catalog: Array[Dictionary] = [
	{
		"id": "Solar Panel",
		"title": "SOLAR ARRAY",
		"mass": 350.0,
		"power": 0.0,
		"scene_path": "res://scenes/modules/solar_panel.tscn",
		"desc": "WHAT IT DOES:\nTurns sunlight into power. Each panel you plug into the reactor doubles what it gives you: 50 kilowatts, then 100, then 200. Plug a panel straight into a machine and that machine can never fail.\n\nWHY IT MATTERS:\nMars is about 1.5 times farther from the Sun than Earth, so sunlight here is less than half as strong. Dust storms can cover panels and cut their output badly.",
		"color": Color(1.0, 0.8, 0.25)
	},
	{
		"id": "Life Support",
		"title": "OXYGEN MAKER",
		"mass": 900.0,
		"power": 30.0,
		"scene_path": "res://scenes/modules/life_support.tscn",
		"desc": "WHAT IT DOES:\nMakes breathable air for the base. Uses 30 kilowatts. Keep it running or your air bar drains.\n\nWHY IT MATTERS:\nMars air is 95% carbon dioxide. NASA's MOXIE experiment on the Perseverance rover split that carbon dioxide with electricity and made real oxygen.",
		"color": Color(0.35, 0.85, 1.0)
	},
	{
		"id": "Thermal Control",
		"title": "SPACE HEATER",
		"mass": 700.0,
		"power": 20.0,
		"scene_path": "res://scenes/modules/thermal.tscn",
		"desc": "WHAT IT DOES:\nKeeps the base warm. Uses 20 kilowatts. Without it your warmth bar falls and you start losing health.\n\nWHY IT MATTERS:\nNights on Mars drop to around -60 degrees C. That is colder than most of Antarctica, and the thin air barely holds any heat.",
		"color": Color(1.0, 0.55, 0.3)
	},
	{
		"id": "Shield",
		"title": "RADIATION SHIELD",
		"mass": 600.0,
		"power": 40.0,
		"scene_path": "res://scenes/modules/shield.tscn",
		"desc": "WHAT IT DOES:\nBlocks solar flares completely while it has power. No damage and nothing fails. It uses 40 kilowatts the whole time it runs, so it is expensive.\n\nWHY IT MATTERS:\nEarth's magnetic field deflects flare particles. Mars lost its field billions of years ago, so the radiation reaches the ground almost unblocked.",
		"color": Color(0.7, 0.55, 1.0)
	},
	{
		"id": "Comms",
		"title": "COMMS DISH",
		"mass": 450.0,
		"power": 15.0,
		"scene_path": "res://scenes/modules/comms.tscn",
		"desc": "WHAT IT DOES:\nPicks up a warning 15 seconds before a solar flare hits, which gives you time to unplug your machines. Uses 15 kilowatts. It will not warn you about dust storms.\n\nWHY IT MATTERS:\nA message between Mars and Earth takes 3 to 22 minutes each way, so crews on Mars have to handle emergencies themselves.",
		"color": Color(0.45, 1.0, 0.6)
	},
	{
		"id": "Med Kit",
		"title": "MED KIT",
		"mass": 150.0,
		"power": 0.0,
		"scene_path": "",
		"consumable": true,
		"desc": "WHAT IT DOES:\nRestores 45 health. Press H to use one once the rover has left. Weighs almost nothing.\n\nWHY IT MATTERS:\nThe nearest hospital is millions of kilometers away, so every astronaut is trained in first aid.",
		"color": Color(1.0, 0.45, 0.5)
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

func stage_for_rover_drop() -> bool:
	var has_any := false
	for k in inventory.keys():
		var count: int = inventory[k]
		pending_delivery[k] = count
		if count > 0:
			has_any = true
		inventory[k] = 0
	return has_any

func deliver_pending_supplies() -> void:
	for k in pending_delivery.keys():
		inventory[k] = inventory.get(k, 0) + pending_delivery[k]
		pending_delivery[k] = 0

func budget_for_day(day: int) -> float:
	return 2400.0 + 600.0 * float(day - 1)

func begin_day() -> void:
	for k in inventory.keys():
		inventory[k] = 0
	for k in pending_delivery.keys():
		pending_delivery[k] = 0
	mass_budget = budget_for_day(current_sol)
	current_phase = Phase.BUILD
	BaseManager.reset_for_day(current_sol)

func advance_day() -> void:
	current_sol += 1
	begin_day()

func restart_day() -> void:
	begin_day()

func restart_all() -> void:
	current_sol = 1
	begin_day()

