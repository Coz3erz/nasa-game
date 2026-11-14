extends Node

var active_modules: Array = []
var total_power: float = 100.0
var current_power_draw: float = 0.0
var reactor_energy: float = 100.0
var oxygen_level: float = 100.0
var temp_level: float = 100.0

# ---- pacing: everything here is deliberately slow and relaxed ----
const REACTOR_DRAIN := 0.8      # reactor fuel burned per second at full load
const SOLAR_CHARGE := 0.35      # fuel given back per second by each solar panel
const O2_LOSS := 0.7
const O2_GAIN := 2.0
const TEMP_LOSS := 0.5
const TEMP_GAIN := 1.5

var failure_roll_interval: float = 18.0
var failure_chance: float = 0.12
var _failure_timer: float = 0.0
var _blackout := false

func _process(delta: float) -> void:
	if get_node_or_null("/root/GameManager") != null:
		if GameManager.current_phase != GameManager.Phase.SURVIVE:
			return

	_tick_power_and_systems(delta)
	_tick_failure_dice(delta)

func calculate_power() -> void:
	for i in range(active_modules.size() - 1, -1, -1):
		if not is_instance_valid(active_modules[i]):
			active_modules.remove_at(i)

	current_power_draw = 0.0
	total_power = 0.0

	for mod in active_modules:
		if mod.module_name == "Reactor" and not mod.is_broken and reactor_energy > 0.0:
			total_power += 100.0

	for mod in active_modules:
		if mod.module_name == "Reactor":
			mod.is_powered = reactor_energy > 0.0
			continue

		if mod.has_valid_power_source() and (current_power_draw + mod.power_draw <= total_power):
			mod.is_powered = true
			current_power_draw += mod.power_draw
		else:
			mod.is_powered = false

	if get_node_or_null("/root/EventBus") != null:
		EventBus.power_changed.emit(current_power_draw, total_power)

func _solar_inputs() -> int:
	var n := 0
	for mod in active_modules:
		if is_instance_valid(mod) and mod.module_name == "Reactor" and not mod.is_broken and mod.has_method("solar_count"):
			n += mod.solar_count()
	return n

func _tick_power_and_systems(delta: float) -> void:
	if current_power_draw > 0.0 and reactor_energy > 0.0:
		var drain_rate: float = (current_power_draw / 100.0) * REACTOR_DRAIN
		reactor_energy = maxf(0.0, reactor_energy - drain_rate * delta)
		if reactor_energy <= 0.0:
			_blackout = true
			calculate_power()

	var solar := _solar_inputs()
	if solar > 0:
		reactor_energy = minf(100.0, reactor_energy + solar * SOLAR_CHARGE * delta)
		if _blackout and reactor_energy >= 5.0:
			_blackout = false
			calculate_power()

	var life_support_active: bool = false
	var thermal_active: bool = false

	for mod in active_modules:
		if not is_instance_valid(mod) or mod.is_broken or not mod.is_powered:
			continue
		if mod.module_name == "Life Support":
			life_support_active = true
		elif mod.module_name == "Thermal Control":
			thermal_active = true

	if life_support_active:
		oxygen_level = minf(100.0, oxygen_level + O2_GAIN * delta)
	else:
		oxygen_level = maxf(0.0, oxygen_level - O2_LOSS * delta)

	if thermal_active:
		temp_level = minf(100.0, temp_level + TEMP_GAIN * delta)
	else:
		temp_level = maxf(0.0, temp_level - TEMP_LOSS * delta)

	if oxygen_level <= 0.0 and get_node_or_null("/root/EventBus") != null:
		EventBus.game_over.emit("We ran out of air!")
	elif temp_level <= 0.0 and get_node_or_null("/root/EventBus") != null:
		EventBus.game_over.emit("It got too cold!")

func _tick_failure_dice(delta: float) -> void:
	_failure_timer += delta
	if _failure_timer < failure_roll_interval:
		return
	_failure_timer = 0.0

	var candidates: Array[BaseModule] = []
	for mod in active_modules:
		if is_instance_valid(mod) and mod.module_name != "Reactor" and not mod.is_broken and mod.is_powered:
			candidates.append(mod)

	if candidates.is_empty():
		return

	for mod in candidates:
		if randf() < failure_chance:
			mod.break_module()
			break
