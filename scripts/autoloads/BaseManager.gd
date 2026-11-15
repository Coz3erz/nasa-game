# CHANGELOG (2026-11-15): Remove passive healing; 8s oxygen / 20s warmth with unbounded daily scaling; NASA-calibrated panels and frequency curve.
extends Node

const EARTH_PANEL_RATING_KW: float = 116.086660
const BASE_REACTOR_POWER: float = EARTH_PANEL_RATING_KW * MarsData.SOLAR_EFFICIENCY_VS_EARTH

var active_modules: Array = []
var total_power: float = 0.0
var current_power_draw: float = 0.0
var reactor_energy: float = 100.0
var oxygen_level: float = 100.0
var temp_level: float = 100.0

var health: float = 100.0
var health_drain: float = 4.0
var o2_drain: float = 6.25
var temp_drain: float = 2.5
var reactor_drain_mult: float = 0.4
var hazard_interval: float = 75.0
var day_failed_sent: bool = false
var solar_efficiency: float = 1.0      ## dust storms drop this to 0.5
var failure_roll_interval: float = 24.0
var failure_chance: float = 0.10
var _failure_timer: float = 0.0
var _life_support_commissioned := false
var _thermal_commissioned := false

func has_module(module_name: String) -> bool:
	for module in active_modules:
		if is_instance_valid(module) and module.module_name == module_name and not module.is_constructing:
			return true
	return false

func _process(delta: float) -> void:
	if get_node_or_null("/root/GameManager") != null:
		if GameManager.current_phase != GameManager.Phase.SURVIVE:
			return

	_tick_power_and_systems(delta)
	_tick_random_failures(delta)

func calculate_power() -> void:
	for i in range(active_modules.size() - 1, -1, -1):
		if not is_instance_valid(active_modules[i]):
			active_modules.remove_at(i)

	current_power_draw = 0.0
	total_power = 0.0

	for mod in active_modules:
		if mod.module_name == "Solar Panel":
			mod.is_powered = not mod.is_broken and not mod.is_constructing

	for mod in active_modules:
		if mod.module_name == "Reactor":
			var solar_count: int = mod.get_connected_solar_count()
			if not mod.is_broken and not mod.is_constructing and solar_count > 0 and reactor_energy > 0.0:
				mod.is_powered = true
				total_power += BASE_REACTOR_POWER * pow(2.0, float(solar_count - 1)) * solar_efficiency
			else:
				mod.is_powered = false

	for mod in active_modules:
		if mod.module_name == "Solar Panel" or mod.module_name == "Reactor":
			continue

		if mod.is_broken or mod.is_constructing:
			mod.is_powered = false
			continue

		if mod.is_fed_by_solar():
			mod.is_powered = solar_efficiency >= 1.0 or mod.power_draw <= BASE_REACTOR_POWER * solar_efficiency
		elif mod.is_fed_by_reactor() and (current_power_draw + mod.power_draw <= total_power):
			mod.is_powered = true
			current_power_draw += mod.power_draw
		else:
			mod.is_powered = false

	if get_node_or_null("/root/EventBus") != null:
		EventBus.power_changed.emit(current_power_draw, total_power)

func _tick_power_and_systems(delta: float) -> void:
	if current_power_draw > 0.0 and total_power > 0.0 and reactor_energy > 0.0:
		var drain_rate: float = (current_power_draw / 100.0) * reactor_drain_mult
		reactor_energy = maxf(0.0, reactor_energy - drain_rate * delta)
		if reactor_energy <= 0.0:
			calculate_power()

	_life_support_commissioned = _life_support_commissioned or has_module("Life Support")
	_thermal_commissioned = _thermal_commissioned or has_module("Thermal Control")
	var life_support_active: bool = false
	var thermal_active: bool = false

	for mod in active_modules:
		if not is_instance_valid(mod) or mod.is_broken or mod.is_constructing or not mod.is_powered:
			continue
		if mod.module_name == "Life Support":
			life_support_active = true
		elif mod.module_name == "Thermal Control":
			thermal_active = true

	if life_support_active:
		oxygen_level = minf(100.0, oxygen_level + 2.5 * delta)
	else:
		oxygen_level = maxf(0.0, oxygen_level - o2_drain * (1.0 if _life_support_commissioned else 1.0 / 3.0) * delta)

	if thermal_active:
		temp_level = minf(100.0, temp_level + 2.0 * delta)
	else:
		temp_level = maxf(0.0, temp_level - temp_drain * (1.0 if _thermal_commissioned else 1.0 / 3.0) * delta)

	var reason := ""
	if oxygen_level <= 0.0:
		reason = "OUT OF AIR!"
	elif temp_level <= 0.0:
		reason = "TOO COLD!"
	if reason != "":
		health = maxf(0.0, health - health_drain * delta)
		if get_node_or_null("/root/EventBus") != null:
			EventBus.game_over.emit(reason)
		if health <= 0.0 and not day_failed_sent:
			day_failed_sent = true
			GameManager.day_failed.emit(reason)


func _tick_random_failures(delta: float) -> void:
	_failure_timer += delta
	if _failure_timer < failure_roll_interval:
		return
	_failure_timer = 0.0

	var candidates: Array[BaseModule] = []
	for mod in active_modules:
		if not is_instance_valid(mod):
			continue
		if mod.is_broken or mod.is_constructing or not mod.is_powered:
			continue
		if mod.has_failure_immunity():
			continue
		candidates.append(mod)

	if candidates.is_empty():
		return

	for mod in candidates:
		if randf() < failure_chance:
			mod.break_module()
			break

func apply_day(day: int) -> void:
	var k := float(maxi(day, 1) - 1)
	failure_roll_interval = maxf(6.0, 24.0 - 4.5 * k)
	failure_chance = clampf(0.10 + 0.05 * k, 0.0, 1.0)
	hazard_interval = maxf(50.0, 120.0 * pow(0.75, k))
	o2_drain = 6.25 * (1.0 + 0.15 * k)
	temp_drain = 2.5 * (1.0 + 0.15 * k)
	reactor_drain_mult = 0.4 + 0.1 * k
	health_drain = 4.0 + 1.0 * k

func reset_for_day(day: int) -> void:
	active_modules.clear()
	_life_support_commissioned = false
	_thermal_commissioned = false
	total_power = 0.0
	current_power_draw = 0.0
	reactor_energy = 100.0
	oxygen_level = 100.0
	temp_level = 100.0
	health = 100.0
	_failure_timer = 0.0
	day_failed_sent = false
	solar_efficiency = 1.0
	apply_day(day)
