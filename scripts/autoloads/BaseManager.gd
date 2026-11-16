# CHANGELOG (2026-11-16): Harsher difficulty curve (faster, likelier, multi-machine failures); Life Support fails 2.5x as often; exported machine-break VFX/SFX (break_module_with_fx).
extends Node

const EARTH_PANEL_RATING_KW: float = 116.086660
const BASE_REACTOR_POWER: float = EARTH_PANEL_RATING_KW * MarsData.SOLAR_EFFICIENCY_VS_EARTH

@export_group("Machine Break VFX")
## Master switch for the break effect (VFX + sound + small camera shake).
@export var break_vfx_enabled: bool = true
## Your own effect scene. Spawned at the machine's centre when it breaks.
## Leave empty to use the built-in sparks + smoke burst.
@export var break_vfx_scene: PackedScene
## Seconds before a spawned break_vfx_scene is freed.
@export var break_vfx_lifetime: float = 2.5
@export var break_sfx: AudioStream
@export var break_sfx_volume_db: float = -4.0
@export var break_camera_shake: float = 0.3

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
var failure_roll_interval: float = 18.0
var failure_chance: float = 0.18
var life_support_fail_mult: float = 2.5  ## Life Support is this much likelier to fail than other machines
var max_breaks_per_roll: int = 1
var _failure_timer: float = 0.0
var _life_support_commissioned := false
var _thermal_commissioned := false
static var _fx_tex: GradientTexture2D = null

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

	# Shuffle so list order never decides who breaks first.
	candidates.shuffle()
	var breaks := 0
	for mod in candidates:
		var chance := failure_chance
		if mod.module_name == "Life Support":
			chance *= life_support_fail_mult
		if randf() < minf(chance, 0.95):
			break_module_with_fx(mod)
			breaks += 1
			if breaks >= max_breaks_per_roll:
				break

func apply_day(day: int) -> void:
	var k := float(maxi(day, 1) - 1)
	failure_roll_interval = maxf(5.0, 18.0 - 2.5 * k)       # d1 18s ... d7 5s
	failure_chance = clampf(0.18 + 0.07 * k, 0.0, 0.9)      # d1 18% ... d7 60%
	max_breaks_per_roll = 1 + int(k / 3.0)                  # d1-3: 1, d4-6: 2, d7: 3
	hazard_interval = maxf(35.0, 100.0 * pow(0.76, k))
	o2_drain = 6.25 * (1.0 + 0.20 * k)
	temp_drain = 2.5 * (1.0 + 0.20 * k)
	reactor_drain_mult = 0.4 + 0.15 * k
	health_drain = 4.0 + 1.5 * k

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

# ---------------------------------------------------------------- machine break VFX
## Use this instead of calling module.break_module() directly, so every break
## (random failures and solar flares) plays the same exported effect.
func break_module_with_fx(mod: Node) -> void:
	if not is_instance_valid(mod):
		return
	mod.break_module()
	_play_break_fx(mod)

func _play_break_fx(mod: Node) -> void:
	if not break_vfx_enabled:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var pos := Vector2.ZERO
	if mod.has_method("get_center"):
		pos = mod.get_center()
	elif mod is Node2D:
		pos = (mod as Node2D).global_position

	if break_vfx_scene != null:
		var fx := break_vfx_scene.instantiate()
		scene_root.add_child(fx)
		if fx is Node2D:
			(fx as Node2D).global_position = pos
			(fx as Node2D).z_index = 85
		_start_particles(fx)
		get_tree().create_timer(break_vfx_lifetime).timeout.connect(func() -> void:
			if is_instance_valid(fx):
				fx.queue_free())
	elif GameSettings.particles_enabled():
		_spawn_default_break_fx(scene_root, pos)

	if break_sfx != null:
		var ap := AudioStreamPlayer.new()
		ap.stream = break_sfx
		ap.volume_db = break_sfx_volume_db
		ap.bus = &"SFX" if AudioServer.get_bus_index("SFX") != -1 else &"Master"
		scene_root.add_child(ap)
		ap.finished.connect(ap.queue_free)
		ap.play()

	if break_camera_shake > 0.0:
		for p in get_tree().get_nodes_in_group("player"):
			if p.has_method("shake"):
				p.call("shake", break_camera_shake)

func _start_particles(n: Node) -> void:
	if n is GPUParticles2D:
		(n as GPUParticles2D).emitting = true
	elif n is CPUParticles2D:
		(n as CPUParticles2D).emitting = true
	for c in n.get_children():
		_start_particles(c)

static func _soft_tex() -> GradientTexture2D:
	if _fx_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_fx_tex = GradientTexture2D.new()
		_fx_tex.gradient = g
		_fx_tex.fill = GradientTexture2D.FILL_RADIAL
		_fx_tex.fill_from = Vector2(0.5, 0.5)
		_fx_tex.fill_to = Vector2(1.0, 0.5)
		_fx_tex.width = 64
		_fx_tex.height = 64
	return _fx_tex

func _spawn_default_break_fx(parent: Node, pos: Vector2) -> void:
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))

	var sparks := CPUParticles2D.new()
	sparks.texture = _soft_tex()
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.amount = 22
	sparks.lifetime = 0.6
	sparks.spread = 180.0
	sparks.initial_velocity_min = 90.0
	sparks.initial_velocity_max = 260.0
	sparks.gravity = Vector2(0, 320)
	sparks.scale_amount_min = 0.04
	sparks.scale_amount_max = 0.10
	sparks.color = Color(1.8, 1.2, 0.5, 1.0)
	sparks.color_ramp = fade
	sparks.local_coords = false
	sparks.z_index = 85
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sparks.material = add
	parent.add_child(sparks)
	sparks.global_position = pos
	sparks.emitting = true

	var smoke := CPUParticles2D.new()
	smoke.texture = _soft_tex()
	smoke.one_shot = true
	smoke.explosiveness = 0.6
	smoke.amount = 18
	smoke.lifetime = 1.6
	smoke.direction = Vector2(0, -1)
	smoke.spread = 40.0
	smoke.initial_velocity_min = 20.0
	smoke.initial_velocity_max = 60.0
	smoke.gravity = Vector2(0, -18)
	smoke.scale_amount_min = 0.35
	smoke.scale_amount_max = 0.8
	smoke.color = Color(0.22, 0.22, 0.25, 0.6)
	smoke.color_ramp = fade
	smoke.local_coords = false
	smoke.z_index = 84
	parent.add_child(smoke)
	smoke.global_position = pos
	smoke.emitting = true

	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		if is_instance_valid(sparks):
			sparks.queue_free()
		if is_instance_valid(smoke):
			smoke.queue_free())
