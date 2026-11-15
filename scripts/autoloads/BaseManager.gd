extends Node

var active_modules: Array = []
var total_power: float = 0.0
var current_power_draw: float = 0.0
var reactor_energy: float = 100.0
var oxygen_level: float = 100.0
var temp_level: float = 100.0

var failure_roll_interval: float = 6.0
var failure_chance: float = 0.18
var _failure_timer: float = 0.0

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

	# Pass 1: Solar Panels are self-powered once built
	for mod in active_modules:
		if mod.module_name == "Solar Panel":
			mod.is_powered = not mod.is_broken and not mod.is_constructing

	# Pass 2: Reactor is ONLY powered if a Solar Panel is wired into it
	for mod in active_modules:
		if mod.module_name == "Reactor":
			if not mod.is_broken and not mod.is_constructing and mod.is_fed_by_solar() and reactor_energy > 0.0:
				mod.is_powered = true
				total_power += 100.0
			else:
				mod.is_powered = false

	# Pass 3: Modules powered directly by Solar (free + failure-immune) or by an active Reactor
	for mod in active_modules:
		if mod.module_name == "Solar Panel" or mod.module_name == "Reactor":
			continue

		if mod.is_broken or mod.is_constructing:
			mod.is_powered = false
			continue

		if mod.is_fed_by_solar():
			mod.is_powered = true
		elif mod.is_fed_by_reactor() and (current_power_draw + mod.power_draw <= total_power):
			mod.is_powered = true
			current_power_draw += mod.power_draw
		else:
			mod.is_powered = false

	if get_node_or_null("/root/EventBus") != null:
		EventBus.power_changed.emit(current_power_draw, total_power)

func _tick_power_and_systems(delta: float) -> void:
	if current_power_draw > 0.0 and total_power > 0.0 and reactor_energy > 0.0:
		var drain_rate: float = (current_power_draw / 100.0) * 1.2
		reactor_energy = maxf(0.0, reactor_energy - drain_rate * delta)
		if reactor_energy <= 0.0:
			calculate_power()

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
		oxygen_level = minf(100.0, oxygen_level + 3.5 * delta)
	else:
		oxygen_level = maxf(0.0, oxygen_level - 2.2 * delta)

	if thermal_active:
		temp_level = minf(100.0, temp_level + 3.0 * delta)
	else:
		temp_level = maxf(0.0, temp_level - 1.8 * delta)

	if oxygen_level <= 0.0 and get_node_or_null("/root/EventBus") != null:
		EventBus.game_over.emit("OXYGEN DEPLETED")
	elif temp_level <= 0.0 and get_node_or_null("/root/EventBus") != null:
		EventBus.game_over.emit("HYPOTHERMIA - THERMAL FAILURE")

func _tick_failure_dice(delta: float) -> void:
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
