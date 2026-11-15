extends Node

enum Phase { INTRO, BUILD, ROVER, SURVIVE, DEBRIEF }
var current_phase: Phase = Phase.BUILD
var current_sol: int = 1
var mass_budget: float = 2000.0

var inventory: Dictionary = {
	"Solar Panel": 0,
	"Life Support": 0,
	"Thermal Control": 0,
	"Shield": 0,
	"Comms": 0
}

var pending_delivery: Dictionary = {
	"Solar Panel": 0,
	"Life Support": 0,
	"Thermal Control": 0,
	"Shield": 0,
	"Comms": 0
}

var catalog: Array[Dictionary] = [
	{
		"id": "Solar Panel",
		"title": "SOLAR ARRAY",
		"mass": 400.0,
		"power": 0.0,
		"scene_path": "res://scenes/modules/solar_panel.tscn",
		"desc": "WHAT IT DOES:\nMakes free power from the sun. If you wire it directly to a module, that module will NEVER randomly break!\n\nNASA FACT:\nMars is much further from the Sun than Earth, so solar panels must be huge. But they are very vulnerable to Martian dust storms which block 99% of sunlight.",
		"color": Color(1.0, 0.8, 0.25)
	},
	{
		"id": "Life Support",
		"title": "OXYGEN MAKER",
		"mass": 1000.0,
		"power": 30.0,
		"scene_path": "res://scenes/modules/life_support.tscn",
		"desc": "WHAT IT DOES:\nPumps fresh air into your base so you can breathe! Wire it to the Reactor to keep your Oxygen bar full.\n\nNASA FACT:\nMars air is 95% carbon dioxide. NASA's MOXIE machine zaps Mars air with electricity to turn it into real breathable oxygen—just like a mechanical tree!",
		"color": Color(0.35, 0.85, 1.0)
	},
	{
		"id": "Thermal Control",
		"title": "SPACE HEATER",
		"mass": 800.0,
		"power": 20.0,
		"scene_path": "res://scenes/modules/thermal.tscn",
		"desc": "WHAT IT DOES:\nKeeps your base warm and cozy! Without power, the base freezes and your Temperature bar drops fast.\n\nNASA FACT:\nAt night, Mars drops to -60°C (-80°F)—colder than Antarctica! Astronauts use heated fluid loops to stop their equipment from freezing solid.",
		"color": Color(1.0, 0.55, 0.3)
	},
	{
		"id": "Shield",
		"title": "RADIATION SHIELD",
		"mass": 600.0,
		"power": 25.0,
		"scene_path": "res://scenes/modules/shield.tscn",
		"desc": "WHAT IT DOES:\nProtects the base from deadly space storms (solar flares). Keep it powered during a storm or it's game over!\n\nNASA FACT:\nEarth has a magnetic field that blocks radiation, but Mars doesn't. A single solar flare can deliver a lethal dose of radiation to astronauts on the surface in minutes.",
		"color": Color(0.7, 0.55, 1.0)
	},
	{
		"id": "Comms",
		"title": "COMMS DISH",
		"mass": 500.0,
		"power": 15.0,
		"scene_path": "res://scenes/modules/comms.tscn",
		"desc": "WHAT IT DOES:\nA big dish to call home and get early weather warnings. If it loses power, you won't see storms coming.\n\nNASA FACT:\nIt takes up to 24 minutes for a signal to travel between Mars and Earth. Because of this delay, astronauts must handle emergencies on their own without Mission Control.",
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
