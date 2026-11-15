extends Node2D

@export_group("Music & Audio")
@export var background_music: AudioStream
@export var music_volume_db: float = -8.0
@export var wind_sfx: AudioStream
@export var wind_volume_db: float = -6.0

@export_group("Transition SFX")
## All optional - leave empty for silence. Played by the shutter / title cards / banners.
@export var shutter_close_sfx: AudioStream     ## blinds slam shut
@export var shutter_open_sfx: AudioStream      ## blinds sweep open
@export var card_slam_sfx: AudioStream         ## title card / banner appears
@export var card_type_sfx: AudioStream         ## subtitle typewriter tick (played per character)
@export var card_out_sfx: AudioStream          ## banner leaves
@export var timer_start_sfx: AudioStream       ## survival timer starts
@export var transition_sfx_volume_db: float = -4.0

@export_group("Days")
@export_file("*.tscn") var win_scene: String = ""
@export var total_days: int = 5
@export var day_length: float = 240.0
@export var debug_mode: bool = false

@onready var build_camera: Camera2D = $BuildCamera
@onready var player: CharacterBody2D = $Player
@onready var rover: Node2D = $Rover

var shop_layer: CanvasLayer
var day_loop: DayLoop
var shop_terminal: MarsGearManifest
var music_player: AudioStreamPlayer

var outside_trigger: Area2D
var outside_mars_area: Area2D
var wind_particles: MarsWindRenderer
var wind_player: AudioStreamPlayer
var mars_bounds_rect: Rect2 = Rect2(-1000, -1000, 2000, 2000)
var is_teleporting: bool = false
var _ignore_outside_trigger: bool = false
var _ignore_mars_trigger: bool = false

class SupplyCrate extends Node2D:
	signal landed
	signal picked_up

	const INTERACT_RADIUS := 85.0
	const GRAVITY := 1050.0
	const BOUNCE_RESTITUTION := 0.54

	var player_ref: CharacterBody2D
	var is_airborne: bool = false
	var is_landed: bool = false
	var is_collected: bool = false
	var player_in_range: bool = false
	var time: float = 0.0

	var z_height: float = 0.0
	var vel_z: float = 0.0
	var vel_xy: Vector2 = Vector2.ZERO
	var box_rot: float = 0.0
	var rot_speed: float = 0.0
	var box_scale: Vector2 = Vector2.ONE
	var bounce_count: int = 0
	var dust_rings: Array[Dictionary] = []

	var pickup_sfx: AudioStreamPlayer
	var thud_sfx: AudioStreamPlayer

	var body_style: StyleBoxFlat
	var lid_style: StyleBoxFlat
	var core_style: StyleBoxFlat
	var tag_style_near: StyleBoxFlat
	var tag_style_far: StyleBoxFlat

	func _ready() -> void:
		z_index = 18
		_init_styles()
		pickup_sfx = AudioStreamPlayer.new()
		pickup_sfx.volume_db = -6.0
		if AudioServer.get_bus_index("SFX") != -1:
			pickup_sfx.bus = &"SFX"
		pickup_sfx.stream = _make_pickup_wav()
		add_child(pickup_sfx)

		thud_sfx = AudioStreamPlayer.new()
		thud_sfx.volume_db = -5.0
		if AudioServer.get_bus_index("SFX") != -1:
			thud_sfx.bus = &"SFX"
		thud_sfx.stream = _make_thud_wav()
		add_child(thud_sfx)

	func _init_styles() -> void:
		body_style = StyleBoxFlat.new()
		body_style.bg_color = Color(0.14, 0.17, 0.22)
		body_style.border_color = Color(0.06, 0.08, 0.11)
		body_style.set_border_width_all(2)
		body_style.set_corner_radius_all(6)

		lid_style = StyleBoxFlat.new()
		lid_style.bg_color = Color(0.24, 0.28, 0.35)
		lid_style.border_color = Color(0.38, 0.44, 0.52)
		lid_style.set_border_width_all(1)
		lid_style.set_corner_radius_all(5)

		core_style = StyleBoxFlat.new()
		core_style.bg_color = Color(0.05, 0.12, 0.18)
		core_style.border_color = Color(0.25, 0.85, 1.0)
		core_style.set_border_width_all(1)
		core_style.set_corner_radius_all(3)

		tag_style_near = StyleBoxFlat.new()
		tag_style_near.bg_color = Color(0.04, 0.10, 0.08, 0.96)
		tag_style_near.border_color = Color(0.42, 1.0, 0.55, 0.95)
		tag_style_near.set_border_width_all(2)
		tag_style_near.set_corner_radius_all(8)

		tag_style_far = StyleBoxFlat.new()
		tag_style_far.bg_color = Color(0.04, 0.08, 0.14, 0.92)
		tag_style_far.border_color = Color(1.0, 0.85, 0.32, 0.85)
		tag_style_far.set_border_width_all(2)
		tag_style_far.set_corner_radius_all(8)

	func launch_from_rover(rover_ground_pos: Vector2, head_height: float, target_pos: Vector2, p: CharacterBody2D) -> void:
		player_ref = p
		global_position = rover_ground_pos
		z_height = -absf(head_height)
		vel_z = -340.0

		var flight_time := 0.72
		vel_xy = (target_pos - rover_ground_pos) / flight_time
		box_rot = -0.45
		rot_speed = 6.5
		box_scale = Vector2(0.55, 1.25)
		bounce_count = 0
		is_airborne = true
		is_landed = false

		await landed

	func _process(delta: float) -> void:
		time += delta

		for i in range(dust_rings.size() - 1, -1, -1):
			var d: Dictionary = dust_rings[i]
			d["age"] += delta
			if d["age"] >= d["life"]:
				dust_rings.remove_at(i)

		if is_airborne:
			_step_bounce_physics(delta)

		box_scale = box_scale.lerp(Vector2.ONE, 1.0 - exp(-18.0 * delta))

		if is_landed and not is_collected and player_ref != null and is_instance_valid(player_ref):
			player_in_range = global_position.distance_to(player_ref.global_position) <= INTERACT_RADIUS
		else:
			player_in_range = false

		queue_redraw()

	func _step_bounce_physics(delta: float) -> void:
		global_position += vel_xy * delta
		vel_z += GRAVITY * delta
		z_height += vel_z * delta
		box_rot += rot_speed * delta

		if z_height < 0.0:
			var air_stretch := clampf(absf(vel_z) / 550.0, 0.0, 0.24)
			box_scale = box_scale.lerp(Vector2(1.0 - air_stretch * 0.5, 1.0 + air_stretch), 0.35)
		else:
			z_height = 0.0
			bounce_count += 1
			var impact_speed := absf(vel_z)

			if impact_speed > 65.0 and bounce_count <= 4:
				vel_z = -impact_speed * BOUNCE_RESTITUTION
				vel_xy *= 0.58
				rot_speed = -rot_speed * 0.42
				box_rot *= 0.5

				var squash := clampf(impact_speed / 420.0, 0.14, 0.42)
				box_scale = Vector2(1.0 + squash, 1.0 - squash * 0.78)
				_spawn_impact_dust(clampf(impact_speed / 360.0, 0.35, 1.0))

				if thud_sfx != null:
					thud_sfx.volume_db = lerpf(-16.0, -3.0, clampf(impact_speed / 420.0, 0.0, 1.0))
					thud_sfx.pitch_scale = randf_range(0.85, 1.05) + float(bounce_count) * 0.12
					thud_sfx.play()
			else:
				z_height = 0.0
				vel_z = 0.0
				vel_xy = Vector2.ZERO
				rot_speed = 0.0
				box_rot = 0.0
				box_scale = Vector2(1.18, 0.85)
				_spawn_impact_dust(0.35)
				is_airborne = false
				is_landed = true
				landed.emit()

	func _spawn_impact_dust(strength: float) -> void:
		for i in range(6):
			var ang := TAU * float(i) / 6.0 + randf_range(-0.3, 0.3)
			dust_rings.append({
				"origin": global_position,
				"dir": Vector2(cos(ang), sin(ang) * 0.65),
				"dist": randf_range(18.0, 34.0) * strength,
				"size": randf_range(5.0, 9.0) * strength,
				"age": 0.0,
				"life": randf_range(0.32, 0.52)
			})

	func _unhandled_input(event: InputEvent) -> void:
		if not is_landed or is_collected or player_ref == null or not is_instance_valid(player_ref):
			return
		if "input_locked" in player_ref and player_ref.input_locked:
			return

		var pressed_e: bool = event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E)
		if pressed_e and global_position.distance_to(player_ref.global_position) <= INTERACT_RADIUS:
			get_viewport().set_input_as_handled()
			_collect()

	func _collect() -> void:
		if is_collected:
			return
		is_collected = true
		GameManager.deliver_pending_supplies()
		if pickup_sfx != null:
			pickup_sfx.play()
		if player_ref.has_method("_flash_hint"):
			player_ref.call("_flash_hint", "Cargo collected! Walk up into the base to start building!", Color(0.42, 1.0, 0.55))
		if player_ref.has_method("_pop"):
			player_ref.call("_pop", -0.18)
		picked_up.emit()

		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "scale", Vector2(1.45, 1.45), 0.22)
		tw.tween_property(self, "modulate:a", 0.0, 0.22)
		await tw.finished
		queue_free()

	func _draw() -> void:
		if body_style == null:
			_init_styles()

		var pulse := 0.5 + 0.5 * sin(time * 5.5)

		for d in dust_rings:
			var t01: float = clampf(d["age"] / d["life"], 0.0, 1.0)
			var ease_out: float = 1.0 - pow(1.0 - t01, 2.5)
			var local_origin: Vector2 = d["origin"] - global_position
			var puff_pos: Vector2 = local_origin + (d["dir"] as Vector2) * (float(d["dist"]) * ease_out) + Vector2(0, 8)
			var rad: float = float(d["size"]) * (0.7 + 0.8 * ease_out)
			draw_circle(puff_pos, rad, Color(0.86, 0.52, 0.34, (1.0 - t01) * 0.55))

		var shadow_scale := clampf(1.0 + z_height / 130.0, 0.32, 1.0)
		draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.28 * shadow_scale * box_scale.x, 0.65 * shadow_scale))
		draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.48 * shadow_scale))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		if is_landed and not is_collected:
			var ring_col := Color(0.42, 1.0, 0.55) if player_in_range else Color(1.0, 0.85, 0.32)
			var ring_r := (42.0 if player_in_range else 34.0) + pulse * 4.0
			draw_circle(Vector2.ZERO, ring_r, Color(ring_col.r, ring_col.g, ring_col.b, 0.08 + 0.05 * pulse))
			for i in range(12):
				if i % 2 == 0:
					var a := TAU * float(i) / 12.0 + time * (1.4 if player_in_range else 0.7)
					draw_arc(Vector2.ZERO, ring_r, a, a + 0.34, 8, Color(ring_col.r, ring_col.g, ring_col.b, 0.65 + 0.35 * pulse), 3.0 if player_in_range else 2.2, true)

		var pivot_pos := Vector2(0, 12.0 + z_height)
		draw_set_transform(pivot_pos, box_rot, box_scale)

		var bumper_col := Color(0.95, 0.68, 0.16)
		var bumper_dark := Color(0.12, 0.14, 0.18)
		for corner in [Vector2(-21, -29), Vector2(13, -29), Vector2(-21, -1), Vector2(13, -1)]:
			draw_rect(Rect2(corner, Vector2(8, 8)), bumper_col)
			draw_rect(Rect2(corner, Vector2(8, 8)), bumper_dark, false, 1.5)

		draw_style_box(body_style, Rect2(-20, -26, 40, 30))
		draw_style_box(lid_style, Rect2(-18, -28, 36, 24))

		draw_rect(Rect2(-15, -25, 30, 4), Color(0.12, 0.15, 0.20))
		for s in range(-12, 14, 6):
			draw_line(Vector2(s, -25), Vector2(s + 3, -21), bumper_col, 2.0)

		draw_rect(Rect2(-18, -16, 4, 6), Color(0.10, 0.12, 0.15))
		draw_rect(Rect2(14, -16, 4, 6), Color(0.10, 0.12, 0.15))
		draw_line(Vector2(-14, -13), Vector2(14, -13), Color(0.10, 0.12, 0.16), 2.0)

		draw_style_box(core_style, Rect2(-9, -18, 18, 10))
		var glow_col := Color(0.35, 0.92, 1.0, 0.65 + 0.35 * pulse)
		draw_rect(Rect2(-6, -15, 12, 4), glow_col)

		var led_col := Color(0.42, 1.0, 0.55) if pulse > 0.3 else Color(0.2, 0.55, 0.35)
		draw_circle(Vector2(-13, -8), 1.8, led_col)
		draw_circle(Vector2(13, -8), 1.8, led_col)

		draw_rect(Rect2(-8, -2, 16, 4), Color(0.32, 0.37, 0.45))
		draw_rect(Rect2(-6, -1, 12, 2), bumper_col)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		if is_landed and not is_collected:
			var f := ThemeDB.fallback_font
			var msg := "PRESS [ E ] TO GRAB CARGO" if player_in_range else "WALK HERE (WASD)"
			var font_sz := 16 if player_in_range else 14
			var w := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
			var tag_y := -38.0 + z_height - pulse * 4.0
			var tag_rect := Rect2(-w * 0.5 - 12.0, tag_y - 18.0, w + 24.0, 26.0)
			draw_style_box(tag_style_near if player_in_range else tag_style_far, tag_rect)
			var txt_col := Color(0.42, 1.0, 0.55) if player_in_range else Color(1.0, 0.85, 0.32)
			draw_string(f, Vector2(-w * 0.5, tag_y), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, txt_col)

	func _make_thud_wav() -> AudioStreamWAV:
		var rate := 22050
		var samples := int(rate * 0.12)
		var data := PackedByteArray()
		data.resize(samples * 2)
		var lp := 0.0
		for i in range(samples):
			var t := float(i) / float(rate)
			var env := exp(-t * 36.0)
			var body_boom := sin(t * TAU * lerpf(145.0, 48.0, clampf(t / 0.09, 0.0, 1.0))) * 0.75
			var clank := sin(t * TAU * 380.0) * exp(-t * 75.0) * 0.25
			lp += 0.25 * (randf_range(-0.4, 0.4) - lp)
			var s := (body_boom + clank + lp) * env
			var pcm := int(clampf(s, -1.0, 1.0) * 32767.0)
			data[i * 2] = pcm & 0xFF
			data[i * 2 + 1] = (pcm >> 8) & 0xFF
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.data = data
		return wav

	func _make_pickup_wav() -> AudioStreamWAV:
		var rate := 22050
		var samples := int(rate * 0.16)
		var data := PackedByteArray()
		data.resize(samples * 2)
		for i in range(samples):
			var t := float(i) / float(rate)
			var freq := 520.0 if t < 0.08 else 780.0
			var env := exp(-fmod(t, 0.08) * 32.0)
			var s := sin(t * TAU * freq) * env * 0.75
			var pcm := int(clampf(s, -1.0, 1.0) * 32767.0)
			data[i * 2] = pcm & 0xFF
			data[i * 2 + 1] = (pcm >> 8) & 0xFF
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.data = data
		return wav

class MarsGearManifest extends Control:
	signal deploy_confirmed

	var font: SystemFont
	var header_size: int = 32
	var font_size: int = 24
	var body_size: int = 20
	var row_height: float = 72.0
	var padding: float = 52.0

	var time: float = 0.0
	var float_amp_y: float = 2.0
	var float_amp_x: float = 1.0
	var float_speed_y: float = 0.14
	var float_speed_x: float = 0.10
	var float_phase_offset: float = 0.6

	var bg_color := Color(0.012, 0.016, 0.032, 0.98)
	var text_color := Color(0.90, 0.94, 0.98)
	var soft_mint := Color(0.42, 1.0, 0.65)
	var soft_sky := Color(0.48, 0.82, 1.0)
	var soft_amber := Color(1.0, 0.80, 0.35)
	var muted_text := Color(0.40, 0.45, 0.55)

	var selected_index: int = 0
	var focus_on_bottom: bool = false
	var selected_bottom_index: int = 0
	var bottom_actions: Array[String] = ["[ CONFIRM DELIVERY ]", "[ CLEAR MANIFEST ]"]

	var item_rects: Array[Rect2] = []
	var minus_rects: Array[Rect2] = []
	var plus_rects: Array[Rect2] = []
	var bottom_rects: Array[Rect2] = []

	var bg_layer: ColorRect
	var glow_layer: ColorRect
	var glow_positions: Array[Vector2] = []
	var sfx_player: AudioStreamPlayer
	var is_closing: bool = false

	var card_idle_style: StyleBoxFlat
	var card_sel_style: StyleBoxFlat
	var info_card_style: StyleBoxFlat
	var pill_btn_style: StyleBoxFlat
	var primary_btn_style: StyleBoxFlat
	var primary_btn_sel_style: StyleBoxFlat
	var secondary_btn_style: StyleBoxFlat
	var secondary_btn_sel_style: StyleBoxFlat
	var bar_bg_style: StyleBoxFlat
	var bar_fill_style: StyleBoxFlat
	var badge_style: StyleBoxFlat

	const SHOP_SHADER := """
shader_type canvas_item;
uniform int glow_count = 0;
uniform vec2 glow_positions[32];
uniform vec4 base_glow_color : source_color = vec4(0.01, 0.03, 0.08, 1.0);
uniform vec4 ring_color : source_color = vec4(0.03, 0.12, 0.25, 1.0);
uniform float bleed = 22.0;
uniform float ring_speed = 0.03;
uniform float inv_aspect = 1.0;
uniform float glow_strength = 0.18;
uniform float time = 0.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.02 + vec2(2.1, 7.4);
		a *= 0.5;
	}
	return v;
}

vec3 star_layer(vec2 sp, float scale, float density, float size, float seed) {
	vec2 g = sp * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash21(id + seed);
	if (h < density) { return vec3(0.0); }
	float k = (h - density) / (1.0 - density);
	vec2 off = (vec2(hash21(id + seed + 3.1), hash21(id + seed + 7.7)) - 0.5) * 0.6;
	vec2 d = f - off;
	float r = length(d);
	float tw = 0.65 + 0.35 * sin(time * (1.1 + k * 2.5) + k * 40.0);
	float core = smoothstep(size, 0.0, r) * tw;
	float halo = smoothstep(size * 3.8, 0.0, r) * 0.08;
	vec3 tint = mix(vec3(0.65, 0.85, 1.0), vec3(1.0, 0.94, 0.86), hash21(id + seed + 9.1));
	return tint * (core * (0.65 + 1.1 * k) + halo);
}

void fragment() {
	vec2 aspect_uv = vec2(UV.x / max(inv_aspect, 0.001), UV.y);
	float n1 = fbm(aspect_uv * 1.4 + vec2(time * 0.004, -time * 0.003));
	vec3 col = mix(vec3(0.008, 0.011, 0.024), vec3(0.016, 0.026, 0.052), n1);

	vec3 ripple = vec3(0.0);
	for (int i = 0; i < glow_count; i++) {
		vec2 diff = UV - glow_positions[i];
		diff.x *= inv_aspect;
		float dist = length(diff);
		ripple += base_glow_color.rgb * exp(-dist * 8.0) * 0.18;

		float t = fract(time * ring_speed + float(i) * 0.3);
		float radius = t * 0.38 + 0.08;
		ripple += ring_color.rgb * exp(-abs(dist - radius) * bleed) * 0.05 * sin(t * PI);
	}

	ripple = min(ripple * glow_strength, vec3(0.06, 0.09, 0.14));

	vec3 stars = vec3(0.0);
	stars += star_layer(aspect_uv + vec2(time * 0.002, 0.0), 48.0, 0.962, 0.08, 2.0);
	stars += star_layer(aspect_uv + vec2(-time * 0.003, time * 0.001), 95.0, 0.974, 0.065, 19.4) * 0.65;

	col += ripple + stars;

	float vig = smoothstep(1.0, 0.25, length((UV - 0.5) * vec2(1.1, 1.0)));
	col *= mix(0.55, 1.0, vig);

	COLOR = vec4(col, 1.0);
}
"""

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL

		font = SystemFont.new()
		font.font_names = PackedStringArray(["Courier New", "monospace"])
		_init_styles()

		bg_layer = ColorRect.new()
		bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_layer.color = bg_color
		bg_layer.z_index = -3
		add_child(bg_layer)

		glow_layer = ColorRect.new()
		glow_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow_layer.color = Color.TRANSPARENT
		glow_layer.z_index = -1
		var sh := Shader.new()
		sh.code = SHOP_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		glow_layer.material = mat
		add_child(glow_layer)

		sfx_player = AudioStreamPlayer.new()
		sfx_player.volume_db = -10.0
		sfx_player.stream = _make_beep_wav()
		add_child(sfx_player)

		get_viewport().size_changed.connect(_on_resized)
		_on_resized()

	func _init_styles() -> void:
		card_idle_style = StyleBoxFlat.new()
		card_idle_style.bg_color = Color(0.04, 0.06, 0.10, 0.80)
		card_idle_style.border_color = Color(0.20, 0.30, 0.45, 0.40)
		card_idle_style.set_border_width_all(1)
		card_idle_style.set_corner_radius_all(4)
		card_idle_style.set_content_margin_all(0)

		card_sel_style = StyleBoxFlat.new()
		card_sel_style.bg_color = Color(0.08, 0.14, 0.22, 0.95)
		card_sel_style.border_color = soft_mint
		card_sel_style.set_border_width_all(2)
		card_sel_style.set_corner_radius_all(4)
		card_sel_style.shadow_color = Color(0.42, 1.0, 0.65, 0.15)
		card_sel_style.shadow_size = 8

		info_card_style = StyleBoxFlat.new()
		info_card_style.bg_color = Color(0.03, 0.05, 0.09, 0.90)
		info_card_style.border_color = Color(0.25, 0.45, 0.65, 0.40)
		info_card_style.set_border_width_all(1)
		info_card_style.set_corner_radius_all(6)
		info_card_style.shadow_color = Color(0, 0, 0, 0.40)
		info_card_style.shadow_size = 12

		pill_btn_style = StyleBoxFlat.new()
		pill_btn_style.bg_color = Color(0.10, 0.15, 0.22, 0.90)
		pill_btn_style.border_color = Color(0.30, 0.42, 0.55, 0.60)
		pill_btn_style.set_border_width_all(1)
		pill_btn_style.set_corner_radius_all(4)

		primary_btn_style = StyleBoxFlat.new()
		primary_btn_style.bg_color = Color(0.08, 0.18, 0.14, 0.90)
		primary_btn_style.border_color = Color(0.30, 0.70, 0.50, 0.60)
		primary_btn_style.set_border_width_all(1)
		primary_btn_style.set_corner_radius_all(6)

		primary_btn_sel_style = StyleBoxFlat.new()
		primary_btn_sel_style.bg_color = Color(0.12, 0.32, 0.22, 0.98)
		primary_btn_sel_style.border_color = soft_mint
		primary_btn_sel_style.set_border_width_all(2)
		primary_btn_sel_style.set_corner_radius_all(6)
		primary_btn_sel_style.shadow_color = Color(0.42, 1.0, 0.65, 0.20)
		primary_btn_sel_style.shadow_size = 10

		secondary_btn_style = StyleBoxFlat.new()
		secondary_btn_style.bg_color = Color(0.06, 0.08, 0.12, 0.80)
		secondary_btn_style.border_color = Color(0.25, 0.30, 0.40, 0.50)
		secondary_btn_style.set_border_width_all(1)
		secondary_btn_style.set_corner_radius_all(6)

		secondary_btn_sel_style = StyleBoxFlat.new()
		secondary_btn_sel_style.bg_color = Color(0.14, 0.16, 0.22, 0.95)
		secondary_btn_sel_style.border_color = soft_amber
		secondary_btn_sel_style.set_border_width_all(2)
		secondary_btn_sel_style.set_corner_radius_all(6)

		bar_bg_style = StyleBoxFlat.new()
		bar_bg_style.bg_color = Color(0.06, 0.08, 0.12, 0.90)
		bar_bg_style.border_color = Color(0.20, 0.25, 0.35, 0.50)
		bar_bg_style.set_border_width_all(1)
		bar_bg_style.set_corner_radius_all(4)

		bar_fill_style = StyleBoxFlat.new()
		bar_fill_style.bg_color = soft_mint
		bar_fill_style.set_corner_radius_all(4)

		badge_style = StyleBoxFlat.new()
		badge_style.bg_color = Color(0.08, 0.12, 0.18, 0.90)
		badge_style.border_color = Color(0.20, 0.30, 0.40, 0.50)
		badge_style.set_border_width_all(1)
		badge_style.set_corner_radius_all(4)

	func _on_resized() -> void:
		var vs := get_viewport_rect().size
		var base := minf(vs.x, vs.y)
		header_size = clampi(int(base * 0.038), 24, 32)
		font_size = clampi(int(base * 0.030), 20, 26)
		body_size = clampi(int(base * 0.026), 16, 22)
		row_height = clampf(base * 0.09, 60.0, 76.0)
		padding = clampf(base * 0.05, 32.0, 56.0)
		queue_redraw()

	func _process(delta: float) -> void:
		time += delta
		if glow_layer != null:
			(glow_layer.material as ShaderMaterial).set_shader_parameter("time", time)
		queue_redraw()

	func _compute_float(phase: float) -> Vector2:
		var y_off := sin(time * float_speed_y * TAU + phase) * float_amp_y
		var x_off := cos(time * float_speed_x * TAU + phase * 0.8) * float_amp_x
		return Vector2(x_off, y_off)

	func _get_display_name(item: Dictionary) -> String:
		return str(item.get("title", item["id"])).to_upper()

	func _draw() -> void:
		if card_idle_style == null:
			_init_styles()

		glow_positions.clear()
		item_rects.clear()
		minus_rects.clear()
		plus_rects.clear()
		bottom_rects.clear()

		var vs := size
		var top_y := padding
		var hdr_off := _compute_float(0.0)

		var title_str := "[ ROVER SUPPLY REQUEST - SOL %d ]" % GameManager.current_sol
		draw_string(font, Vector2(padding, top_y + font.get_ascent(header_size)) + hdr_off, title_str, HORIZONTAL_ALIGNMENT_LEFT, -1, header_size, text_color)

		var max_mass: float = GameManager.budget_for_day(GameManager.current_sol)
		var ratio: float = clampf(GameManager.mass_budget / max_mass, 0.0, 1.0)
		var weight_txt := "MASS BUDGET: %d / %d KG" % [int(GameManager.mass_budget), int(max_mass)]
		var wt_w := font.get_string_size(weight_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x
		
		var bar_w := 200.0
		var bar_h := 16.0
		var bar_x := vs.x - padding - bar_w
		var bar_y := top_y + 12.0 + hdr_off.y

		draw_string(font, Vector2(bar_x - wt_w - 20.0, top_y + font.get_ascent(body_size) + 4.0 + hdr_off.y), weight_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, soft_amber)
		draw_style_box(bar_bg_style, Rect2(bar_x, bar_y, bar_w, bar_h))
		
		if ratio > 0.01:
			bar_fill_style.bg_color = soft_mint if ratio > 0.25 else soft_amber
			draw_style_box(bar_fill_style, Rect2(bar_x, bar_y, maxf(16.0, bar_w * ratio), bar_h))

		var content_top := top_y + header_size + 40.0
		var content_bottom := vs.y - padding - 76.0
		var left_x := padding
		var left_w := vs.x * 0.40 - padding
		var right_x := vs.x * 0.43
		var right_w := vs.x - right_x - padding

		var card_y := content_top + 8.0
		for i in range(GameManager.catalog.size()):
			var item: Dictionary = GameManager.catalog[i]
			var item_id: String = item["id"]
			var display_name: String = _get_display_name(item)
			var qty: int = GameManager.get_item_count(item_id)
			var is_sel: bool = (not focus_on_bottom and i == selected_index)
			var can_afford: bool = GameManager.mass_budget >= float(item["mass"])
			var f_off := _compute_float(float(i + 1) * float_phase_offset)

			var card_rect := Rect2(Vector2(left_x, card_y) + f_off, Vector2(left_w, row_height))
			draw_style_box(card_sel_style if is_sel else card_idle_style, card_rect)

			var name_col := soft_mint if is_sel else (text_color if can_afford or qty > 0 else muted_text)
			var text_y := card_rect.position.y + (row_height + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			draw_string(font, Vector2(card_rect.position.x + 24.0, text_y), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, name_col)

			var btn_sz := 34.0
			var btn_y := card_rect.position.y + (row_height - btn_sz) * 0.5
			var plus_rect := Rect2(card_rect.end.x - 20.0 - btn_sz, btn_y, btn_sz, btn_sz)
			var minus_rect := Rect2(plus_rect.position.x - 50.0 - btn_sz, btn_y, btn_sz, btn_sz)

			draw_style_box(pill_btn_style, minus_rect)
			draw_style_box(pill_btn_style, plus_rect)

			var sym_y := btn_y + (btn_sz + font.get_ascent(body_size) - font.get_descent(body_size)) * 0.5
			var minus_w := font.get_string_size("-", HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x
			var plus_w := font.get_string_size("+", HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x
			
			draw_string(font, Vector2(minus_rect.get_center().x - minus_w * 0.5, sym_y), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, text_color if qty > 0 else muted_text)
			draw_string(font, Vector2(plus_rect.get_center().x - plus_w * 0.5, sym_y), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, text_color if can_afford else muted_text)

			var qty_str := "x%d" % qty
			var qty_w := font.get_string_size(qty_str, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x
			var qty_center_x := (minus_rect.end.x + plus_rect.position.x) * 0.5
			var qty_col := soft_amber if qty > 0 else muted_text
			draw_string(font, Vector2(qty_center_x - qty_w * 0.5, text_y), qty_str, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, qty_col)

			if is_sel:
				glow_positions.append(card_rect.get_center())

			item_rects.append(card_rect)
			minus_rects.append(minus_rect.grow(6.0))
			plus_rects.append(plus_rect.grow(6.0))

			card_y += row_height + 16.0

		var info_rect := Rect2(right_x, content_top, right_w, content_bottom - content_top)
		_draw_info_card(info_rect)
		_draw_bottom_bar(vs)
		_update_glow_shader()

	func _draw_info_card(rect: Rect2) -> void:
		if GameManager.catalog.is_empty():
			return
		var idx := clampi(selected_index, 0, GameManager.catalog.size() - 1)
		var item: Dictionary = GameManager.catalog[idx]
		var display_name: String = _get_display_name(item)
		var f_off := _compute_float((idx + 3) * float_phase_offset) * 0.6

		var card_rect := Rect2(rect.position + f_off, rect.size)
		draw_style_box(info_card_style, card_rect)

		var pad := 32.0
		var tx := card_rect.position.x + pad
		var ty := card_rect.position.y + pad + font.get_ascent(header_size)

		var icon_rad := 16.0
		var icon_center := Vector2(card_rect.end.x - pad - icon_rad, card_rect.position.y + pad + icon_rad)
		draw_circle(icon_center, icon_rad * 1.5, Color(0.48, 0.82, 0.98, 0.08))
		var num_pts := 6 if idx == 0 else 5
		var pts := PackedVector2Array()
		for p_i in range(num_pts):
			var ang := time * 0.4 + p_i * TAU / float(num_pts)
			pts.append(icon_center + Vector2(cos(ang), sin(ang)) * icon_rad)
		for p_i in range(num_pts):
			draw_line(pts[p_i], pts[(p_i + 1) % num_pts], soft_mint, 1.5, true)
			draw_circle(pts[p_i], 2.5, soft_sky)
		glow_positions.append(icon_center)

		draw_string(font, Vector2(tx, ty), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, header_size, soft_mint)

		ty += 28.0
		var badge_1 := "%d KG" % int(item["mass"])
		var badge_2 := "%d KW" % int(item["power"])
		var b1_w := font.get_string_size(badge_1, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x + 20.0
		var b2_w := font.get_string_size(badge_2, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x + 20.0
		var badge_h := float(body_size) + 12.0

		var b1_rect := Rect2(tx, ty, b1_w, badge_h)
		var b2_rect := Rect2(tx + b1_w + 12.0, ty, b2_w, badge_h)
		draw_style_box(badge_style, b1_rect)
		draw_style_box(badge_style, b2_rect)

		var b_text_y := ty + (badge_h + font.get_ascent(body_size) - font.get_descent(body_size)) * 0.5
		draw_string(font, Vector2(tx + 10.0, b_text_y), badge_1, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, soft_amber)
		draw_string(font, Vector2(b2_rect.position.x + 10.0, b_text_y), badge_2, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, soft_sky)

		ty += badge_h + 32.0
		var wrapped := _wrap_line(str(item["desc"]), card_rect.size.x - pad * 2.0, body_size)
		for line in wrapped:
			if ty > card_rect.end.y - pad:
				break
			if line == "":
				ty += body_size * 0.8
				continue
			
			var is_heading := line.begins_with("WHAT IT DOES") or line.begins_with("NASA FACT")
			var line_col := soft_sky if is_heading else text_color
			var current_size := body_size if is_heading else int(body_size * 0.9)
			
			draw_string(font, Vector2(tx, ty), line, HORIZONTAL_ALIGNMENT_LEFT, -1, current_size, line_col)
			ty += current_size * 1.5

	func _wrap_line(text: String, max_w: float, f_size: int) -> Array[String]:
		var out: Array[String] = []
		for paragraph in text.split("\n"):
			if paragraph.strip_edges() == "":
				out.append("")
				continue
			var words := paragraph.split(" ", false)
			var cur := ""
			for w in words:
				var test := cur + (" " if cur != "" else "") + w
				if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size).x > max_w and cur != "":
					out.append(cur)
					cur = w
				else:
					cur = test
			if cur != "":
				out.append(cur)
		return out

	func _draw_bottom_bar(vs: Vector2) -> void:
		var btn_h := 50.0
		var bottom_y := vs.y - padding - btn_h + 8.0
		var x := padding

		for i in range(bottom_actions.size()):
			var is_sel := focus_on_bottom and i == selected_bottom_index
			var label: String = bottom_actions[i]
			var f_off := _compute_float(float(i + 6) * float_phase_offset) * 0.5
			var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var btn_w := text_w + 56.0
			var btn_rect := Rect2(Vector2(x, bottom_y) + f_off, Vector2(btn_w, btn_h))

			if i == 0:
				draw_style_box(primary_btn_sel_style if is_sel else primary_btn_style, btn_rect)
			else:
				draw_style_box(secondary_btn_sel_style if is_sel else secondary_btn_style, btn_rect)

			var txt_col := soft_mint if i == 0 else (soft_amber if is_sel else muted_text)
			if i == 0 and is_sel:
				txt_col = Color.WHITE
			
			var text_y := btn_rect.position.y + (btn_h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			draw_string(font, Vector2(btn_rect.position.x + 28.0, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, txt_col)

			bottom_rects.append(btn_rect)
			x += btn_w + 20.0

	func _update_glow_shader() -> void:
		if glow_layer == null:
			return
		var mat := glow_layer.material as ShaderMaterial
		var vs := get_viewport_rect().size
		var count := mini(glow_positions.size(), 32)
		mat.set_shader_parameter("glow_count", count)
		var arr := []
		for i in range(count):
			arr.append(Vector2(glow_positions[i].x / maxf(vs.x, 1.0), glow_positions[i].y / maxf(vs.y, 1.0)))
		for i in range(count, 32):
			arr.append(Vector2.ZERO)
		mat.set_shader_parameter("glow_positions", arr)
		mat.set_shader_parameter("inv_aspect", vs.y / maxf(vs.x, 1.0))

	func _input(event: InputEvent) -> void:
		if not visible or is_closing:
			return

		if event is InputEventMouseMotion:
			var m_pos: Vector2 = event.position
			for i in range(item_rects.size()):
				if item_rects[i].has_point(m_pos):
					if focus_on_bottom or selected_index != i:
						focus_on_bottom = false
						selected_index = i
						_beep(1.1)
					return
			for i in range(bottom_rects.size()):
				if bottom_rects[i].has_point(m_pos):
					if not focus_on_bottom or selected_bottom_index != i:
						focus_on_bottom = true
						selected_bottom_index = i
						_beep(1.1)
					return

		elif event is InputEventMouseButton and event.pressed:
			var m_pos: Vector2 = event.position
			if event.button_index == MOUSE_BUTTON_LEFT:
				for i in range(plus_rects.size()):
					if plus_rects[i].has_point(m_pos):
						selected_index = i
						focus_on_bottom = false
						_adjust_item(i, 1)
						get_viewport().set_input_as_handled()
						return
				for i in range(minus_rects.size()):
					if minus_rects[i].has_point(m_pos):
						selected_index = i
						focus_on_bottom = false
						_adjust_item(i, -1)
						get_viewport().set_input_as_handled()
						return
				for i in range(item_rects.size()):
					if item_rects[i].has_point(m_pos):
						selected_index = i
						focus_on_bottom = false
						_adjust_item(i, 1)
						get_viewport().set_input_as_handled()
						return
				for i in range(bottom_rects.size()):
					if bottom_rects[i].has_point(m_pos):
						focus_on_bottom = true
						selected_bottom_index = i
						_execute_bottom(i)
						get_viewport().set_input_as_handled()
						return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				for i in range(item_rects.size()):
					if item_rects[i].has_point(m_pos):
						selected_index = i
						focus_on_bottom = false
						_adjust_item(i, -1)
						get_viewport().set_input_as_handled()
						return

		elif event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_UP, KEY_W:
					if focus_on_bottom:
						focus_on_bottom = false
						selected_index = maxi(0, GameManager.catalog.size() - 1)
					else:
						selected_index = (selected_index - 1 + GameManager.catalog.size()) % GameManager.catalog.size()
					_beep(1.05)
					get_viewport().set_input_as_handled()
				KEY_DOWN, KEY_S:
					if focus_on_bottom:
						selected_bottom_index = (selected_bottom_index + 1) % bottom_actions.size()
					else:
						if selected_index < GameManager.catalog.size() - 1:
							selected_index += 1
						else:
							focus_on_bottom = true
							selected_bottom_index = 0
					_beep(1.05)
					get_viewport().set_input_as_handled()
				KEY_LEFT, KEY_A, KEY_MINUS:
					if focus_on_bottom:
						selected_bottom_index = (selected_bottom_index - 1 + bottom_actions.size()) % bottom_actions.size()
						_beep(1.05)
					else:
						_adjust_item(selected_index, -1)
					get_viewport().set_input_as_handled()
				KEY_RIGHT, KEY_D, KEY_EQUAL, KEY_PLUS:
					if focus_on_bottom:
						selected_bottom_index = (selected_bottom_index + 1) % bottom_actions.size()
						_beep(1.05)
					else:
						_adjust_item(selected_index, 1)
					get_viewport().set_input_as_handled()
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					if focus_on_bottom:
						_execute_bottom(selected_bottom_index)
					else:
						_adjust_item(selected_index, 1)
					get_viewport().set_input_as_handled()

	func _adjust_item(idx: int, dir: int) -> void:
		if idx < 0 or idx >= GameManager.catalog.size():
			return
		var item: Dictionary = GameManager.catalog[idx]
		var cost: float = float(item["mass"])
		var id: String = item["id"]
		if dir > 0:
			if GameManager.mass_budget >= cost:
				GameManager.mass_budget -= cost
				GameManager.add_to_inventory(id)
				_beep(1.35)
			else:
				_beep(0.6)
		else:
			if GameManager.remove_from_inventory(id):
				GameManager.mass_budget += cost
				_beep(0.9)
			else:
				_beep(0.6)

	func _execute_bottom(idx: int) -> void:
		if idx == 0:
			is_closing = true
			_beep(1.5)
			deploy_confirmed.emit()
		elif idx == 1:
			for item in GameManager.catalog:
				var id: String = item["id"]
				while GameManager.remove_from_inventory(id):
					GameManager.mass_budget += float(item["mass"])
			_beep(0.8)

	func _beep(pitch: float) -> void:
		if sfx_player != null:
			sfx_player.pitch_scale = pitch
			sfx_player.play()

	func _make_beep_wav() -> AudioStreamWAV:
		var rate := 22050
		var samples := int(rate * 0.035)
		var data := PackedByteArray()
		data.resize(samples * 2)
		for i in range(samples):
			var t := float(i) / float(rate)
			var env := exp(-t * 110.0)
			var s := (sin(t * TAU * 1180.0) * 0.7 + sin(t * TAU * 2360.0) * 0.3) * env
			var pcm := int(clampf(s, -1.0, 1.0) * 32767.0)
			data[i * 2] = pcm & 0xFF
			data[i * 2 + 1] = (pcm >> 8) & 0xFF
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.data = data
		return wav

class MarsWindRenderer extends Node2D:
	var particles: Array[Dictionary] = []
	var time: float = 0.0
	var active: bool = false
	var alpha_fade: float = 0.0
	var bounds: Rect2 = Rect2(-1000, -1000, 2000, 2000)

	func setup(area_bounds: Rect2) -> void:
		bounds = area_bounds
		z_index = 40
		particles.clear()
		for i in range(260):
			particles.append({
				"pos": Vector2(
					randf_range(bounds.position.x, bounds.end.x),
					randf_range(bounds.position.y, bounds.end.y)
				),
				"speed": randf_range(160.0, 340.0),
				"drift": randf_range(-25.0, 25.0),
				"size": randf_range(1.4, 3.4),
				"len": randf_range(14.0, 38.0),
				"alpha": randf_range(0.14, 0.38),
				"phase": randf() * TAU
			})

	func _process(delta: float) -> void:
		var target_a: float = 1.0 if active else 0.0
		alpha_fade = move_toward(alpha_fade, target_a, delta * 1.5)
		if alpha_fade <= 0.001:
			return

		time += delta
		for p in particles:
			var pos: Vector2 = p["pos"]
			var gust: float = 1.0 + 0.3 * sin(time * 1.4 + p["phase"])
			pos.x += p["speed"] * gust * delta
			pos.y += (p["drift"] + sin(time * 2.2 + p["phase"]) * 18.0) * delta

			if pos.x > bounds.end.x + 50.0:
				pos.x = bounds.position.x - 50.0
				pos.y = randf_range(bounds.position.y, bounds.end.y)
			if pos.y > bounds.end.y + 30.0:
				pos.y = bounds.position.y - 30.0
			elif pos.y < bounds.position.y - 30.0:
				pos.y = bounds.end.y + 30.0
			p["pos"] = pos
		queue_redraw()

	func _draw() -> void:
		if alpha_fade <= 0.001:
			return
		for p in particles:
			var pos: Vector2 = p["pos"]
			var a: float = p["alpha"] * alpha_fade
			var streak_col := Color(0.88, 0.52, 0.34, a * 0.65)
			var grain_col := Color(0.95, 0.64, 0.44, a)
			draw_line(pos - Vector2(p["len"], 0.0), pos, streak_col, p["size"] * 0.7, true)
			draw_circle(pos, p["size"], grain_col)

func _apply_transition_sfx() -> void:
	day_loop.sfx_volume_db = transition_sfx_volume_db
	day_loop.sfx_card_slam = card_slam_sfx
	day_loop.sfx_type = card_type_sfx
	day_loop.sfx_card_out = card_out_sfx
	day_loop.sfx_timer_start = timer_start_sfx
	var tm = get_node_or_null("/root/Transition")
	if tm != null and "sfx_close" in tm:
		tm.sfx_volume_db = transition_sfx_volume_db
		tm.sfx_close = shutter_close_sfx
		tm.sfx_open = shutter_open_sfx

func _ready() -> void:
	GameManager.total_days = total_days
	GameManager.day_length = day_length
	day_loop = DayLoop.new()
	day_loop.win_scene = win_scene
	day_loop.debug_mode = debug_mode
	_apply_transition_sfx()
	add_child(day_loop)
	GameManager.current_phase = GameManager.Phase.BUILD
	build_camera.enabled = true
	if rover != null:
		rover.visible = false
	_setup_background_music()
	_setup_mars_zones_and_walls()
	_setup_wind_effects()
	await day_loop.play_intro()
	_build_shop_ui()
	await day_loop.reveal()

func _setup_background_music() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "BackgroundMusicPlayer"
	music_player.volume_db = music_volume_db
	if AudioServer.get_bus_index("Music") != -1:
		music_player.bus = &"Music"

	if background_music != null:
		var st := background_music.duplicate()
		if "loop" in st:
			st.loop = true
		elif st is AudioStreamWAV:
			(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		music_player.stream = st
	else:
		music_player.stream = _generate_space_music_loop_wav()

	music_player.finished.connect(func():
		if is_instance_valid(music_player):
			music_player.play()
	)
	add_child(music_player)
	music_player.play()

func _generate_space_music_loop_wav() -> AudioStreamWAV:
	var mix_rate: int = 22050
	var duration: float = 8.0
	var samples: int = int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var freqs := [110.0, 164.81, 220.0, 261.63, 329.63]
	for i in range(samples):
		var t: float = float(i) / float(mix_rate)
		var pad: float = 0.0
		for f_idx in range(freqs.size()):
			var f: float = freqs[f_idx]
			var lfo: float = 0.65 + 0.35 * sin(t * TAU * 0.25 + float(f_idx) * 1.3)
			pad += sin(t * TAU * f) * lfo * (0.22 / float(f_idx + 1))
		var pulse_arp: float = sin(t * TAU * (440.0 if int(t * 2.0) % 2 == 0 else 329.63)) * exp(-fmod(t * 2.0, 1.0) * 6.5) * 0.12
		var sample: float = clampf(pad + pulse_arp, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples
	wav.stereo = false
	wav.data = data
	return wav

func _build_shop_ui() -> void:
	shop_layer = CanvasLayer.new()
	shop_layer.layer = 10
	add_child(shop_layer)

	shop_terminal = MarsGearManifest.new()
	shop_terminal.deploy_confirmed.connect(_on_confirm_delivery)
	shop_layer.add_child(shop_terminal)

func _on_confirm_delivery() -> void:
	_start_rover_transition()

func _setup_mars_zones_and_walls() -> void:
	outside_trigger = get_node_or_null("outside") as Area2D
	if outside_trigger == null:
		outside_trigger = find_child("outside", true, false) as Area2D

	outside_mars_area = get_node_or_null("outside_mars") as Area2D
	if outside_mars_area == null:
		outside_mars_area = find_child("outside_mars", true, false) as Area2D

	if outside_trigger != null:
		outside_trigger.body_entered.connect(_on_outside_trigger_entered)
		outside_trigger.body_exited.connect(_on_outside_trigger_exited)

	if outside_mars_area != null:
		outside_mars_area.body_entered.connect(_on_outside_mars_entered)
		outside_mars_area.body_exited.connect(_on_outside_mars_exited)
		mars_bounds_rect = _calculate_mars_bounds(outside_mars_area, 1000.0)
		_create_invisible_walls(mars_bounds_rect)

func _get_area_global_rect(area: Area2D) -> Rect2:
	var col_shape: CollisionShape2D = area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col_shape != null and col_shape.shape != null:
		var shape_rect: Rect2 = col_shape.shape.get_rect()
		var global_center: Vector2 = col_shape.global_position
		var g_scale: Vector2 = col_shape.global_scale.abs()
		var scaled_size: Vector2 = shape_rect.size * g_scale
		return Rect2(global_center - scaled_size * 0.5, scaled_size)
	return Rect2(area.global_position - Vector2(64, 64), Vector2(128, 128))

func _calculate_mars_bounds(area: Area2D, margin: float) -> Rect2:
	var raw_rect: Rect2 = _get_area_global_rect(area)
	var top_left := Vector2(raw_rect.position.x - margin, raw_rect.position.y)
	var total_size := Vector2(raw_rect.size.x + margin * 2.0, raw_rect.size.y + margin)
	return Rect2(top_left, total_size)

func _create_invisible_walls(bounds: Rect2) -> void:
	var wall_body := StaticBody2D.new()
	wall_body.name = "MarsInvisibleWalls"
	wall_body.collision_layer = 1
	wall_body.collision_mask = 1
	add_child(wall_body)

	var thickness: float = 64.0
	var walls_data: Array[Rect2] = [
		Rect2(bounds.position.x - thickness, bounds.position.y - thickness, bounds.size.x + thickness * 2.0, thickness),
		Rect2(bounds.position.x - thickness, bounds.end.y, bounds.size.x + thickness * 2.0, thickness),
		Rect2(bounds.position.x - thickness, bounds.position.y, thickness, bounds.size.y),
		Rect2(bounds.end.x, bounds.position.y, thickness, bounds.size.y)
	]

	for w_rect in walls_data:
		var col := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = w_rect.size
		col.shape = rect_shape
		col.global_position = w_rect.position + w_rect.size * 0.5
		wall_body.add_child(col)

func _setup_wind_effects() -> void:
	wind_particles = MarsWindRenderer.new()
	wind_particles.setup(mars_bounds_rect)
	add_child(wind_particles)

	wind_player = AudioStreamPlayer.new()
	wind_player.volume_db = -60.0
	wind_player.stream = wind_sfx if wind_sfx != null else _generate_wind_loop_wav()
	add_child(wind_player)

func _on_outside_trigger_entered(body: Node2D) -> void:
	if body != player or is_teleporting or _ignore_outside_trigger or outside_mars_area == null:
		return
	if "is_outside" in player and player.is_outside:
		return
	_transition_player_to_mars()

func _on_outside_trigger_exited(body: Node2D) -> void:
	if body == player:
		_ignore_outside_trigger = false

func _on_outside_mars_entered(body: Node2D) -> void:
	if body != player or is_teleporting or _ignore_mars_trigger or outside_trigger == null:
		return
	if "is_outside" in player and not player.is_outside:
		return
	_transition_player_inside()

func _on_outside_mars_exited(body: Node2D) -> void:
	if body == player:
		_ignore_mars_trigger = false

func _transition_player_to_mars() -> void:
	is_teleporting = true
	_ignore_mars_trigger = true
	if player.has_method("set_input_locked"):
		player.set_input_locked(true)

	var trans = get_node_or_null("/root/Transition")
	if trans != null:
		await trans.fade_to_black(0.75)

	var mars_rect: Rect2 = _get_area_global_rect(outside_mars_area)
	var spawn_pos := Vector2(mars_rect.get_center().x, mars_rect.end.y + 48.0)

	player.global_position = spawn_pos
	if player.has_method("set_outside_mode"):
		player.set_outside_mode(true, mars_bounds_rect)

	wind_particles.active = true
	if not wind_player.playing:
		wind_player.play()
	var w_tw := create_tween()
	w_tw.tween_property(wind_player, "volume_db", wind_volume_db, 1.0)

	await get_tree().create_timer(0.2).timeout
	_ignore_mars_trigger = false

	if trans != null:
		await trans.fade_from_black(0.75)

	if player.has_method("set_input_locked"):
		player.set_input_locked(false)
	is_teleporting = false

func _transition_player_inside() -> void:
	is_teleporting = true
	_ignore_outside_trigger = true
	if player.has_method("set_input_locked"):
		player.set_input_locked(true)

	var trans = get_node_or_null("/root/Transition")
	if trans != null:
		await trans.fade_to_black(0.75)

	var inside_rect: Rect2 = _get_area_global_rect(outside_trigger)
	var spawn_pos := Vector2(inside_rect.get_center().x, inside_rect.position.y - 48.0)

	player.global_position = spawn_pos
	if player.has_method("set_outside_mode"):
		player.set_outside_mode(false, Rect2())

	wind_particles.active = false
	var w_tw := create_tween()
	w_tw.tween_property(wind_player, "volume_db", -60.0, 0.8)

	await get_tree().create_timer(0.2).timeout
	_ignore_outside_trigger = false

	if trans != null:
		await trans.fade_from_black(0.75)

	if player.has_method("set_input_locked"):
		player.set_input_locked(false)
	is_teleporting = false

func _generate_wind_loop_wav() -> AudioStreamWAV:
	var mix_rate: int = 22050
	var duration: float = 4.0
	var samples: int = int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var lp1: float = 0.0
	var lp2: float = 0.0

	for i in range(samples):
		var t: float = float(i) / float(mix_rate)
		var swell: float = 0.55 + 0.35 * sin(t * TAU * 0.25) + 0.15 * sin(t * TAU * 0.5)
		var white: float = randf_range(-1.0, 1.0)
		lp1 += 0.035 * (white - lp1)
		lp2 += 0.018 * (lp1 - lp2)
		var sample: float = clampf(lp2 * 2.8 * swell, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples
	wav.stereo = false
	wav.data = data
	return wav

func _set_rover_frame(f_idx: int) -> void:
	if rover == null:
		return
	if "frame" in rover:
		rover.set("frame", f_idx)
	else:
		var sp := rover.get_node_or_null("Sprite2D") as Sprite2D
		if sp != null:
			sp.frame = f_idx

func _play_rover_turn_animation() -> void:
	if rover == null:
		return
	var base_scale := rover.scale
	for f_idx in range(0, 5):
		_set_rover_frame(f_idx)
		var tw := create_tween()
		tw.tween_property(rover, "scale", Vector2(base_scale.x * 1.04, base_scale.y * 0.96), 0.05)
		tw.tween_property(rover, "scale", base_scale, 0.06)
		await get_tree().create_timer(0.11).timeout

func _start_rover_transition() -> void:
	GameManager.current_phase = GameManager.Phase.ROVER
	var has_supplies: bool = GameManager.stage_for_rover_drop()
	var trans = get_node_or_null("/root/Transition")

	if trans != null:
		await trans.shutter_close(0.6, Color(1.0, 0.82, 0.35))   # shop -> blinds slam shut

	if shop_layer != null:
		shop_layer.queue_free()
		shop_layer = null
		shop_terminal = null

	var player_outside_pos := Vector2(320, 600)
	if outside_mars_area != null:
		var mars_rect: Rect2 = _get_area_global_rect(outside_mars_area)
		player_outside_pos = Vector2(mars_rect.get_center().x, mars_rect.end.y + 48.0)

	var box_drop_pos := player_outside_pos + Vector2(0.0, 220.0)
	var rover_stop_pos := player_outside_pos + Vector2(0.0, 290.0)
	var rover_start_pos := player_outside_pos + Vector2(0.0, 560.0)

	_ignore_mars_trigger = true
	build_camera.enabled = false
	if player != null:
		if player.has_method("enable_player"):
			player.enable_player()
		player.global_position = player_outside_pos
		if player.has_method("set_outside_mode"):
			player.set_outside_mode(true, mars_bounds_rect)
		if player.has_method("set_input_locked"):
			player.set_input_locked(true)

	wind_particles.active = true
	if not wind_player.playing:
		wind_player.play()
	create_tween().tween_property(wind_player, "volume_db", wind_volume_db, 1.0)

	if rover != null:
		rover.visible = true
		rover.global_position = rover_start_pos
		_set_rover_frame(0)

	await get_tree().create_timer(0.15).timeout
	_ignore_mars_trigger = false

	if trans != null:
		await trans.shutter_open(0.7, Color(1.0, 0.82, 0.35))    # blinds open on Mars
	await day_loop.banner("SUPPLY DROP", "Rover inbound with your manifest", Color(1.0, 0.82, 0.35), 1.8)

	if rover != null:
		var tw_in := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_in.tween_property(rover, "global_position", rover_stop_pos, 2.4)
		await tw_in.finished

	var crate := SupplyCrate.new()
	add_child(crate)
	var rover_ground_pos := rover.global_position if rover != null else rover_stop_pos
	await crate.launch_from_rover(rover_ground_pos, 32.0, box_drop_pos, player)

	if not has_supplies:
		GameManager.deliver_pending_supplies()

	await get_tree().create_timer(0.25).timeout

	await _play_rover_turn_animation()

	if rover != null:
		var tw_out := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw_out.tween_property(rover, "global_position", rover_start_pos, 2.0)
		await tw_out.finished
		rover.visible = false
		_set_rover_frame(0)

	if trans != null:
		await trans.shutter_close(0.55, Color(1.0, 0.35, 0.3))   # rover gone -> blinds close (red = danger)
		await trans.shutter_open(0.6, Color(1.0, 0.35, 0.3))
	await day_loop.banner("SURVIVE", day_loop.survive_sub(), Color(1.0, 0.35, 0.3), 2.2)

	GameManager.current_phase = GameManager.Phase.SURVIVE
	day_loop.start_timer()
	if player != null and player.has_method("set_input_locked"):
		player.set_input_locked(false)
