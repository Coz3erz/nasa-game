extends Control

@export_group("Assets")
@export var ship_texture: Texture2D

@export_group("Audio")
@export var ambient_audio: AudioStream
@export var audio_volume_db: float = -8.0
@export var typing_sfx: AudioStream
@export var typing_sfx_volume_db: float = -6.0

@export_group("Timing")
@export var fade_in_duration: float = 2.5
@export var total_duration: float = 20.0
@export var fade_out_duration: float = 1.5
@export var sol_type_delay: float = 2.0
@export var sol_char_delay: float = 0.32

@export_group("Ship")
@export var ship_position_override: Vector2 = Vector2(-1, -1)
@export var ship_start_x_ratio: float = 0.45
@export var ship_start_y_ratio: float = 0.60
@export var ship_drift_speed: float = 15.0
@export var ship_size_multiplier: float = 1.0
@export var ship_facing_left: bool = true
@export var ship_sun_light: float = 1.0

@export_group("Mars")
@export var mars_center_x_ratio: float = 0.14
@export var mars_center_y_ratio: float = 0.52
@export var mars_size_ratio: float = 0.56
@export var mars_rotation_speed: float = 0.025

@export_group("Sun Position")
@export var sun_center_x_ratio: float = 1.50
@export var sun_center_y_ratio: float = 0.50
@export var sun_container_size_ratio: float = 6.0
@export var sun_rotation_speed: float = 0.012

@export_group("Sun Shape")
@export var sun_radius_a: float = 1.0
@export var sun_radius_b: float = 1.0
@export var gas_radius: float = 1.95

@export_group("Sun Colors")
@export var sun_core_color: Color = Color(1.0, 1.0, 0.98)
@export var sun_mid_color: Color = Color(1.0, 0.85, 0.40)
@export var sun_edge_color: Color = Color(1.0, 0.58, 0.15)
@export var corona_near_color: Color = Color(1.0, 0.78, 0.32)
@export var corona_mid_color: Color = Color(1.0, 0.48, 0.12)
@export var corona_far_color: Color = Color(0.95, 0.28, 0.06)

@export_group("Sun Life")
@export var breath_period: float = 7.5
@export_range(0.0, 2.0, 0.05) var breath_depth: float = 1.0
@export var sunspot_radius: float = 0.22
@export var flare_interval: float = 1.6
@export var limb_ring_strength: float = 0.9

@export_group("Background")
@export var nebula_a_color: Color = Color(0.05, 0.02, 0.12)
@export var nebula_b_color: Color = Color(0.12, 0.02, 0.06)
@export var star_color: Color = Color(0.88, 0.94, 1.0)
@export_range(0.0, 1.5, 0.05) var lens_strength: float = 0.85

@export_group("Cinematic")
@export var camera_push: float = 0.07
@export var camera_shake: float = 1.0
@export var bloom_strength: float = 1.0
@export var vignette_strength: float = 0.75
@export var grain_strength: float = 1.0
@export var chroma_strength: float = 1.0
@export var heat_shimmer: float = 1.0
@export var ember_count: int = 150

@export_group("Text")
@export var sol_text: String = "SOL"
@export var sol_font_size_ratio: float = 0.075
@export var sol_color: Color = Color(0.42, 1.0, 0.55)
@export var sol_margin_ratio: float = 0.04

@export_group("Scene")
@export_file("*.tscn") var next_scene: String = "res://Main.tscn"

const BG_SHADER := """
shader_type canvas_item;
uniform float time = 0.0;
uniform float aspect = 1.7778;
uniform vec2 lens_center = vec2(2.67, 0.5);
uniform float lens_radius = 3.0;
uniform float lens_strength = 0.85;
uniform vec4 nebula_a : source_color = vec4(0.05, 0.02, 0.12, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.12, 0.02, 0.06, 1.0);
uniform vec4 star_col : source_color = vec4(0.88, 0.94, 1.0, 1.0);

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
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

vec3 star_layer(vec2 sp, float scale, float density, float size, float seed, float spikes) {
	vec2 g = sp * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash21(id + seed);
	if (h < density) { return vec3(0.0); }
	float k = (h - density) / (1.0 - density);
	vec2 off = (vec2(hash21(id + seed + 3.1), hash21(id + seed + 7.7)) - 0.5) * 0.6;
	vec2 d = f - off;
	float r = length(d);
	float tw = 0.65 + 0.35 * sin(time * (1.0 + k * 3.0) + k * 40.0);
	float core = smoothstep(size, 0.0, r) * tw;
	float halo = smoothstep(size * 5.0, 0.0, r) * 0.12;
	float cross = (smoothstep(0.012, 0.0, abs(d.y)) * smoothstep(0.45, 0.0, abs(d.x))
	             + smoothstep(0.012, 0.0, abs(d.x)) * smoothstep(0.45, 0.0, abs(d.y))) * spikes * k;
	float temp = hash21(id + seed + 11.3);
	vec3 tint = mix(vec3(0.62, 0.78, 1.0), vec3(1.0, 0.94, 0.86), smoothstep(0.0, 0.6, temp));
	tint = mix(tint, vec3(1.0, 0.62, 0.35), smoothstep(0.75, 1.0, temp));
	tint = mix(tint, star_col.rgb, 0.25);
	return tint * (core * (0.8 + 2.0 * k) + halo + cross * 0.6);
}

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);

	vec2 d = p - lens_center;
	float r = max(length(d), 0.0001);
	float R = lens_radius;
	float src = r - lens_strength * R * R / r;
	vec2 sp = lens_center + (d / r) * src;
	float x = r / R;
	float mag = 1.0 + 0.9 * lens_strength * exp(-(x - 1.0) * 7.0) * step(1.0, x + 0.15);

	vec2 np = sp * 0.9;
	float n1 = fbm(np + vec2(time * 0.004, time * 0.002));
	float n2 = fbm(np * 1.7 + vec2(-time * 0.006, time * 0.003) + vec2(3.7, 1.2));
	float dust = 1.0 - abs(fbm(np * 2.3 + 8.0) * 2.0 - 1.0);
	vec3 col = mix(nebula_a.rgb, nebula_b.rgb, n1 * n2);
	col *= (n1 * 0.55 + 0.10);
	col *= mix(1.0, 0.35, pow(dust, 4.0));
	float band = exp(-pow(dot(sp - vec2(1.2, 0.5), normalize(vec2(0.45, 1.0))) * 1.9, 2.0));
	col += mix(nebula_a.rgb, vec3(0.5, 0.3, 0.4), 0.5) * band * (0.25 + 0.5 * n2) * 0.7;

	vec3 st = vec3(0.0);
	st += star_layer(sp, 70.0, 0.955, 0.10, 1.0, 0.0);
	st += star_layer(sp, 130.0, 0.965, 0.085, 13.7, 0.0) * 0.9;
	st += star_layer(sp, 230.0, 0.975, 0.075, 29.1, 0.0) * 0.8;
	st += star_layer(sp, 28.0, 0.985, 0.06, 57.3, 1.0) * 1.8;
	col += st * (band * 1.6 + 1.0) * mag;

	COLOR = vec4(col, 1.0);
}
"""

const MARS_SHADER := """
shader_type canvas_item;
uniform float time = 0.0;
uniform float rotation_speed = 0.025;
uniform vec2 light_dir = vec2(0.85, -0.35);
uniform float breath = 0.0;

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
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(2.3, 5.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.4;
	float r = length(uv);
	if (r > 1.2) { discard; }

	vec2 L2 = normalize(light_dir + vec2(0.0001));
	vec3 L = normalize(vec3(L2, 0.35));

	float atmo_halo = exp(-max(r - 0.98, 0.0) * 14.0) * smoothstep(1.2, 0.98, r);
	float sun_side = clamp(dot(normalize(uv + vec2(0.0001)), L2) * 0.6 + 0.4, 0.0, 1.0);

	if (r > 1.0) {
		vec3 halo_col = vec3(1.0, 0.48, 0.22) * atmo_halo * sun_side * (0.65 + 0.2 * breath);
		COLOR = vec4(halo_col, atmo_halo * sun_side * 0.75);
	} else {
		float z = sqrt(max(1.0 - r * r, 0.0));
		vec3 N = normalize(vec3(uv, z));

		float lat = asin(clamp(uv.y, -0.999, 0.999));
		float lon = atan(uv.x, max(z, 0.0001)) - time * rotation_speed;
		vec2 S = vec2(lon * cos(lat), lat);

		float n1 = fbm(S * 2.6 + vec2(1.4, 3.2));
		float n2 = fbm(S * 6.5 - vec2(2.1, 0.8) + n1 * 0.45);
		float n3 = fbm(S * 16.0 + n2 * 0.35);
		float ridge = 1.0 - abs(fbm(S * 5.0 + 4.0) * 2.0 - 1.0);

		vec3 dark_rock = vec3(0.32, 0.12, 0.07);
		vec3 mid_rust = vec3(0.76, 0.29, 0.13);
		vec3 bright_ochre = vec3(0.95, 0.52, 0.26);

		vec3 albedo = mix(dark_rock, mid_rust, smoothstep(0.28, 0.62, n1));
		albedo = mix(albedo, bright_ochre, smoothstep(0.52, 0.85, n2) * 0.75);
		albedo *= 0.82 + 0.32 * n3;
		albedo = mix(albedo, vec3(0.22, 0.08, 0.05), pow(ridge, 6.0) * 0.45);

		float pole = smoothstep(0.78, 0.95, abs(uv.y) + (n2 - 0.5) * 0.12);
		albedo = mix(albedo, vec3(0.92, 0.84, 0.78), pole * 0.65);

		vec3 N_bump = normalize(N + vec3((n2 - 0.5) * 0.18, (n3 - 0.5) * 0.18, 0.0));
		float ndl = clamp(dot(N_bump, L), 0.0, 1.0);
		float terminator = smoothstep(-0.12, 0.25, dot(N, L));

		vec3 ambient = vec3(0.08, 0.03, 0.04);
		vec3 surface = albedo * (ambient + vec3(1.05, 0.88, 0.72) * pow(ndl, 0.85) * 1.25 * terminator);

		float rim = pow(1.0 - z, 2.6);
		vec3 atmo_col = mix(vec3(0.85, 0.32, 0.14), vec3(1.0, 0.68, 0.38), sun_side);
		surface = mix(surface, atmo_col, rim * (0.35 + 0.50 * sun_side));
		surface += atmo_col * rim * sun_side * (0.35 + 0.15 * breath);

		float edge_aa = 1.0 - smoothstep(0.985, 1.0, r);
		vec3 halo_col = vec3(1.0, 0.48, 0.22) * atmo_halo * sun_side * 0.5;
		vec3 final_col = mix(halo_col, surface, edge_aa);
		float final_alpha = max(edge_aa, atmo_halo * sun_side * 0.75);

		COLOR = vec4(final_col, final_alpha);
	}
}
"""

const SUN_INNER_SHADER := """
shader_type canvas_item;
uniform float time = 0.0;
uniform float rotation_speed = 0.012;
uniform vec2 sun_aspect = vec2(1.0, 1.0);
uniform vec4 core_col : source_color = vec4(1.0, 1.0, 0.98, 1.0);
uniform vec4 mid_col : source_color = vec4(1.0, 0.85, 0.40, 1.0);
uniform vec4 edge_col : source_color = vec4(1.0, 0.58, 0.15, 1.0);
uniform float breath = 0.0;
uniform float breath_phase = 0.0;
uniform float tension = 0.0;
uniform float ring_strength = 0.9;
uniform vec4 spot_a = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 spot_b = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 flare_a = vec4(0.0, 0.0, -1.0, 0.0);
uniform vec4 flare_b = vec4(0.0, 0.0, -1.0, 0.0);
uniform vec4 flare_c = vec4(0.0, 0.0, -1.0, 0.0);

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}
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
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + vec2(3.1, 7.3); a *= 0.5; }
	return v;
}
vec3 voro(vec2 p, float t) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 h = hash22(n + g);
			vec2 o = 0.5 + 0.5 * sin(t + 6.2831 * h);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; id = h.x; }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec3(sqrt(d1), sqrt(d2), id);
}
vec3 aces(vec3 x) {
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}
vec2 sunspot(vec2 S, vec2 c, float r, float seed) {
	vec2 d = S - c;
	float dl = length(d);
	if (dl > r * 2.6) { return vec2(0.0); }
	float ang = atan(d.y, d.x);
	float w = fbm(S * 9.0 / max(r, 0.01) * 0.12 + seed) - 0.5;
	float dd = dl + w * r * 0.55;
	float fil = fbm(vec2(ang * 5.0 + seed, dl / r * 3.0 - time * 0.05));
	float umbra = 1.0 - smoothstep(r * 0.55, r * 0.95, dd);
	float pen = (1.0 - smoothstep(r * 1.2, r * 2.15, dd + (fil - 0.5) * r * 0.5)) * (0.55 + 0.9 * fil);
	return vec2(umbra, clamp(pen, 0.0, 1.0));
}
float flare_burst(vec2 uv, vec4 f) {
	if (f.z < 0.0) { return 0.0; }
	float a = f.z;
	float d = length(uv - f.xy);
	float env = smoothstep(0.0, 0.35, a) * exp(-a * 0.55);
	float rad = 0.018 + a * 0.020;
	float blob = exp(-(d * d) / (rad * rad));
	float ring = exp(-pow((d - a * 0.075) / 0.008, 2.0));
	return (blob * 1.9 + ring * 0.5) * env * f.w;
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	uv.x /= sun_aspect.x;
	uv.y /= sun_aspect.y;

	float R = 1.0 - 0.011 * breath;
	float dist = length(uv) / R;
	if (dist > 1.0) { discard; }
	vec2 q = uv / R;
	float mu = sqrt(max(1.0 - dist * dist, 0.0));

	float lat = asin(clamp(q.y, -0.999, 0.999));
	float lon = atan(q.x, max(mu, 0.0001));
	lon -= time * rotation_speed * (1.0 - 0.28 * q.y * q.y);
	float swell = 1.0 - 0.012 * breath;
	vec2 S = vec2(lon * cos(lat), lat) * swell;
	float t = time;

	vec2 warp = vec2(fbm(S * 2.4 + vec2(t * 0.050, 0.0)), fbm(S * 2.4 + vec2(5.2, 1.3) - vec2(0.0, t * 0.040))) - 0.5;
	vec2 Sw = S + warp * 0.22;

	vec2 w2 = vec2(noise(Sw * 30.0 + t * 0.15), noise(Sw * 30.0 + 17.0 - t * 0.15)) - 0.5;
	vec3 g1 = voro(Sw * 4.0 + w2 * 0.25, t * 0.22);
	vec3 g2 = voro(Sw * 15.0 + 3.3 + w2 * 0.45, t * 0.45);
	vec3 g3 = voro(Sw * 44.0 + 9.1 + w2 * 0.8, t * 0.90);
	float lane1 = smoothstep(0.0, 0.45, g1.y - g1.x);
	float lane2 = pow(smoothstep(0.0, 0.34, g2.y - g2.x), 0.8);
	float lane3 = smoothstep(0.0, 0.30, g3.y - g3.x);
	float cen2 = 1.0 - smoothstep(0.0, 0.80, g2.x);
	float cen3 = 1.0 - smoothstep(0.0, 0.70, g3.x);

	float x = 0.35;
	x *= mix(0.60, 1.0, lane1) * (0.75 + 0.50 * g1.z);
	x *= mix(0.10 + 0.10 * (1.0 - breath), 1.0, lane2) * (0.55 + 0.90 * g2.z) * (0.65 + 0.70 * cen2);
	x *= mix(0.60, 1.0, lane3) * (0.85 + 0.30 * cen3);
	x *= 0.62 + 0.80 * fbm(Sw * 1.8 + 9.0);
	x += fbm(Sw * 90.0 + t * 0.3) * 0.08;
	x *= 1.45;

	float rv1 = 1.0 - abs(fbm(Sw * 4.2 + vec2(t * 0.035, -t * 0.028)) * 2.0 - 1.0);
	float rv2 = 1.0 - abs(fbm(Sw * 11.0 - vec2(t * 0.05, t * 0.03) + 4.0) * 2.0 - 1.0);
	float veins = (pow(rv1, 14.0) * 1.1 + pow(rv2, 18.0) * 0.6) * (1.0 - 0.7 * lane2);
	x += veins * (0.45 + 0.9 * breath + 0.7 * tension);

	vec2 sp1 = vec2(0.0);
	vec2 sp2 = vec2(0.0);
	if (spot_a.z > 0.0) {
		vec2 c = vec2(spot_a.x * cos(spot_a.y), spot_a.y);
		sp1 = sunspot(S, c, spot_a.z, 1.0);
		sp1 = max(sp1, sunspot(S, c + vec2(0.9, -0.55) * spot_a.z, spot_a.z * 0.38, 7.0));
		sp1 = max(sp1, sunspot(S, c + vec2(-0.8, 0.70) * spot_a.z, spot_a.z * 0.30, 11.0));
	}
	if (spot_b.z > 0.0) {
		vec2 c = vec2(spot_b.x * cos(spot_b.y), spot_b.y);
		sp2 = sunspot(S, c, spot_b.z, 3.0);
		sp2 = max(sp2, sunspot(S, c + vec2(-0.85, -0.6) * spot_b.z, spot_b.z * 0.35, 5.0));
	}
	vec2 sp = max(sp1, sp2);
	float umbral_dots = pow(noise(S * 120.0 + t * 0.4), 6.0) * 0.5;
	x *= 1.0 - sp.y * 0.55 * (1.0 - sp.x);
	x = mix(x, 0.07 + umbral_dots * 0.35, sp.x);
	float plage = smoothstep(0.0, 0.8, sp.y) * (1.0 - sp.x) * (1.0 - lane2) * 0.30;
	x += plage;

	float limb = mix(0.40, 1.0, pow(mu, 0.55));
	x *= limb;
	x += (1.0 - lane2) * (1.0 - mu) * (1.0 - mu) * 0.30 * fbm(Sw * 18.0);

	float wave = 0.5 + 0.5 * sin(dist * 16.0 - breath_phase * 6.2831);
	x *= (0.80 + 0.36 * breath) * (1.0 + 0.09 * wave * (0.4 + breath));
	x *= 1.0 + 0.10 * tension;

	x += flare_burst(uv, flare_a) + flare_burst(uv, flare_b) + flare_burst(uv, flare_c);

	float doppler = 1.0 + 0.35 * q.x;
	float ring = smoothstep(0.955, 0.994, dist) * (1.0 - smoothstep(0.994, 1.0, dist));
	x += ring * ring_strength * (0.9 + 0.9 * breath) * doppler;

	vec3 c1 = mix(edge_col.rgb * vec3(0.55, 0.12, 0.05), edge_col.rgb, smoothstep(0.0, 0.55, x));
	c1 = mix(c1, mid_col.rgb, smoothstep(0.50, 1.15, x));
	c1 = mix(c1, core_col.rgb, smoothstep(1.05, 1.90, x));
	vec3 col = c1 * (0.20 + 1.00 * x);
	col = aces(col * 1.05);
	col += (hash21(FRAGCOORD.xy + fract(time) * 91.0) - 0.5) / 255.0;

	float alpha = 1.0 - smoothstep(0.992, 1.0, dist);
	COLOR = vec4(col, alpha);
}
"""

const SUN_OUTER_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform float time = 0.0;
uniform vec2 sun_aspect = vec2(1.0, 1.0);
uniform float outer_uv = 1.95;
uniform vec4 near_col : source_color = vec4(1.0, 0.78, 0.32, 1.0);
uniform vec4 mid_col : source_color = vec4(1.0, 0.48, 0.12, 1.0);
uniform vec4 far_col : source_color = vec4(0.95, 0.28, 0.06, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	uv.x /= sun_aspect.x;
	uv.y /= sun_aspect.y;
	float dist = length(uv);
	if (dist < 0.85 || dist > outer_uv) { discard; }

	float angle = atan(-uv.y, -uv.x);
	float t = clamp(dist / outer_uv, 0.0, 1.0);

	float streak_a = fbm(vec2(angle * 7.0, t * 3.5 - time * 0.14));
	float streak_b = fbm(vec2(angle * 22.0, t * 8.0 - time * 0.30));
	float streak_c = fbm(vec2(angle * 48.0, t * 16.0 - time * 0.55));

	float streaks = streak_a * 0.50 + streak_b * 0.32 + streak_c * 0.18;
	streaks = smoothstep(0.25, 0.78, streaks);

	float fade = smoothstep(0.85, 1.05, dist) * (1.0 - smoothstep(1.0, outer_uv, dist));
	fade = pow(fade, 1.6);

	float intensity = fade * (streaks * 2.0 + 0.22);

	vec3 col;
	if (t < 0.35) {
		col = mix(near_col.rgb, mid_col.rgb, t / 0.35);
	} else {
		col = mix(mid_col.rgb, far_col.rgb, (t - 0.35) / 0.65);
	}

	float prom = fbm(vec2(angle * 2.5, t * 4.5 - time * 0.09));
	float prom_mask = smoothstep(0.55, 0.86, prom);
	float prom_band = smoothstep(1.1, 0.95, dist);
	col += near_col.rgb * prom_mask * prom_band * 0.85;

	COLOR = vec4(col * intensity * 1.6, 1.0);
}
"""

const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float time = 0.0;
uniform float breath = 0.0;
uniform float tension = 0.0;
uniform float aspect = 1.7778;
uniform vec2 sun_uv = vec2(1.5, 0.5);
uniform float bloom_strength = 1.0;
uniform float vignette_strength = 0.75;
uniform float grain_strength = 1.0;
uniform float chroma_strength = 1.0;
uniform float heat_shimmer = 1.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec2 sd = uv - sun_uv;
	sd.x *= aspect;

	float w = heat_shimmer / (1.0 + length(sd) * 0.45);
	vec2 haze = vec2(sin(uv.y * 85.0 + time * 3.1 + sin(uv.x * 37.0 + time * 1.3) * 2.0),
	                 cos(uv.x * 63.0 - time * 2.4 + sin(uv.y * 29.0 + time) * 2.0)) * 0.00085 * w;
	vec2 suv = uv + haze;

	float ca = chroma_strength * 0.0045 * (0.25 + dot(c, c) * 3.0);
	vec3 col;
	col.r = textureLod(screen_tex, suv + c * ca, 0.0).r;
	col.g = textureLod(screen_tex, suv, 0.0).g;
	col.b = textureLod(screen_tex, suv - c * ca, 0.0).b;

	vec3 hi = textureLod(screen_tex, suv, 3.0).rgb * 0.5 + textureLod(screen_tex, suv, 4.5).rgb * 0.5;
	vec3 avg = textureLod(screen_tex, suv, 7.0).rgb;
	vec3 bl = max(hi - avg * 0.80, vec3(0.0));
	col += bl * 0.70 * bloom_strength * (0.80 + 0.55 * breath + 0.35 * tension);
	col += avg * 0.10 * bloom_strength;

	vec3 st = vec3(0.0);
	for (int i = -4; i <= 4; i++) {
		vec3 s = textureLod(screen_tex, suv + vec2(float(i) * 0.028, 0.0), 4.0).rgb;
		st += s * (1.0 - abs(float(i)) / 5.0);
	}
	st /= 5.0;
	float st_l = dot(st, vec3(0.30, 0.59, 0.11));
	col += st * vec3(0.55, 0.78, 1.0) * smoothstep(0.80, 1.00, st_l) * 0.10 * bloom_strength;

	float lum = dot(col, vec3(0.30, 0.59, 0.11));
	col = mix(col, col * vec3(0.90, 0.97, 1.10), 1.0 - smoothstep(0.0, 0.30, lum));
	col = mix(col, col * col * (3.0 - 2.0 * col), 0.30);
	col *= 1.0 + 0.05 * (breath - 0.5);

	float vig = smoothstep(0.30, 1.05, length(c * vec2(aspect * 0.62, 1.0)) * 1.35);
	col *= 1.0 - vig * (vignette_strength + 0.20 * tension);

	float n = hash21(FRAGCOORD.xy + fract(time) * vec2(37.0, 91.0)) - 0.5;
	col += n * grain_strength * (0.030 + 0.035 * (1.0 - clamp(lum, 0.0, 1.0)));

	COLOR = vec4(col, 1.0);
}
"""

const SHIP_SHADER := """
shader_type canvas_item;
uniform vec2 light_dir = vec2(1.0, 0.0);
uniform vec2 extent = vec2(140.0, 62.0);
uniform vec3 sun_light : source_color = vec3(1.0, 0.62, 0.26);
uniform float light_amount = 1.0;
uniform float breath = 0.0;
uniform float emissive_k = 1.0;
varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = lp / extent;
	vec3 n = normalize(vec3(q.x * 0.85, q.y * 0.95, 0.55));
	vec3 L = normalize(vec3(light_dir, 0.30));
	float ndl = clamp(dot(n, L), 0.0, 1.0);
	float facing = max(dot(normalize(n.xy + vec2(0.0001)), light_dir), 0.0);
	float rim = pow(1.0 - n.z, 1.6) * facing;
	float emissive = emissive_k * smoothstep(0.30, 0.55, COLOR.b - COLOR.r);
	vec3 base = COLOR.rgb;
	vec3 ambient = vec3(0.62, 0.36, 0.22) * (0.8 + 0.5 * breath);
	vec3 lit = base * 1.25 * (ambient + sun_light * ndl * 1.5) * light_amount;
	lit += sun_light * rim * 1.4 * light_amount;
	lit += vec3(1.0, 0.8, 0.5) * pow(max(dot(n, normalize(L + vec3(0.0, 0.0, 1.0))), 0.0), 40.0) * 0.5 * light_amount;
	COLOR.rgb = mix(lit, base * 1.1, emissive);
}
"""

class ShipRenderer extends Node2D:
	var time: float = 0.0
	var ship_texture: Texture2D

	func _process(delta: float) -> void:
		time += delta
		queue_redraw()

	func _draw() -> void:
		if ship_texture:
			var sz := ship_texture.get_size()
			draw_texture(ship_texture, -sz * 0.5)
			return

		var pod_l_top := PackedVector2Array([Vector2(-100, -32), Vector2(-42, -32), Vector2(-52, -62), Vector2(-90, -62)])
		var pod_l_bot := PackedVector2Array([Vector2(-100, 32), Vector2(-42, 32), Vector2(-52, 62), Vector2(-90, 62)])
		var pod_r_top := PackedVector2Array([Vector2(22, -32), Vector2(80, -32), Vector2(70, -62), Vector2(32, -62)])
		var pod_r_bot := PackedVector2Array([Vector2(22, 32), Vector2(80, 32), Vector2(70, 62), Vector2(32, 62)])
		
		draw_polygon(pod_l_top, [Color(0.28, 0.31, 0.36)])
		draw_polygon(pod_l_bot, [Color(0.16, 0.18, 0.22)])
		draw_polygon(pod_r_top, [Color(0.28, 0.31, 0.36)])
		draw_polygon(pod_r_bot, [Color(0.16, 0.18, 0.22)])

		var pod_edges := Color(0.10, 0.12, 0.15, 0.9)
		draw_polyline(PackedVector2Array([Vector2(-100, -32), Vector2(-42, -32), Vector2(-52, -62), Vector2(-90, -62), Vector2(-100, -32)]), pod_edges, 1.0)
		draw_polyline(PackedVector2Array([Vector2(-100, 32), Vector2(-42, 32), Vector2(-52, 62), Vector2(-90, 62), Vector2(-100, 32)]), pod_edges, 1.0)
		draw_polyline(PackedVector2Array([Vector2(22, -32), Vector2(80, -32), Vector2(70, -62), Vector2(32, -62), Vector2(22, -32)]), pod_edges, 1.0)
		draw_polyline(PackedVector2Array([Vector2(22, 32), Vector2(80, 32), Vector2(70, 62), Vector2(32, 62), Vector2(22, 32)]), pod_edges, 1.0)

		var hull := PackedVector2Array([
			Vector2(-140, -18), Vector2(-120, -42), Vector2(60, -42),
			Vector2(120, -25), Vector2(140, 0), Vector2(120, 25),
			Vector2(60, 42), Vector2(-120, 42), Vector2(-140, 18)
		])
		draw_polygon(hull, [Color(0.22, 0.25, 0.30)])

		var upper := PackedVector2Array([
			Vector2(-130, -16), Vector2(-110, -38), Vector2(50, -38),
			Vector2(110, -23), Vector2(130, 0), Vector2(110, 0),
			Vector2(50, -10), Vector2(-110, -10), Vector2(-130, 0)
		])
		draw_polygon(upper, [Color(0.34, 0.37, 0.42)])

		var lower := PackedVector2Array([
			Vector2(-130, 16), Vector2(-110, 38), Vector2(50, 38),
			Vector2(110, 23), Vector2(130, 0), Vector2(110, 0),
			Vector2(50, 10), Vector2(-110, 10), Vector2(-130, 0)
		])
		draw_polygon(lower, [Color(0.14, 0.16, 0.20)])

		var cockpit := PackedVector2Array([
			Vector2(60, -22), Vector2(105, -15), Vector2(125, 0),
			Vector2(105, 15), Vector2(60, 22), Vector2(40, 0)
		])
		draw_polygon(cockpit, [Color(0.04, 0.12, 0.25, 0.95)])

		var cockpit_inner := PackedVector2Array([
			Vector2(70, -16), Vector2(100, -10), Vector2(115, 0),
			Vector2(100, 10), Vector2(70, 16), Vector2(55, 0)
		])
		draw_polygon(cockpit_inner, [Color(0.14, 0.34, 0.55, 0.90)])
		draw_polyline(PackedVector2Array([Vector2(72, -14), Vector2(98, -8), Vector2(110, 0)]), Color(0.70, 0.90, 1.0, 0.70), 1.5)

		draw_rect(Rect2(-135, -30, 15, 60), Color(0.25, 0.28, 0.32))
		draw_rect(Rect2(-135, -30, 15, 60), Color(0.14, 0.16, 0.19), false, 1.0)

		var window_color := Color(0.30, 0.70, 1.0, 0.90)
		for i in range(4):
			var wx := -30.0 + i * 18.0
			draw_rect(Rect2(wx, -38, 8, 4), window_color)
			draw_rect(Rect2(wx, 34, 8, 4), window_color)

		var screw_color := Color(0.12, 0.13, 0.16)
		var screws := [
			Vector2(-100, -35), Vector2(-60, -35), Vector2(-20, -35),
			Vector2(20, -35), Vector2(50, -35),
			Vector2(-100, 35), Vector2(-60, 35), Vector2(-20, 35),
			Vector2(20, 35), Vector2(50, 35),
			Vector2(-125, -20), Vector2(-125, 20),
			Vector2(-70, -50), Vector2(-70, 50),
			Vector2(40, -50), Vector2(40, 50)
		]
		for sp in screws:
			draw_circle(sp, 1.2, screw_color)

		draw_polygon(PackedVector2Array([Vector2(-130, -45), Vector2(-115, -45), Vector2(-120, -55)]), [Color(0.30, 0.60, 1.0, 0.60)])
		draw_polygon(PackedVector2Array([Vector2(-130, 45), Vector2(-115, 45), Vector2(-120, 55)]), [Color(0.30, 0.60, 1.0, 0.60)])

		var outline := hull.duplicate()
		outline.append(hull[0])
		draw_polyline(outline, Color(0.55, 0.58, 0.62, 0.45), 1.0)

class EngineGlow extends Node2D:
	var time: float = 0.0
	var engine_x: float = -145.0
	var half_h: float = 18.0
	var power: float = 1.0

	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func _process(delta: float) -> void:
		time += delta
		queue_redraw()

	func _draw() -> void:
		var fl := (45.0 + sin(time * 20.0) * 8.0 + sin(time * 37.0) * 4.0 + sin(time * 61.0) * 2.5) * power
		var ex := engine_x
		for i in range(10):
			var k := float(i) / 9.0
			draw_circle(Vector2(ex - 6.0, 0.0), lerpf(95.0, 14.0, k), Color(0.25, 0.50, 1.0, 0.010 + 0.014 * k * power))
		var plume_a := PackedVector2Array([Vector2(ex, -half_h * 1.3), Vector2(ex - fl * 1.45, 0.0), Vector2(ex, half_h * 1.3)])
		var plume_b := PackedVector2Array([Vector2(ex, -half_h), Vector2(ex - fl, 0.0), Vector2(ex, half_h)])
		var plume_c := PackedVector2Array([Vector2(ex, -half_h * 0.55), Vector2(ex - fl * 0.62, 0.0), Vector2(ex, half_h * 0.55)])
		draw_polygon(plume_a, [Color(0.20, 0.45, 1.0, 0.20)])
		draw_polygon(plume_b, [Color(0.30, 0.60, 1.0, 0.55)])
		draw_polygon(plume_c, [Color(0.92, 0.96, 1.0, 0.95)])

class EmberField extends Node2D:
	var view_size: Vector2 = Vector2(1920, 1080)
	var drift: float = 25.0
	var intensity: float = 1.0
	var time: float = 0.0
	var pos := PackedVector2Array()
	var depth := PackedFloat32Array()
	var phase := PackedFloat32Array()

	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func setup(n: int, size: Vector2) -> void:
		view_size = size
		pos.resize(n)
		depth.resize(n)
		phase.resize(n)
		for i in range(n):
			pos[i] = Vector2(randf() * size.x, randf() * size.y)
			depth[i] = pow(randf(), 1.7)
			phase[i] = randf() * TAU

	func _process(delta: float) -> void:
		time += delta
		var s := view_size.y / 1080.0
		for i in range(pos.size()):
			var d := depth[i]
			var p := pos[i]
			p.x += (drift * (0.35 + 2.6 * d) + sin(time * 0.6 + phase[i]) * 14.0 * d) * delta
			p.y += (-(10.0 + 36.0 * d) * s + cos(time * 0.9 + phase[i] * 1.7) * 10.0) * delta
			if p.x > view_size.x + 40.0:
				p = Vector2(-40.0, randf() * view_size.y)
			elif p.x < -40.0:
				p.x = view_size.x + 40.0
			if p.y < -40.0:
				p = Vector2(randf() * view_size.x, view_size.y + 40.0)
			pos[i] = p
		queue_redraw()

	func _draw() -> void:
		var s := view_size.y / 1080.0
		for i in range(pos.size()):
			var d := depth[i]
			var tw := 0.6 + 0.4 * sin(time * (2.0 + d * 3.0) + phase[i])
			var hue := fposmod(phase[i] * 0.37, 1.0)
			var c := Color(1.0, 0.45 + 0.45 * hue, 0.12 + 0.50 * hue * hue)
			var sz := lerpf(1.1, 4.2, d * d) * s
			var a := (0.30 + 0.55 * d) * tw * intensity
			draw_circle(pos[i], sz * 4.5, Color(c.r, c.g, c.b, 0.045 * a))
			draw_circle(pos[i], sz, Color(c.r, c.g, c.b, a))
			if d > 0.9:
				draw_circle(pos[i], (20.0 + 30.0 * (d - 0.9) * 10.0) * s, Color(1.0, 0.5, 0.2, 0.028 * intensity))

var time: float = 0.0
var view_size: Vector2
var font: SystemFont
var world: Control
var bg_layer: ColorRect
var sun_container: Control
var sun_inner: ColorRect
var sun_outer: ColorRect
var mars_rect: ColorRect
var ship_node: ShipRenderer
var engine_glow: EngineGlow
var embers: EmberField
var sol_label: Label
var post_layer: ColorRect
var audio_player: AudioStreamPlayer
var typing_player: AudioStreamPlayer
var bg_mat: ShaderMaterial
var sun_inner_mat: ShaderMaterial
var sun_outer_mat: ShaderMaterial
var mars_mat: ShaderMaterial
var ship_mat: ShaderMaterial
var post_mat: ShaderMaterial
var typing_started: bool = false
var ship_placed: bool = false
var scene_ending: bool = false

var rng := RandomNumberGenerator.new()
var sun_center: Vector2 = Vector2.ZERO
var mars_center: Vector2 = Vector2.ZERO
var container_size: float = 1.0
var breath: float = 0.0
var breath_phase: float = 0.0
var tension: float = 0.0
var ship_home_y_ratio: float = 0.6
var flares: Array = [
	{"pos": Vector2.ZERO, "age": -1.0, "dur": 4.0, "str": 1.0},
	{"pos": Vector2.ZERO, "age": -1.0, "dur": 4.0, "str": 1.0},
	{"pos": Vector2.ZERO, "age": -1.0, "dur": 4.0, "str": 1.0},
]
var next_flare_time: float = 1.5
var sol_typed: String = ""
var sol_flash: float = 0.0
var sol_base_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_size = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_resize)
	rng.randomize()

	font = SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "monospace"])

	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_background()
	_build_sun()
	_build_mars()
	_build_ship()
	_build_embers()
	_build_sol_text()
	_build_post()
	_build_audio()
	_layout()

	var trans = get_node_or_null("/root/Transition")
	if trans:
		trans.overlay.modulate.a = 1.0
		trans.fade_from_black(fade_in_duration)

	_schedule_end()
	_delayed_type_sol()

func _make_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _build_background() -> void:
	bg_layer = ColorRect.new()
	bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.color = Color.BLACK
	bg_mat = _make_mat(BG_SHADER)
	bg_layer.material = bg_mat
	world.add_child(bg_layer)
	bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_sun() -> void:
	sun_container = Control.new()
	sun_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(sun_container)

	sun_inner = ColorRect.new()
	sun_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun_inner_mat = _make_mat(SUN_INNER_SHADER)
	sun_inner.material = sun_inner_mat
	sun_container.add_child(sun_inner)
	sun_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	sun_outer = ColorRect.new()
	sun_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun_outer_mat = _make_mat(SUN_OUTER_SHADER)
	sun_outer.material = sun_outer_mat
	sun_container.add_child(sun_outer)
	sun_outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_mars() -> void:
	mars_rect = ColorRect.new()
	mars_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mars_mat = _make_mat(MARS_SHADER)
	mars_rect.material = mars_mat
	world.add_child(mars_rect)

func _build_ship() -> void:
	ship_node = ShipRenderer.new()
	ship_node.ship_texture = ship_texture
	ship_mat = _make_mat(SHIP_SHADER)
	ship_node.material = ship_mat
	if ship_texture:
		ship_mat.set_shader_parameter("extent", ship_texture.get_size() * 0.5)
		ship_mat.set_shader_parameter("emissive_k", 0.0)
	world.add_child(ship_node)

	engine_glow = EngineGlow.new()
	if ship_texture:
		engine_glow.engine_x = -ship_texture.get_size().x * 0.5
		engine_glow.half_h = ship_texture.get_size().y * 0.12
	ship_node.add_child(engine_glow)

func _build_embers() -> void:
	embers = EmberField.new()
	world.add_child(embers)

func _build_sol_text() -> void:
	sol_label = Label.new()
	sol_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_color = sol_color
	ls.font_size = 48
	sol_label.label_settings = ls
	sol_label.text = ""
	add_child(sol_label)

func _build_post() -> void:
	post_layer = ColorRect.new()
	post_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_layer.color = Color.WHITE
	post_mat = _make_mat(POST_SHADER)
	post_layer.material = post_mat
	add_child(post_layer)
	post_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.volume_db = audio_volume_db
	add_child(audio_player)
	if ambient_audio:
		var st = ambient_audio.duplicate()
		if "loop" in st:
			st.loop = true
		audio_player.stream = st
		audio_player.play()

	typing_player = AudioStreamPlayer.new()
	typing_player.volume_db = typing_sfx_volume_db
	add_child(typing_player)
	if typing_sfx:
		typing_player.stream = typing_sfx

func _screen_to_sun_uv(sp: Vector2) -> Vector2:
	var half := container_size * 0.5
	return Vector2((sp.x - sun_center.x) / half / sun_radius_a, (sp.y - sun_center.y) / half / sun_radius_b)

func _sun_uv_to_lonlat(u: Vector2) -> Vector2:
	if u.length() > 0.9:
		u = u.normalized() * 0.9
	var z := sqrt(maxf(1.0 - u.length_squared(), 0.0001))
	return Vector2(atan2(u.x, z), asin(clampf(u.y, -0.999, 0.999)))

func _layout() -> void:
	view_size = get_viewport_rect().size
	world.pivot_offset = view_size * 0.5

	sun_center = Vector2(view_size.x * sun_center_x_ratio, view_size.y * sun_center_y_ratio)
	container_size = view_size.y * sun_container_size_ratio
	sun_container.size = Vector2(container_size, container_size)
	sun_container.position = sun_center - Vector2(container_size, container_size) * 0.5

	if mars_rect:
		mars_center = Vector2(view_size.x * mars_center_x_ratio, view_size.y * mars_center_y_ratio)
		var m_size: float = view_size.y * mars_size_ratio
		mars_rect.size = Vector2(m_size, m_size)
		mars_rect.position = mars_center - Vector2(m_size, m_size) * 0.5

	if ship_node:
		var ship_scale: float = view_size.y / 780.0 * ship_size_multiplier
		var x_sign := -1.0 if ship_facing_left else 1.0
		ship_node.scale = Vector2(ship_scale * x_sign, ship_scale)
		if not ship_placed:
			if ship_position_override != Vector2(-1, -1):
				ship_node.position = ship_position_override
			else:
				ship_node.position = Vector2(view_size.x * ship_start_x_ratio, view_size.y * ship_start_y_ratio)
			ship_home_y_ratio = ship_node.position.y / view_size.y
			ship_placed = true

	if embers:
		if embers.pos.size() != ember_count:
			embers.setup(ember_count, view_size)
		embers.view_size = view_size

	var sol_fs := clampi(int(min(view_size.x, view_size.y) * sol_font_size_ratio), 28, 80)
	sol_label.label_settings.font_size = sol_fs
	var pad: float = min(view_size.x, view_size.y) * sol_margin_ratio
	sol_base_pos = Vector2(pad, pad)
	sol_label.position = sol_base_pos

	var aspect := view_size.x / view_size.y
	bg_mat.set_shader_parameter("aspect", aspect)
	bg_mat.set_shader_parameter("lens_center", Vector2(sun_center.x / view_size.y, sun_center.y / view_size.y))
	bg_mat.set_shader_parameter("lens_radius", container_size * 0.5 / view_size.y)
	post_mat.set_shader_parameter("aspect", aspect)
	post_mat.set_shader_parameter("sun_uv", Vector2(sun_center.x / view_size.x, sun_center.y / view_size.y))

	var r_uv := sunspot_radius / (sun_container_size_ratio * 0.5)
	var la := _sun_uv_to_lonlat(_screen_to_sun_uv(Vector2(view_size.x * 0.74, view_size.y * 0.30)))
	var lb := _sun_uv_to_lonlat(_screen_to_sun_uv(Vector2(view_size.x * 0.30, view_size.y * 0.22)))
	sun_inner_mat.set_shader_parameter("spot_a", Vector4(la.x, la.y, r_uv, 1.0))
	sun_inner_mat.set_shader_parameter("spot_b", Vector4(lb.x, lb.y, r_uv * 0.55, 1.0))

func _on_resize() -> void:
	_layout()

func _schedule_end() -> void:
	await get_tree().create_timer(total_duration).timeout
	if not is_inside_tree() or scene_ending:
		return
	scene_ending = true

	if audio_player and audio_player.playing:
		var at := create_tween()
		at.tween_property(audio_player, "volume_db", -60.0, fade_out_duration)

	var trans = get_node_or_null("/root/Transition")
	if trans:
		trans.change_scene(next_scene, fade_out_duration)
	else:
		get_tree().change_scene_to_file(next_scene)

func _delayed_type_sol() -> void:
	await get_tree().create_timer(sol_type_delay).timeout
	if not is_inside_tree():
		return
	_type_sol()

var typing_active: bool = false

func _type_sol() -> void:
	if typing_started:
		return
	typing_started = true
	typing_active = true
	sol_typed = ""
	for i in range(sol_text.length()):
		if not is_inside_tree():
			return
		sol_typed = sol_text.substr(0, i + 1)
		sol_flash = 1.0
		if typing_player and typing_player.stream:
			typing_player.play()
		await get_tree().create_timer(sol_char_delay).timeout
	typing_active = false

func _apply_sun_uniforms() -> void:
	if not sun_inner_mat or not sun_outer_mat:
		return

	sun_inner_mat.set_shader_parameter("time", time)
	sun_inner_mat.set_shader_parameter("sun_aspect", Vector2(sun_radius_a, sun_radius_b))
	sun_inner_mat.set_shader_parameter("rotation_speed", sun_rotation_speed)
	sun_inner_mat.set_shader_parameter("core_col", sun_core_color)
	sun_inner_mat.set_shader_parameter("mid_col", sun_mid_color)
	sun_inner_mat.set_shader_parameter("edge_col", sun_edge_color)
	sun_inner_mat.set_shader_parameter("breath", breath)
	sun_inner_mat.set_shader_parameter("breath_phase", breath_phase)
	sun_inner_mat.set_shader_parameter("tension", tension)
	sun_inner_mat.set_shader_parameter("ring_strength", limb_ring_strength)
	var fnames := ["flare_a", "flare_b", "flare_c"]
	for i in range(3):
		var f: Dictionary = flares[i]
		var p: Vector2 = f["pos"]
		sun_inner_mat.set_shader_parameter(fnames[i], Vector4(p.x, p.y, f["age"], f["str"]))

	sun_outer_mat.set_shader_parameter("time", time)
	sun_outer_mat.set_shader_parameter("sun_aspect", Vector2(sun_radius_a, sun_radius_b))
	sun_outer_mat.set_shader_parameter("outer_uv", gas_radius)
	sun_outer_mat.set_shader_parameter("near_col", corona_near_color)
	sun_outer_mat.set_shader_parameter("mid_col", corona_mid_color)
	sun_outer_mat.set_shader_parameter("far_col", corona_far_color)

	if mars_mat:
		mars_mat.set_shader_parameter("time", time)
		mars_mat.set_shader_parameter("rotation_speed", mars_rotation_speed)
		mars_mat.set_shader_parameter("light_dir", (sun_center - mars_center).normalized())
		mars_mat.set_shader_parameter("breath", breath)

	bg_mat.set_shader_parameter("time", time)
	bg_mat.set_shader_parameter("nebula_a", nebula_a_color)
	bg_mat.set_shader_parameter("nebula_b", nebula_b_color)
	bg_mat.set_shader_parameter("star_col", star_color)
	bg_mat.set_shader_parameter("lens_strength", lens_strength)

func _update_breath(delta: float) -> void:
	breath_phase += delta / maxf(breath_period, 0.5) * (1.0 + 0.18 * sin(time * 0.41))
	var c := fposmod(breath_phase, 1.0)
	var b := 0.0
	if c < 0.38:
		b = smoothstep(0.0, 1.0, c / 0.38)
	else:
		b = 1.0 - smoothstep(0.0, 1.0, (c - 0.38) / 0.62)
	b += sin(time * 5.3) * 0.025 * (0.3 + tension)
	breath = clampf(0.5 + (b - 0.5) * breath_depth, 0.0, 1.0)

func _update_flares(delta: float) -> void:
	for f in flares:
		if f["age"] >= 0.0:
			f["age"] += delta
			if f["age"] > f["dur"]:
				f["age"] = -1.0
	if time >= next_flare_time and not scene_ending:
		for f in flares:
			if f["age"] < 0.0:
				var sp := Vector2(rng.randf_range(0.08, 0.92) * view_size.x, rng.randf_range(0.10, 0.90) * view_size.y)
				var u := _screen_to_sun_uv(sp)
				if u.length() > 0.93:
					u = u.normalized() * 0.93
				f["pos"] = u
				f["age"] = 0.0
				f["str"] = rng.randf_range(0.7, 1.3)
				f["dur"] = rng.randf_range(3.2, 4.5)
				break
		next_flare_time = time + rng.randf_range(0.7, 1.8) * flare_interval / (1.0 + tension)

func _update_ship(delta: float) -> void:
	if not ship_node:
		return
	var s := view_size.y / 1080.0
	ship_node.position.x -= ship_drift_speed * delta * (view_size.y / 648.0)
	ship_node.position.y = view_size.y * ship_home_y_ratio + sin(time * 0.8) * 3.0 * s + sin(time * 13.0) * 0.6 * s * (0.5 + tension)
	ship_node.rotation = sin(time * 0.33) * 0.010 + sin(time * 11.0) * 0.0015 * (0.5 + tension)

	var to_sun := (sun_center - ship_node.position).normalized()
	var local_dir := ship_node.transform.affine_inverse().basis_xform(to_sun).normalized()
	ship_mat.set_shader_parameter("light_dir", local_dir)
	ship_mat.set_shader_parameter("light_amount", ship_sun_light * (0.85 + 0.30 * breath + 0.2 * tension))
	ship_mat.set_shader_parameter("breath", breath)
	if engine_glow:
		engine_glow.power = 1.0 + 0.20 * breath + 0.25 * tension
	if embers:
		embers.drift = ship_drift_speed * (view_size.y / 648.0)
		embers.intensity = 0.8 + 0.5 * breath + 0.4 * tension

func _update_camera() -> void:
	var s := 1.018 + camera_push * tension + 0.004 * breath
	var amp := minf(camera_shake * (view_size.y / 1080.0) * (1.2 + 3.5 * tension + 1.6 * breath), 14.0)
	var off := Vector2(
		sin(time * 1.7) + 0.6 * sin(time * 2.9 + 1.3) + 0.3 * sin(time * 7.3),
		sin(time * 2.1 + 0.7) + 0.5 * sin(time * 3.3) + 0.3 * sin(time * 6.1)) * amp
	world.scale = Vector2(s, s)
	world.position = off
	world.rotation = sin(time * 0.27) * 0.0025 * camera_shake

func _update_post() -> void:
	post_mat.set_shader_parameter("time", time)
	post_mat.set_shader_parameter("breath", breath)
	post_mat.set_shader_parameter("tension", tension)
	post_mat.set_shader_parameter("bloom_strength", bloom_strength)
	post_mat.set_shader_parameter("vignette_strength", vignette_strength)
	post_mat.set_shader_parameter("grain_strength", grain_strength)
	post_mat.set_shader_parameter("chroma_strength", chroma_strength)
	post_mat.set_shader_parameter("heat_shimmer", heat_shimmer)

func _update_text(delta: float) -> void:
	sol_flash = maxf(0.0, sol_flash - delta * 3.5)
	if typing_started:
		var show_cursor := typing_active or int(time * 2.4) % 2 == 0
		sol_label.text = sol_typed + ("_" if show_cursor else "")
	var flick := 0.93 + 0.07 * sin(time * 43.0) * sin(time * 7.0)
	var m := flick + sol_flash * 0.9
	sol_label.modulate = Color(m, m, m, minf(m, 1.0))
	var jitter := 0.0
	if rng.randf() < 0.012:
		jitter = rng.randf_range(-2.5, 2.5)
	sol_label.position = sol_base_pos + Vector2(jitter, 0.0)

func _update_audio() -> void:
	if audio_player and audio_player.playing and not scene_ending:
		audio_player.volume_db = audio_volume_db + (breath - 0.5) * 3.0 + tension * 2.0

func _process(delta: float) -> void:
	time += delta
	var t01 := clampf(time / maxf(total_duration, 0.1), 0.0, 1.0)
	tension = t01 * t01 * (3.0 - 2.0 * t01)

	_update_breath(delta)
	_update_flares(delta)
	_apply_sun_uniforms()
	_update_ship(delta)
	_update_camera()
	_update_post()
	_update_text(delta)
	_update_audio()
