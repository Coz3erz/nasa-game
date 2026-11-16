# CHANGELOG (2026-11-15): Day-one storms; sever every cable without hidden immunity; reuse cutscene gas shader and exported flare audio; storm penalty lasts until storm end.
extends Node
## AUTOLOAD (name it Hazards, put it LAST in the autoload list).
## Runs the two Mars hazards during the SURVIVE phase and reads BaseManager for shield / comms / power.
##
## SOLAR FLARE : Comms (powered) warns 15 s ahead. On impact: a powered Storm Shield blocks everything.
##               Without it: 15 damage, and every RUNNING module fails. Unplugged modules are safe.
## DUST STORM  : cannot be avoided. Every cable disconnects, solar output x0.5 for the storm, 25 damage.
## Modules wired DIRECTLY to a solar panel are immune to both (BaseModule.has_failure_immunity()).
@export_group("Hazard Audio")
@export var solar_flare_sfx: AudioStream
@export var solar_flare_volume_db: float = -8.0

signal demo_finished

const FLARE_WARNING_SECONDS := 15.0
const FLARE_DAMAGE := 15.0
const STORM_DAMAGE := 25.0
const STORM_SOLAR_FACTOR := 0.5
const STORM_SECONDS := 30.0
const FLARE_RISE_SECONDS := 1.75
const FLARE_FX_SECONDS := 5.25
const STORM_FROM_DAY := 1            # all hazards can occur from day one
const STORM_CHANCE := 0.45
const SHIELD := "Shield"
const COMMS := "Comms"

const AMBER := Color(1.0, 0.82, 0.35)
const ORANGE := Color(1.0, 0.55, 0.25)
const CYAN := Color(0.45, 0.9, 1.0)
const RED := Color(1.0, 0.4, 0.35)

enum S { IDLE, WARNING, STORM, BUSY }
var _state: S = S.IDLE
var _timer := 0.0
var _next_at := -1.0
var _warn_left := 0.0
var _storm_left := 0.0
var _gen := 0
var _fx: HazardFX

func _ready() -> void:
	_fx = HazardFX.new()
	add_child(_fx)

func _process(delta: float) -> void:
	var surviving: bool = GameManager.current_phase == GameManager.Phase.SURVIVE
	if not surviving:
		if _state != S.IDLE or _next_at >= 0.0:
			clear()
		return
	if _next_at < 0.0:
		_next_at = BaseManager.hazard_interval * randf_range(0.6, 1.0)
		_timer = 0.0
	match _state:
		S.IDLE:
			_timer += delta
			if _timer >= _next_at:
				_launch()
		S.WARNING:
			_warn_left -= delta
			_fx.set_warning(_warn_left)
			if _warn_left <= 0.0:
				_flare_hit()
		S.STORM:
			_storm_left -= delta
			if _storm_left <= 0.0:
				_end_storm()

# ---------------------------------------------------------------- public
func clear() -> void:
	_gen += 1
	_state = S.IDLE
	_next_at = -1.0
	_timer = 0.0
	BaseManager.solar_efficiency = 1.0
	BaseManager.calculate_power()
	if _fx != null:
		_fx.stop_all()

## Effects only, nothing breaks and nobody gets hurt. Used by the tutorial.
func demo(kind: String) -> void:
	var generation := _gen
	if kind == "storm":
		_fx.start_storm()
		await SceneDelay.timer(self, 7.0, false).timeout
		if generation != _gen:
			return
		_fx.stop_storm()
		await SceneDelay.timer(self, 2.5, false).timeout
	else:
		_fx.play_flare(false)
		GameAudio.play_flare(solar_flare_sfx, solar_flare_volume_db)
		await SceneDelay.timer(self, FLARE_FX_SECONDS + 0.4, false).timeout
	if generation == _gen:
		demo_finished.emit()

# ---------------------------------------------------------------- scheduling
func _launch() -> void:
	var storm: bool = GameManager.current_sol >= STORM_FROM_DAY and randf() < STORM_CHANCE
	if storm:
		_start_storm()
	else:
		_start_flare()

func _finish(hazard_name: String) -> void:
	_state = S.IDLE
	_timer = 0.0
	_next_at = maxf(20.0, BaseManager.hazard_interval * randf_range(0.8, 1.2))
	EventBus.hazard_ended.emit(hazard_name)

# ---------------------------------------------------------------- solar flare
func _start_flare() -> void:
	EventBus.hazard_started.emit("Solar Flare")
	if _module_running(COMMS):
		_state = S.WARNING
		_warn_left = FLARE_WARNING_SECONDS
		_fx.show_warning(true)
		_fx.toast("Comms picked up a solar flare. Impact in 15 seconds. Unplug your equipment.", AMBER)
	else:
		_flare_hit()

func _flare_hit() -> void:
	var gen := _gen
	_state = S.BUSY
	_fx.show_warning(false)
	var shielded := _module_running(SHIELD)
	_fx.play_flare(shielded)
	# Resolve gameplay impact at the visual peak, not at an invisible first frame.
	await SceneDelay.timer(self, FLARE_RISE_SECONDS, false).timeout
	if gen != _gen:
		return
	shielded = _module_running(SHIELD)
	GameAudio.play_flare(solar_flare_sfx, solar_flare_volume_db)
	if shielded:
		_fx.toast("The storm shield held. The flare did no damage.", CYAN)
	else:
		var broke := _break_modules(true)
		_damage(FLARE_DAMAGE, "SOLAR FLARE RADIATION")
		if broke > 0:
			_fx.toast("Solar flare! -%d health and %d system(s) failed." % [int(FLARE_DAMAGE), broke], RED)
		else:
			_fx.toast("Solar flare! -%d health. Nothing was plugged in, so no equipment failed." % int(FLARE_DAMAGE), RED)
	await SceneDelay.timer(self, FLARE_FX_SECONDS - FLARE_RISE_SECONDS, false).timeout
	if gen != _gen:
		return
	_finish("Solar Flare")

# ---------------------------------------------------------------- dust storm
func _start_storm() -> void:
	EventBus.hazard_started.emit("Dust Storm")
	var generation := _gen
	_state = S.BUSY
	_fx.start_storm()
	await SceneDelay.timer(self, 2.5, false).timeout
	if generation != _gen:
		return
	_state = S.STORM
	_storm_left = STORM_SECONDS
	BaseManager.solar_efficiency = STORM_SOLAR_FACTOR
	# Snapshot all wires, including immune solar links and the cable in the player hand.
	for cable in get_tree().get_nodes_in_group("wires"):
		if is_instance_valid(cable) and cable.has_method("disconnect_wire"):
			cable.disconnect_wire(cable.hand_pos)
	for player in get_tree().get_nodes_in_group("player"):
		player.current_wire = null
	BaseManager.calculate_power()
	_damage(STORM_DAMAGE, "CAUGHT IN THE DUST STORM")
	_fx.toast("Dust storm! All cables disconnected. Solar output is halved for the storm. Reconnect manually.", ORANGE)

func _end_storm() -> void:
	BaseManager.solar_efficiency = 1.0
	BaseManager.calculate_power()
	_fx.stop_storm()
	_fx.toast("The storm passed. Solar output is normal; cables stay disconnected until you reconnect them.", CYAN)
	_finish("Dust Storm")

# ---------------------------------------------------------------- helpers
func _module_running(module_name: String) -> bool:
	for m in BaseManager.active_modules:
		if is_instance_valid(m) and m.module_name == module_name and m.is_powered and not m.is_broken and not m.is_constructing:
			return true
	return false

## only_running = true: modules that are unplugged / off are left alone (flare).
func _break_modules(only_running: bool) -> int:
	var count := 0
	for m in BaseManager.active_modules.duplicate():
		if not is_instance_valid(m) or m.is_broken or m.is_constructing:
			continue
		if m.module_name == "Solar Panel":
			continue
		if only_running and not m.is_powered:
			continue
		if m.has_failure_immunity():
			continue
		m.break_module()
		count += 1
	return count

func _damage(amount: float, reason: String) -> void:
	BaseManager.health = maxf(0.0, BaseManager.health - amount)
	_fx.hurt_flash()
	if BaseManager.health <= 0.0 and not BaseManager.day_failed_sent:
		BaseManager.day_failed_sent = true
		GameManager.day_failed.emit(reason)

# =====================================================================
class HazardFX extends CanvasLayer:
	const STORM_SHADER := """
shader_type canvas_item;
uniform bool cheap_quality = false;
uniform float intensity = 0.0;
uniform float gust = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fbm(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * vn(p); p = p * 2.02 + vec2(5.1, 2.7); a *= 0.5; } return v; }
void fragment(){
	if (cheap_quality) {
		COLOR = vec4(0.60, 0.30, 0.12, intensity * 0.20);
	} else {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float asp = res.x / res.y;
	vec2 uv = UV;
	vec2 p = vec2(uv.x * asp, uv.y);
	float t = TIME;
	float g = 0.75 + 0.25 * sin(t * 0.6) + gust * 0.5;
	float haze = fbm(vec2(p.x * 0.9 - t * 0.9 * g, p.y * 1.6 + t * 0.05));
	float st = 0.0;
	for (int i = 0; i < 3; i++){
		float fi = float(i);
		float sp = 2.2 + fi * 1.6;
		vec2 q = vec2(p.x * (0.25 + fi * 0.08) - t * sp * g, p.y * (7.0 + fi * 9.0) + fi * 13.0);
		st += smoothstep(0.52, 0.85, fbm(q)) * (0.55 - fi * 0.12);
	}
	// Continuous, anti-aliased, slowly drifting motes, not square random cells.
	vec2 mote_uv = vec2(p.x * 34.0 - t * 0.75, p.y * 48.0 + t * 0.16);
	float grit = smoothstep(0.79, 0.94, vn(mote_uv)) * 0.12;
	float e = smoothstep(0.25, 1.0, length((uv - 0.5) * vec2(1.0, 1.15)));
	float a = intensity * (0.10 + 0.20 * haze + 0.16 * e);
	a += intensity * st * 0.30 + intensity * grit * 0.5;
	vec3 dust = mix(vec3(0.42, 0.17, 0.06), vec3(0.95, 0.52, 0.20), haze);
	dust = mix(dust, vec3(1.0, 0.72, 0.38), clamp(st * 0.6 + grit, 0.0, 1.0));
	dust *= mix(1.0, 0.55, e);
	COLOR = vec4(dust, clamp(a, 0.0, 0.88));
	}
}
"""
	# Flare look adapted from the opening cutscene's sun shader (same fbm, flare_burst blob + ring, same colour ramp).
	const FLARE_SHADER := """
shader_type canvas_item;
uniform bool cheap_quality = false;
render_mode blend_add;
uniform float age = -1.0;
uniform float strength = 1.0;
uniform float opacity = 0.0;
uniform vec4 core_col : source_color = vec4(1.0, 1.0, 0.98, 1.0);
uniform vec4 mid_col : source_color = vec4(1.0, 0.85, 0.40, 1.0);
uniform vec4 edge_col : source_color = vec4(1.0, 0.58, 0.15, 1.0);
float hash21(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fbm(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * noise(p); p = p * 2.03 + vec2(3.1, 7.3); a *= 0.5; } return v; }
float flare_burst(vec2 p, vec2 c, float a, float w){
	if (a < 0.0) { return 0.0; }
	float d = length(p - c);
	float env = smoothstep(0.0, 0.35, a) * exp(-a * 0.55);
	float rad = 0.16 + a * 0.22;
	float blob = exp(-(d * d) / (rad * rad));
	float ring = exp(-pow((d - a * 0.75) / 0.05, 2.0));
	return (blob * 1.9 + ring * 0.5) * env * w;
}
void fragment(){
	if (cheap_quality) {
		float a = age < 0.0 ? 0.0 : opacity * exp(-max(age, 0.0) * 1.5) * 0.22;
		COLOR = vec4(edge_col.rgb, a);
	} else {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float asp = res.x / res.y;
	vec2 p = (UV - 0.5) * 2.0;
	p.x *= asp;
	vec2 sun = vec2(asp * 0.72, -0.72);
	float flash = smoothstep(0.0, 0.05, age) * exp(-age * 1.5);
	float d = length(p - sun);
	float ang = atan(p.y - sun.y, p.x - sun.x);
	float x = exp(-d * 0.85) * flash * 1.7;
	x += pow(abs(sin(ang * 9.0 + fbm(vec2(ang * 3.0, age * 0.6)) * 4.0)), 6.0) * exp(-d * 1.05) * flash * 0.9;
	x += flare_burst(p, sun, age, 1.0);
	x += flare_burst(p, sun + vec2(-0.5, 0.35), age - 0.18, 0.8);
	x += flare_burst(p, sun + vec2(-1.1, 0.75), age - 0.34, 0.6);
	x += flash * 0.50 * (0.7 + 0.5 * fbm(p * 2.0 + age));
	x *= strength;
	vec3 c1 = mix(edge_col.rgb * vec3(0.55, 0.12, 0.05), edge_col.rgb, smoothstep(0.0, 0.55, x));
	c1 = mix(c1, mid_col.rgb, smoothstep(0.50, 1.15, x));
	c1 = mix(c1, core_col.rgb, smoothstep(1.05, 1.90, x));
	COLOR = (age < 0.0) ? vec4(0.0) : vec4(c1 * clamp(x, 0.0, 1.4), opacity);
	}
}
"""
	const EDGE_SHADER := """
shader_type canvas_item;
uniform bool cheap_quality = false;
uniform float pulse = 0.0;
uniform vec4 col : source_color = vec4(1.0, 0.7, 0.2, 1.0);
void fragment(){
	float e = smoothstep(0.35, 1.0, length((UV - 0.5) * 1.35));
	COLOR = vec4(col.rgb, e * pulse * 0.7);
}
"""
	var storm: ColorRect
	var flare: ColorRect
	var corona: ColorRect
	var _flare_tween: Tween
	var _flare_age_tween: Tween
	var edge: ColorRect
	var hurt: ColorRect
	var warn_label: Label
	var toasts: VBoxContainer
	var wind: AudioStreamPlayer
	var sfx: AudioStreamPlayer
	var beep: AudioStreamPlayer
	var _storm_level := 0.0
	var _shake := 0.0
	var _warn_on := false
	var _warn_left := 0.0
	var _last_beep := -1
	var _t := 0.0
	var _storm_tween: Tween

	func _make_rect(code: String) -> ColorRect:
		var r := ColorRect.new()
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.color = Color.WHITE
		if code != "":
			var sh := Shader.new()
			sh.code = code
			var mat := ShaderMaterial.new()
			mat.shader = sh
			r.material = mat
		add_child(r)
		return r

	func _ready() -> void:
		layer = 60
		storm = _make_rect(STORM_SHADER)
		(storm.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)
		storm.visible = false
		corona = _make_rect(SolarGas.SHADER)
		corona.visible = false
		flare = _make_rect(FLARE_SHADER)
		flare.visible = false
		edge = _make_rect(EDGE_SHADER)
		edge.visible = false
		hurt = _make_rect("")
		hurt.color = Color(1.0, 0.15, 0.05, 0.0)

		warn_label = Label.new()
		warn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		warn_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		warn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		warn_label.position.y = 90
		warn_label.add_theme_font_override("font", GameFont.get_font())
		warn_label.add_theme_font_size_override("font_size", 34)
		warn_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		warn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		warn_label.add_theme_constant_override("outline_size", 6)
		warn_label.visible = false
		add_child(warn_label)

		toasts = VBoxContainer.new()
		toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
		toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
		toasts.offset_bottom = -70
		toasts.alignment = BoxContainer.ALIGNMENT_END
		add_child(toasts)

		wind = AudioStreamPlayer.new()
		wind.bus = &"Ambient"
		wind.stream = SynthSfx.wind_wav()
		wind.volume_db = -60.0
		add_child(wind)
		sfx = AudioStreamPlayer.new()
		sfx.bus = &"SFX"
		sfx.stream = SynthSfx.flare_wav()
		sfx.volume_db = -3.0
		add_child(sfx)
		beep = AudioStreamPlayer.new()
		beep.bus = &"SFX"
		beep.stream = SynthSfx.beep_wav()
		beep.volume_db = -8.0
		add_child(beep)
		if AudioServer.get_bus_index("SFX") != -1:
			sfx.bus = &"SFX"
			beep.bus = &"SFX"
		GameSettings.quality_changed.connect(_apply_quality)
		_apply_quality()

	func _apply_quality() -> void:
		var cheap := GameSettings.reduced_detail() or GameSettings.mobile_quality()
		(storm.material as ShaderMaterial).set_shader_parameter("cheap_quality", cheap)
		(flare.material as ShaderMaterial).set_shader_parameter("cheap_quality", cheap)
		(corona.material as ShaderMaterial).set_shader_parameter("flat_quality", GameSettings.ultra_enabled())
		(corona.material as ShaderMaterial).set_shader_parameter("noise_octaves", 2 if cheap else 5)

	func _process(delta: float) -> void:
		_t += delta
		if corona.visible:
			(corona.material as ShaderMaterial).set_shader_parameter("time", _t)
		var amount := (_storm_level * 2.2 + _shake) if bool(GameSettings.settings.get("screen_shake", true)) else 0.0
		_shake = maxf(0.0, _shake - delta * 22.0)
		var cam := get_viewport().get_camera_2d()
		if cam != null:
			cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount if amount > 0.05 else Vector2.ZERO
		if storm.visible:
			(storm.material as ShaderMaterial).set_shader_parameter("gust", maxf(0.0, sin(_t * 0.8) * sin(_t * 0.37 + 1.0)))
		if _warn_on:
			var p := 0.5 + 0.5 * sin(_t * 7.0)
			warn_label.modulate.a = 0.55 + 0.45 * p
			(edge.material as ShaderMaterial).set_shader_parameter("pulse", 0.35 + 0.65 * p)
		if hurt.color.a > 0.0:
			hurt.color.a = maxf(0.0, hurt.color.a - delta * 1.6)

	# ---------------- storm
	func start_storm() -> void:
		storm.visible = true
		if _storm_tween != null:
			_storm_tween.kill()
		_storm_tween = create_tween().set_parallel(true)
		_storm_tween.tween_method(func(v: float) -> void:
			_storm_level = v
			(storm.material as ShaderMaterial).set_shader_parameter("intensity", v), _storm_level, 1.0, 2.5)
		wind.play()
		_storm_tween.tween_property(wind, "volume_db", -4.0, 2.5)

	func stop_storm() -> void:
		if _storm_tween != null:
			_storm_tween.kill()
		_storm_tween = create_tween().set_parallel(true)
		_storm_tween.tween_method(func(v: float) -> void:
			_storm_level = v
			(storm.material as ShaderMaterial).set_shader_parameter("intensity", v), _storm_level, 0.0, 3.0)
		_storm_tween.tween_property(wind, "volume_db", -60.0, 3.0)
		_storm_tween.chain().tween_callback(func() -> void:
			storm.visible = false
			wind.stop())

	# ---------------- flare
	func play_flare(shielded: bool) -> void:
		if is_instance_valid(_flare_tween):
			_flare_tween.kill()
		corona.visible = true
		(corona.material as ShaderMaterial).set_shader_parameter("opacity", 0.0)
		var gas := corona.material as ShaderMaterial
		gas.set_shader_parameter("sun_aspect", Vector2.ONE)
		gas.set_shader_parameter("outer_uv", 1.95)
		gas.set_shader_parameter("time", 0.0)
		gas.set_shader_parameter("near_col", Color(1.0, 0.78, 0.32))
		gas.set_shader_parameter("mid_col", Color(1.0, 0.48, 0.12))
		gas.set_shader_parameter("far_col", Color(0.95, 0.28, 0.06))
		_t = 0.0
		_flare_tween = create_tween()
		_flare_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_flare_tween.tween_method(_set_flare_opacity, 0.0, 0.38 if shielded else 0.75, 1.75)
		_flare_tween.tween_interval(1.75)
		_flare_tween.tween_method(_set_flare_opacity, 0.38 if shielded else 0.75, 0.0, 1.75)
		_flare_tween.tween_callback(corona.hide)
		var mat := flare.material as ShaderMaterial
		if shielded:
			mat.set_shader_parameter("strength", 0.35)
			mat.set_shader_parameter("core_col", Color(0.9, 0.95, 1.0))
			mat.set_shader_parameter("mid_col", Color(0.5, 0.65, 1.0))
			mat.set_shader_parameter("edge_col", Color(0.4, 0.3, 0.9))
		else:
			mat.set_shader_parameter("strength", 1.0)
			mat.set_shader_parameter("core_col", Color(1.0, 1.0, 0.98))
			mat.set_shader_parameter("mid_col", Color(1.0, 0.85, 0.40))
			mat.set_shader_parameter("edge_col", Color(1.0, 0.58, 0.15))
		flare.visible = true
		# The hazard owner plays its exported/fallback flare sound once.
		_shake = 5.0 if shielded else 16.0
		if is_instance_valid(_flare_age_tween):
			_flare_age_tween.kill()
		mat.set_shader_parameter("age", 0.0)
		_flare_age_tween = create_tween()
		_flare_age_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("age", v), 0.0, 1.5, 5.25)
		_flare_age_tween.tween_callback(func() -> void:
			mat.set_shader_parameter("age", -1.0)
			flare.visible = false)

	func _set_flare_opacity(value: float) -> void:
		(corona.material as ShaderMaterial).set_shader_parameter("opacity", value)
		(flare.material as ShaderMaterial).set_shader_parameter("opacity", value)

	func show_warning(on: bool) -> void:
		_warn_on = on
		warn_label.visible = on
		edge.visible = on
		_last_beep = -1

	func set_warning(left: float) -> void:
		var s := maxi(0, int(ceil(left)))
		warn_label.text = "SOLAR FLARE IN %d" % s
		if s != _last_beep:
			_last_beep = s
			beep.pitch_scale = 1.0 + (15 - s) * 0.03
			beep.play()

	func hurt_flash() -> void:
		hurt.color.a = 0.45

	func stop_all() -> void:
		if is_instance_valid(_flare_age_tween):
			_flare_age_tween.kill()
		_set_flare_opacity(0.0)
		if is_instance_valid(_flare_tween):
			_flare_tween.kill()
		corona.hide()
		hurt.color.a = 0.0
		for toast_panel in toasts.get_children():
			toast_panel.queue_free()
		show_warning(false)
		if _storm_tween != null:
			_storm_tween.kill()
		_storm_level = 0.0
		_shake = 0.0
		storm.visible = false
		(storm.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)
		flare.visible = false
		(flare.material as ShaderMaterial).set_shader_parameter("age", -1.0)
		wind.stop()
		var cam := get_viewport().get_camera_2d()
		if cam != null:
			cam.offset = Vector2.ZERO

	func toast(msg: String, col: Color) -> void:
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.05, 0.08, 0.92)
		sb.border_color = col
		sb.set_border_width_all(2)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		p.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = msg
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = minf(680.0, get_viewport().get_visible_rect().size.x - 84.0)
		l.add_theme_font_override("font", GameFont.get_font())
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", col)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(l)
		toasts.add_child(p)
		p.modulate.a = 0.0
		var tw := p.create_tween()
		tw.tween_property(p, "modulate:a", 1.0, 0.18)
		tw.tween_interval(4.5)
		tw.tween_property(p, "modulate:a", 0.0, 0.5)
		tw.tween_callback(p.queue_free)
