# CHANGELOG (2026-11-15): Single cutscene/hazard corona shader source; no dependency on a running cutscene scene.
class_name SolarGas
extends RefCounted

const SHADER := """
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
