extends Control

@export_category("Terminal Style")
@export var bg_color: Color = Color(0.005, 0.008, 0.02, 0.98)
@export var text_color: Color = Color(0.88, 0.95, 1.0)
@export var highlight_color: Color = Color(0.42, 1.0, 0.55)
@export var accent_cyan: Color = Color(0.3, 0.85, 1.0)
@export var dim_color: Color = Color(0.4, 0.48, 0.58)
@export var prompt_char: String = "> "

@export_category("Cosmic Shader")
@export var base_glow_color: Color = Color(0.01, 0.04, 0.10, 1.0)
@export var ring_color: Color = Color(0.04, 0.16, 0.34, 1.0)
@export var secondary_ring_color: Color = Color(0.05, 0.28, 0.18, 1.0)
@export var foam_color: Color = Color(0.35, 0.70, 0.90, 0.45)
@export var nebula_a: Color = Color(0.006, 0.004, 0.018, 1.0)
@export var nebula_b: Color = Color(0.004, 0.014, 0.032, 1.0)
@export var bleed: float = 18.0
@export var ring_speed: float = 0.045
@export var secondary_ring_speed: float = 0.028
@export var foam_speed: float = 0.065
@export var foam_width: float = 0.012
@export var foam_wave_freq: float = 5.0
@export var foam_wave_amp: float = 0.014
@export var circle_correction: float = 1.0
@export var glow_strength: float = 0.28

@export_group("Floating Text")
@export var float_amp_y: float = 4.5
@export var float_amp_x: float = 2.2
@export var float_speed_y: float = 0.18
@export var float_speed_x: float = 0.13
@export var float_phase_offset: float = 0.5
@export var float_rot_amp: float = 0.005
@export var float_rot_speed: float = 0.06
@export_group("")

@export var reveal_speed: float = 10.0
@export var dropdown_padding: float = 12.0

const SPACE_MENU_SHADER := """
shader_type canvas_item;
uniform int glow_count = 0;
uniform vec2 glow_positions[32];
uniform vec4 base_glow_color : source_color = vec4(0.01, 0.04, 0.10, 1.0);
uniform vec4 ring_color : source_color = vec4(0.04, 0.16, 0.34, 1.0);
uniform vec4 secondary_ring_color : source_color = vec4(0.05, 0.28, 0.18, 1.0);
uniform vec4 foam_color : source_color = vec4(0.35, 0.70, 0.90, 0.45);
uniform vec4 nebula_a : source_color = vec4(0.006, 0.004, 0.018, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.004, 0.014, 0.032, 1.0);
uniform float bleed = 18.0;
uniform float ring_speed = 0.045;
uniform float secondary_ring_speed = 0.028;
uniform float foam_speed = 0.065;
uniform float foam_width = 0.012;
uniform float foam_wave_freq = 5.0;
uniform float foam_wave_amp = 0.014;
uniform float inv_aspect = 1.0;
uniform float circle_correction = 1.0;
uniform float glow_strength = 0.28;
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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.04 + vec2(1.7, 9.2);
		a *= 0.5;
	}
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
	float tw = 0.6 + 0.4 * sin(time * (1.2 + k * 3.5) + k * 45.0);
	float core = smoothstep(size, 0.0, r) * tw;
	float halo = smoothstep(size * 4.5, 0.0, r) * 0.10;
	float cross = (smoothstep(0.010, 0.0, abs(d.y)) * smoothstep(0.38, 0.0, abs(d.x))
	             + smoothstep(0.010, 0.0, abs(d.x)) * smoothstep(0.38, 0.0, abs(d.y))) * spikes * k;
	vec3 tint = mix(vec3(0.55, 0.80, 1.0), vec3(1.0, 0.95, 0.85), hash21(id + seed + 11.3));
	tint = mix(tint, vec3(0.45, 1.0, 0.65), smoothstep(0.8, 1.0, k) * 0.35);
	return tint * (core * (0.75 + 1.6 * k) + halo + cross * 0.55);
}

void fragment() {
	vec2 aspect_uv = vec2(UV.x / max(inv_aspect, 0.001), UV.y);
	float n1 = fbm(aspect_uv * 1.6 + vec2(time * 0.008, -time * 0.005));
	float n2 = fbm(aspect_uv * 3.2 - vec2(time * 0.01, time * 0.006) + 4.2);
	vec3 col = mix(nebula_a.rgb, nebula_b.rgb, n1);
	col += vec3(0.01, 0.03, 0.06) * pow(n1 * n2, 2.0);

	vec2 warp = vec2(0.0);
	vec3 ripple_col = vec3(0.0);

	for (int i = 0; i < glow_count; i++) {
		vec2 diff = UV - glow_positions[i];
		diff.x *= inv_aspect * circle_correction;
		float dist = length(diff);

		warp += normalize(diff + vec2(0.0001)) * exp(-dist * 12.0) * 0.0025 * sin(dist * 28.0 - time * 2.5);

		float central = exp(-dist * 7.5) * 0.22;
		ripple_col += base_glow_color.rgb * central;

		for (int j = 0; j < 2; j++) {
			float t = fract(time * ring_speed + float(j) * 0.5);
			float radius = t * 0.42 + 0.08;
			float envelope = sin(t * PI);
			float d = abs(dist - radius);
			float ring = exp(-d * bleed) * 0.07 * envelope;
			ripple_col += ring_color.rgb * ring;
		}

		float t2 = fract(time * secondary_ring_speed + 0.35);
		float r2 = t2 * 0.38 + 0.12;
		ripple_col += secondary_ring_color.rgb * exp(-abs(dist - r2) * bleed * 0.85) * 0.06 * sin(t2 * PI);

		float point_phase = hash21(vec2(float(i), 1.0)) * 6.28318;
		float tf = fract(time * foam_speed + point_phase * 0.1);
		float rf = mix(0.05, 0.45, tf) + foam_wave_amp * sin(atan(diff.y, diff.x) * foam_wave_freq + time * 2.0 + point_phase);
		float line = exp(-pow(abs(dist - rf) / foam_width, 2.0));
		ripple_col += foam_color.rgb * line * sin(tf * PI) * 0.16;
	}

	ripple_col = min(ripple_col * glow_strength, vec3(0.11, 0.16, 0.22));

	vec2 star_uv = aspect_uv + warp;
	vec3 stars = vec3(0.0);
	stars += star_layer(star_uv + vec2(time * 0.003, 0.0), 55.0, 0.958, 0.085, 1.0, 0.0);
	stars += star_layer(star_uv + vec2(time * 0.006, -time * 0.002), 115.0, 0.970, 0.070, 17.3, 0.0) * 0.75;
	stars += star_layer(star_uv + vec2(time * 0.0015, time * 0.001), 26.0, 0.986, 0.050, 53.7, 1.0) * 1.35;

	col += ripple_col + stars;

	float vig = smoothstep(0.95, 0.25, length((UV - 0.5) * vec2(1.15, 1.0)));
	col *= mix(0.45, 1.0, vig);

	float scanline = 0.96 + 0.04 * sin(FRAGCOORD.y * 2.2 + time * 4.0);
	col *= scanline;

	COLOR = vec4(col, 1.0);
}
"""

var font: Font
var font_size: int = 40
var line_height: int = 50
var padding: float = 30.0

var section_names: Array[String] = ["GAMEPLAY", "AUDIO", "GRAPHICS", "CONTROLS"]
var selected_section: int = 0
var focus_on_sections: bool = false

var current_page: String = "gameplay"
var selected_index: int = 0
var entries: Array[Dictionary] = []

var awaiting_input: bool = false
var rebinding_action: String = ""
var _display_mode_seen := ""
var binding_mode: bool = false

var confirming_exit: bool = false
var confirm_selected: int = 0
var confirm_rects: Array[Rect2] = []

var dropdown_open: bool = false
var dropdown_options: Array = []
var dropdown_selected: int = 0
var dropdown_target: String = ""
var dropdown_anchor: Vector2 = Vector2.ZERO
var dropdown_parent_index: int = 0

var dragging_slider: bool = false
var using_mouse: bool = false

var focus_on_bottom: bool = false
var selected_bottom_index: int = 0
var bottom_actions: Array[String] = ["SAVE", "BACK", "RESET ALL"]

var scroll_offset: int = 0
var max_visible_rows: int = 0

var reveal: float = 0.0
var animate_reveal: bool = false

var bg_layer: ColorRect
var glow_layer: ColorRect
var glow_positions: Array[Vector2] = []
var time: float = 0.0
var text_float_index: int = 0

var _fallback_settings: Node = null

func _gs() -> Node:
	var g := get_node_or_null("/root/GameSettings")
	if g != null:
		return g
	if _fallback_settings == null:
		var script_res := load("res://scripts/autoloads/GameSettings.gd")
		if script_res != null:
			_fallback_settings = script_res.new()
			_fallback_settings.name = "GameSettings"
			get_tree().root.add_child.call_deferred(_fallback_settings)
	return _fallback_settings

func _get_setting(key: String, default_val: Variant) -> Variant:
	var gs := _gs()
	if gs != null and "settings" in gs:
		return gs.settings.get(key, default_val)
	return default_val

func _set_setting(key: String, val: Variant) -> void:
	var gs := _gs()
	if gs != null and "settings" in gs:
		gs.settings[key] = val
		gs.dirty = true
		if gs.has_method("apply_settings"):
			gs.apply_settings()

func _is_dirty() -> bool:
	var gs := _gs()
	if gs != null and "dirty" in gs:
		return gs.dirty
	return false

func _set_dirty(val: bool) -> void:
	var gs := _gs()
	if gs != null and "dirty" in gs:
		gs.dirty = val

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	InputSupport.device_changed.connect(_on_input_device_changed)
	clip_contents = false

	_gs()

	set_meta("no_polish", true)
	font = load("res://resources/fonts/Monospace.ttf")
	if font == null:
		push_warning("options: failed to load font, using fallback")
		font = ThemeDB.fallback_font
	_create_background_layer()
	_create_glow_layer()

	_build_gameplay_page()
	reveal = 0.0
	animate_reveal = true
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()

func _create_background_layer() -> void:
	bg_layer = ColorRect.new()
	bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.color = bg_color
	bg_layer.z_index = -3
	add_child(bg_layer)

func _create_glow_layer() -> void:
	glow_layer = ColorRect.new()
	glow_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_layer.color = Color(0, 0, 0, 0)
	glow_layer.z_index = -1

	var shader := Shader.new()
	shader.code = SPACE_MENU_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	glow_layer.material = mat
	add_child(glow_layer)

func _process(delta: float) -> void:
	var actual := str(_get_setting("window_mode", "Windowed"))
	if actual != _display_mode_seen:
		_display_mode_seen = actual
		if current_page == "graphics" and not dropdown_open:
			_build_graphics_page()
	time += delta
	if animate_reveal and reveal < 1.0:
		reveal = minf(reveal + delta * reveal_speed, 1.0)
		queue_redraw()
	elif animate_reveal and reveal >= 1.0:
		animate_reveal = false

	queue_redraw()

	if glow_layer:
		var mat := glow_layer.material as ShaderMaterial
		mat.set_shader_parameter("time", time)

func _on_resized() -> void:
	var vs := get_viewport_rect().size
	var base := minf(vs.x, vs.y)
	font_size = clampi(int(base * 0.05), 28, 48)
	line_height = int(font_size * 1.3)
	padding = font_size

	var top_area := padding + line_height * 2
	var bottom_area := line_height * 2
	var available_height := size.y - top_area - bottom_area
	max_visible_rows = maxi(1, int(available_height / line_height))

	_update_scroll_range()
	queue_redraw()

func _update_scroll_range() -> void:
	var max_scroll := maxi(0, entries.size() - max_visible_rows)
	scroll_offset = clampi(scroll_offset, 0, max_scroll)

func _compute_float(phase: float) -> Vector3:
	var y_offset := sin(time * float_speed_y * TAU + phase) * float_amp_y + sin(time * float_speed_y * 1.7 + phase * 2.0) * float_amp_y * 0.4
	var x_offset := sin(time * float_speed_x * TAU + phase * 0.7) * float_amp_x + cos(time * float_speed_x * 1.3 + phase) * float_amp_x * 0.5
	var rot_offset := sin(time * float_rot_speed * TAU + phase) * float_rot_amp
	return Vector3(x_offset, y_offset, rot_offset)

func _get_entry_float_index(index: int) -> int:
	return section_names.size() + (index - scroll_offset)

func _draw() -> void:
	text_float_index = 0
	glow_positions.clear()

	var y := padding
	var total_width := size.x - 2.0 * padding
	var num_sections := section_names.size()
	for i in range(num_sections):
		var section_text := section_names[i]
		if i == selected_section:
			section_text = "[ " + section_text + " ]"
		else:
			section_text = "  " + section_text + "  "
		var col := highlight_color if i == selected_section else text_color
		var text_width := font.get_string_size(section_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var center_x := padding + total_width * (i + 0.5) / num_sections
		var pos := Vector2(center_x - text_width / 2.0, y + font.get_ascent(font_size))
		_draw_text(pos, section_text, col)

	var options_start_y := padding + line_height * 2
	var end_idx := mini(scroll_offset + max_visible_rows, entries.size())
	for i in range(scroll_offset, end_idx):
		var line_y := options_start_y + (i - scroll_offset) * line_height
		var layout := _get_entry_layout(i, line_y)
		var line_text: String = layout["text"]
		var is_rebind_target = binding_mode and i == selected_index and entries[i].action == "rebind"
		var col := highlight_color if layout["active"] else text_color
		if is_rebind_target:
			col = accent_cyan
		var display_text := line_text
		if animate_reveal:
			var visible_chars := int(reveal * line_text.length())
			display_text = line_text.substr(0, visible_chars)
		_draw_text(Vector2(padding, line_y + font.get_ascent(font_size)), display_text, col)

	_draw_bottom_actions()

	if binding_mode:
		_draw_binding_prompt()

	if dropdown_open:
		_draw_dropdown()

	if confirming_exit:
		_draw_confirm_dialog()

	_update_glow_shader()

func _draw_binding_prompt() -> void:
	var friendly_name := rebinding_action.replace("_", " ").capitalize()
	var line1 := "Press any button to bind it to %s" % friendly_name
	var line2 := "Press ESC to cancel, press DELETE to remove last input"

	var box_width := minf(size.x * 0.45, 520.0)
	var box_padding := dropdown_padding * 2.0
	var max_line_width := box_width - 2.0 * box_padding
	var wrapped_lines: Array[String] = []
	wrapped_lines.append_array(_wrap_text(line1, max_line_width))
	wrapped_lines.append_array(_wrap_text(line2, max_line_width))

	var total_lines := wrapped_lines.size()
	var box_height := total_lines * line_height + box_padding * 2.0

	var box_x := size.x - box_width - padding
	var box_y := size.y - line_height * 2 - box_height - padding
	var prompt_phase := _get_entry_float_index(selected_index) * float_phase_offset
	var f := _compute_float(prompt_phase)

	draw_set_transform(Vector2(f.x, f.y), f.z, Vector2.ONE)

	var rect := Rect2(box_x, box_y, box_width, box_height)
	draw_rect(rect, Color(0.01, 0.02, 0.05, 0.96))
	draw_rect(rect, highlight_color, false, 2.0)

	for idx in range(total_lines):
		var line_y_pos := box_y + box_padding + idx * line_height + font.get_ascent(font_size)
		var text_pos := Vector2(box_x + box_padding, line_y_pos)
		draw_string(font, text_pos, wrapped_lines[idx], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, highlight_color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _wrap_text(text: String, max_width: float) -> Array[String]:
	var words := text.split(" ", false)
	var lines: Array[String] = []
	var current_line := ""
	for w in words:
		var test_line := current_line + (" " if current_line != "" else "") + w
		var w_width := font.get_string_size(test_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w_width > max_width and current_line != "":
			lines.append(current_line)
			current_line = w
		else:
			current_line = test_line
	if current_line != "":
		lines.append(current_line)
	if lines.is_empty():
		lines.append(text)
	return lines

func _draw_bottom_actions() -> void:
	var bottom_y := size.y - line_height * 2
	var gap := font_size * 5
	var x := padding

	for i in range(bottom_actions.size()):
		var action_text := bottom_actions[i]
		var is_selected := focus_on_bottom and i == selected_bottom_index

		var display_text := ("> " if is_selected else "  ") + action_text
		var drawn_text := display_text
		if animate_reveal:
			var visible_chars := int(reveal * display_text.length())
			drawn_text = display_text.substr(0, visible_chars)

		var col: Color
		if action_text == "SAVE":
			if is_selected or _is_dirty():
				col = highlight_color
			else:
				col = dim_color
		else:
			col = highlight_color if is_selected else text_color

		_draw_text(Vector2(x, bottom_y + font.get_ascent(font_size)), drawn_text, col)
		x += font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + gap

func _draw_text_with_phase(pos: Vector2, text: String, color: Color, phase: float) -> void:
	var f := _compute_float(phase)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_center := pos + Vector2(f.x, f.y) + Vector2(text_size.x / 2.0, -text_size.y / 2.0)

	draw_set_transform(text_center, f.z, Vector2.ONE)
	draw_string(font, -Vector2(text_size.x / 2.0, -text_size.y / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	glow_positions.append(text_center)

func _draw_text(pos: Vector2, text: String, color: Color) -> void:
	var phase := text_float_index * float_phase_offset
	_draw_text_with_phase(pos, text, color, phase)
	text_float_index += 1

func _get_dropdown_rect() -> Rect2:
	var dd_x := dropdown_anchor.x
	var dd_y := dropdown_anchor.y
	var max_width := 0.0
	for i in range(dropdown_options.size()):
		var display_val := str(dropdown_options[i])
		if dropdown_target == "max_fps" and int(dropdown_options[i]) == 0:
			display_val = "Uncapped"
		var prefix := "> " if i == dropdown_selected else "  "
		var w := font.get_string_size(prefix + display_val, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w > max_width:
			max_width = w

	var dd_width := minf(max_width + 2.0 * dropdown_padding, size.x - dd_x - padding)
	var dd_height := dropdown_options.size() * line_height + 2.0 * dropdown_padding
	return Rect2(dd_x, dd_y, dd_width, dd_height)

func _draw_dropdown() -> void:
	var parent_phase := _get_entry_float_index(dropdown_parent_index) * float_phase_offset
	var f := _compute_float(parent_phase)
	var dd_rect := _get_dropdown_rect()

	draw_set_transform(Vector2(f.x, f.y), f.z, Vector2.ONE)
	draw_rect(Rect2(dd_rect.position, dd_rect.size), Color(0.01, 0.015, 0.04, 0.98))
	draw_rect(Rect2(dd_rect.position, dd_rect.size), highlight_color, false, 2.0)

	for i in range(dropdown_options.size()):
		var prefix := "> " if i == dropdown_selected else "  "
		var display_val := str(dropdown_options[i])
		if dropdown_target == "max_fps" and int(dropdown_options[i]) == 0:
			display_val = "Uncapped"
		var col := highlight_color if i == dropdown_selected else text_color
		var text_pos := Vector2(
			dd_rect.position.x + dropdown_padding,
			dd_rect.position.y + dropdown_padding + i * line_height + font.get_ascent(font_size)
		)
		draw_string(font, text_pos, prefix + display_val, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _update_glow_shader() -> void:
	if glow_layer == null:
		return
	var mat := glow_layer.material as ShaderMaterial
	var vs := get_viewport_rect().size
	var count := mini(glow_positions.size(), 32)
	mat.set_shader_parameter("glow_count", count)
	var pos_array := []
	for i in range(count):
		pos_array.append(Vector2(glow_positions[i].x / maxf(vs.x, 1.0), glow_positions[i].y / maxf(vs.y, 1.0)))
	for i in range(count, 32):
		pos_array.append(Vector2.ZERO)
	mat.set_shader_parameter("glow_positions", pos_array)
	mat.set_shader_parameter("base_glow_color", base_glow_color)
	mat.set_shader_parameter("ring_color", ring_color)
	mat.set_shader_parameter("secondary_ring_color", secondary_ring_color)
	mat.set_shader_parameter("foam_color", foam_color)
	mat.set_shader_parameter("nebula_a", nebula_a)
	mat.set_shader_parameter("nebula_b", nebula_b)
	mat.set_shader_parameter("bleed", bleed)
	mat.set_shader_parameter("ring_speed", ring_speed)
	mat.set_shader_parameter("secondary_ring_speed", secondary_ring_speed)
	mat.set_shader_parameter("foam_speed", foam_speed)
	mat.set_shader_parameter("foam_width", foam_width)
	mat.set_shader_parameter("foam_wave_freq", foam_wave_freq)
	mat.set_shader_parameter("foam_wave_amp", foam_wave_amp)
	mat.set_shader_parameter("circle_correction", circle_correction)
	mat.set_shader_parameter("glow_strength", glow_strength)
	mat.set_shader_parameter("inv_aspect", vs.y / maxf(vs.x, 1.0))

func _draw_confirm_dialog() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.90))
	var prompt := "Unsaved telemetry changes! Confirm action:"
	var options := ["Save & Exit", "Exit Without Saving", "Cancel"]
	var px := padding
	var py := size.y * 0.3
	_draw_text(Vector2(px, py + font.get_ascent(font_size)), prompt, accent_cyan)
	confirm_rects.clear()
	var y := py + line_height * 1.5
	for i in range(options.size()):
		var col := highlight_color if i == confirm_selected else text_color
		_draw_text(Vector2(px, y + font.get_ascent(font_size)), ("> " if i == confirm_selected else "  ") + options[i], col)
		confirm_rects.append(Rect2(px, y, size.x - px * 2.0, line_height))
		y += line_height

func _build_gameplay_page() -> void:
	current_page = "gameplay"
	entries.clear()
	entries.append({"text": _bool_text("Particles", _get_setting("particles", true)), "action": "toggle", "param": "particles"})
	entries.append({"text": _bool_text("Low Detail", _get_setting("low_detail", false)), "action": "toggle", "param": "low_detail"})
	scroll_offset = 0
	_update_scroll_range()
	queue_redraw()

func _build_audio_page() -> void:
	current_page = "audio"
	entries.clear()
	entries.append(_slider_entry("Master Volume", "master_volume", 0, 100))
	entries.append(_slider_entry("SFX Volume", "sfx_volume", 0, 100))
	entries.append(_slider_entry("Music Volume", "music_volume", 0, 100))
	scroll_offset = 0
	_update_scroll_range()
	queue_redraw()

func _build_graphics_page() -> void:
	current_page = "graphics"
	entries.clear()
	# VSync + FPS — always visible, including web
	entries.append({"text": _bool_text("VSync", _get_setting("vsync", true)), "action": "toggle", "param": "vsync"})
	entries.append(_cycle_entry("Max FPS", "max_fps", [0, 30, 60, 120, 144, 240]))
	entries.append(_cycle_entry("MSAA", "msaa", ["Off", "2x", "4x", "8x"]))
	entries.append(_slider_entry("Brightness", "brightness", 20, 200))
	# Desktop-only: resolution + window mode
	if InputSupport.desktop_window_controls():
		entries.append(_cycle_entry("Resolution", "resolution", ["1280x720", "1600x900", "1920x1080", "2560x1440"]))
		entries.append(_cycle_entry("Window Mode", "window_mode", ["Windowed", "Fullscreen", "Borderless"]))
	scroll_offset = 0
	_update_scroll_range()
	queue_redraw()
func _build_controls_page() -> void:
	current_page = "controls"
	entries.clear()
	var actions := _get_custom_actions()
	if actions.is_empty():
		entries.append({"text": "No custom actions found", "action": "back"})
	else:
		for action in actions:
			var bindings_display := _get_action_bindings_display(action)
			var friendly_name := action.replace("_", " ").capitalize()
			entries.append({
				"text": "%s: %s" % [friendly_name, bindings_display],
				"action": "rebind",
				"param": action
			})
	entries.append({"text": "Reset Keybinds", "action": "reset_keys"})
	_update_scroll_range()
	queue_redraw()

func _get_action_bindings_display(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "[None]"
	var parts := []
	for e in events:
		var label := _get_event_display(e)
		if label != "":
			parts.append("[%s]" % label)
	if parts.is_empty():
		return "[None]"
	return " ".join(parts)

func _get_event_display(event: InputEvent) -> String:
	if event is InputEventKey:
		var kc = event.keycode
		if kc == KEY_NONE and event.physical_keycode != KEY_NONE:
			# keyboard_get_keycode_from_physical is NOT implemented on Web or headless.
			var ds := DisplayServer.get_name()
			if ds == "headless" or ds == "web" or OS.has_feature("web"):
				kc = event.physical_keycode
			else:
				kc = DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
		return OS.get_keycode_string(kc)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			_: return "Mouse " + str(event.button_index)
	elif event is InputEventJoypadButton:
		return "%s (Joypad)" % _get_joypad_button_name(event.button_index)
	elif event is InputEventJoypadMotion:
		var axis_name := _get_joypad_axis_name(event.axis)
		var sgn := " +" if event.axis_value > 0 else " -"
		return "%s%s" % [axis_name, sgn]
	return ""
func _get_joypad_button_name(button: int) -> String:
	match button:
		0: return "A"
		1: return "B"
		2: return "X"
		3: return "Y"
		4: return "L1"
		5: return "R1"
		6: return "L2"
		7: return "R2"
		8: return "Back"
		9: return "Start"
		10: return "L3"
		11: return "R3"
		12: return "D-Pad Up"
		13: return "D-Pad Down"
		14: return "D-Pad Left"
		15: return "D-Pad Right"
		16: return "Guide"
		_: return "Button %d" % button

func _get_joypad_axis_name(axis: int) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return "Left Stick X"
		JOY_AXIS_LEFT_Y: return "Left Stick Y"
		JOY_AXIS_RIGHT_X: return "Right Stick X"
		JOY_AXIS_RIGHT_Y: return "Right Stick Y"
		JOY_AXIS_TRIGGER_LEFT: return "Left Trigger"
		JOY_AXIS_TRIGGER_RIGHT: return "Right Trigger"
		_: return "Axis %d" % axis

func _rebuild_current_page() -> void:
	var old_index := selected_index
	var old_scroll := scroll_offset
	match current_page:
		"gameplay": _build_gameplay_page()
		"audio": _build_audio_page()
		"graphics": _build_graphics_page()
		"controls": _build_controls_page()
		_: _build_gameplay_page()
	selected_index = clampi(old_index, 0, maxi(0, entries.size() - 1))
	var max_scroll := maxi(0, entries.size() - max_visible_rows)
	scroll_offset = clampi(old_scroll, 0, max_scroll)
	_update_scroll_range()
	queue_redraw()

func _open_section(idx: int) -> void:
	selected_section = idx
	selected_index = 0
	scroll_offset = 0
	focus_on_sections = false
	focus_on_bottom = false
	reveal = 0.0
	animate_reveal = true
	match idx:
		0: _build_gameplay_page()
		1: _build_audio_page()
		2: _build_graphics_page()
		3: _build_controls_page()
	queue_redraw()

func _get_entry_layout(i: int, line_y: float) -> Dictionary:
	var is_active := (i == selected_index and not focus_on_sections and not focus_on_bottom)
	var prefix := "> " if is_active else "  "
	var full_text: String = prefix + entries[i].text
	var layout := {
		"y": line_y,
		"x": padding,
		"text": full_text,
		"active": is_active,
		"param": entries[i].get("param", ""),
		"min": entries[i].get("min", 0),
		"max": entries[i].get("max", 100)
	}
	if entries[i].action == "adjust":
		var bracket_open := full_text.find("[")
		var bracket_close := full_text.find("]", bracket_open + 1)
		if bracket_open != -1 and bracket_close != -1:
			var label_before_open := full_text.substr(0, bracket_open)
			var label_before_close := full_text.substr(0, bracket_close + 1)
			var start_x := padding + font.get_string_size(label_before_open, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var end_x := padding + font.get_string_size(label_before_close, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var bracket_width := font.get_string_size("[", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var bar_start_x := start_x + bracket_width
			var bar_end_x := end_x - bracket_width
			layout["bar_start_x"] = bar_start_x
			layout["bar_end_x"] = bar_end_x
			layout["bar_rect"] = Rect2(bar_start_x, line_y, bar_end_x - bar_start_x, line_height)
	return layout

func _line_index_from_pos(pos: Vector2) -> int:
	if pos.y >= size.y - line_height * 2:
		return -1
	var options_start_y := padding + line_height * 2
	var rel_y := pos.y - options_start_y
	if rel_y < 0 or rel_y >= max_visible_rows * line_height:
		return -1
	var visible_index := int(rel_y / line_height)
	var actual_index := scroll_offset + visible_index
	if actual_index < 0 or actual_index >= entries.size():
		return -1
	if pos.x < padding or pos.x > size.x - padding:
		return -1
	return actual_index

func _section_index_from_pos(pos: Vector2) -> int:
	if pos.y < 0 or pos.y > line_height * 2:
		return -1
	var total_width := size.x - 2.0 * padding
	var num_sections := section_names.size()
	for i in range(num_sections):
		var section_text := section_names[i]
		if i == selected_section:
			section_text = "[ " + section_text + " ]"
		else:
			section_text = "  " + section_text + "  "
		var text_width := font.get_string_size(section_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var center_x := padding + total_width * (i + 0.5) / num_sections
		if pos.x >= center_x - text_width / 2.0 and pos.x <= center_x + text_width / 2.0:
			return i
	return -1

func _bottom_action_index(pos: Vector2) -> int:
	if pos.y < size.y - line_height * 2 or pos.y >= size.y - line_height:
		return -1
	var x := padding
	var gap := font_size * 5
	for i in range(bottom_actions.size()):
		var display_text := ("> " if focus_on_bottom and i == selected_bottom_index else "  ") + bottom_actions[i]
		var width := font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var segment_width := width + gap
		if pos.x >= x and pos.x < x + segment_width:
			return i
		x += segment_width
	return -1

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F11:
		return # reserved global shortcut, never bind it as a gameplay key
	if not binding_mode and not awaiting_input:
		event = InputSupport.menu_event(event)
	if confirming_exit:
		_input_confirm(event)
		return
	if dropdown_open:
		_input_dropdown(event)
		return
	if binding_mode:
		_input_binding(event)
		return
	if awaiting_input:
		_input_rebind(event)
		return

	if event is InputEventMouseMotion:
		using_mouse = true
		if dragging_slider:
			_handle_mouse_motion(event.position)
		else:
			var idx := _line_index_from_pos(event.position)
			if idx != -1:
				selected_index = idx
				focus_on_sections = false
				focus_on_bottom = false
				queue_redraw()
			else:
				var bottom_idx := _bottom_action_index(event.position)
				if bottom_idx != -1:
					selected_bottom_index = bottom_idx
					focus_on_bottom = true
					focus_on_sections = false
					queue_redraw()
	elif event is InputEventMouseButton:
		if event.pressed:
			using_mouse = true
			if event.button_index == MOUSE_BUTTON_LEFT:
				var bottom_idx := _bottom_action_index(event.position)
				if bottom_idx != -1:
					_handle_bottom_action(bottom_idx)
					return

				if event.position.y < line_height * 2:
					var sec_idx := _section_index_from_pos(event.position)
					if sec_idx != -1:
						selected_section = sec_idx
						_open_section(selected_section)
						queue_redraw()
					return

				var idx := _line_index_from_pos(event.position)
				if idx >= 0 and idx < entries.size():
					selected_index = idx
					focus_on_sections = false
					focus_on_bottom = false
					var entry := entries[idx]
					if entry.action == "adjust":
						var line_y := padding + line_height * 2 + (idx - scroll_offset) * line_height
						var base_rect := _get_base_bar_rect(idx, line_y)
						if base_rect.size.x > 0:
							var float_offset := _get_float_offset_for_entry(idx)
							var actual_rect := Rect2(base_rect.position + float_offset, base_rect.size).grow(5)
							if actual_rect.has_point(event.position):
								dragging_slider = true
								_handle_mouse_motion(event.position)
							else:
								_activate_selected()
						else:
							_activate_selected()
					else:
						_activate_selected()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				if scroll_offset > 0:
					scroll_offset -= 1
					_update_scroll_range()
					queue_redraw()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				var max_scroll := maxi(0, entries.size() - max_visible_rows)
				if scroll_offset < max_scroll:
					scroll_offset += 1
					_update_scroll_range()
					queue_redraw()
		else:
			if event.button_index == MOUSE_BUTTON_LEFT and dragging_slider:
				dragging_slider = false
				# Apply the new value once, now that the drag is over.
				var gs := _gs()
				if gs != null and gs.has_method("apply_settings"):
					gs.apply_settings()
	elif event is InputEventKey and event.pressed:
		using_mouse = false
		match event.keycode:
			KEY_UP, KEY_W: _navigate_up()
			KEY_DOWN, KEY_S: _navigate_down()
			KEY_LEFT, KEY_A: _navigate_left()
			KEY_RIGHT, KEY_D: _navigate_right()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if not event.echo:
					_activate_focused()
			KEY_ESCAPE:
				if not event.echo:
					_back()

func _navigate_up() -> void:
	if focus_on_sections:
		selected_section = (selected_section - 1 + section_names.size()) % section_names.size()
	elif focus_on_bottom:
		focus_on_bottom = false
		focus_on_sections = false
		selected_index = mini(entries.size() - 1, scroll_offset + max_visible_rows - 1)
	else:
		if selected_index > 0:
			selected_index -= 1
			if selected_index < scroll_offset:
				scroll_offset = selected_index
				_update_scroll_range()
		else:
			focus_on_sections = true
	queue_redraw()

func _navigate_down() -> void:
	if focus_on_sections:
		focus_on_sections = false
		selected_index = 0
	elif focus_on_bottom:
		selected_bottom_index = (selected_bottom_index + 1) % bottom_actions.size()
	else:
		if selected_index < entries.size() - 1:
			selected_index += 1
			if selected_index >= scroll_offset + max_visible_rows:
				scroll_offset = selected_index - max_visible_rows + 1
				_update_scroll_range()
		else:
			focus_on_bottom = true
			focus_on_sections = false
			selected_bottom_index = 0
	queue_redraw()

func _navigate_left() -> void:
	if focus_on_sections:
		selected_section = (selected_section - 1 + section_names.size()) % section_names.size()
		_open_section(selected_section)
	elif focus_on_bottom:
		selected_bottom_index = (selected_bottom_index - 1 + bottom_actions.size()) % bottom_actions.size()
	else:
		_adjust_option(-1)
	queue_redraw()

func _navigate_right() -> void:
	if focus_on_sections:
		selected_section = (selected_section + 1) % section_names.size()
		_open_section(selected_section)
	elif focus_on_bottom:
		selected_bottom_index = (selected_bottom_index + 1) % bottom_actions.size()
	else:
		_adjust_option(1)
	queue_redraw()

func _activate_focused() -> void:
	if focus_on_sections:
		_open_section(selected_section)
	elif focus_on_bottom:
		_handle_bottom_action(selected_bottom_index)
	else:
		_activate_selected()

func _handle_bottom_action(index: int) -> void:
	match bottom_actions[index]:
		"SAVE": _save_all()
		"BACK": _exit_action()
		"RESET ALL": _reset_all_action()

func _reset_all_action() -> void:
	var gs := _gs()
	if gs != null:
		if gs.has_method("reset_settings_to_default"): gs.reset_settings_to_default()
		if gs.has_method("save_settings"): gs.save_settings()
	_set_dirty(false)
	_rebuild_current_page()

func _reset_keys_action() -> void:
	var gs := _gs()
	if gs != null:
		if gs.has_method("reset_inputs_to_default"): gs.reset_inputs_to_default()
		if gs.has_method("save_player_input_map"): gs.save_player_input_map()
	else:
		InputMap.load_from_project_settings()
	_rebuild_current_page()

func _exit_action() -> void:
	if _is_dirty():
		confirming_exit = true
		confirm_selected = 0
		focus_on_sections = false
		focus_on_bottom = false
		queue_redraw()
	else:
		_exit_to_main_menu()

func _back() -> void:
	if binding_mode:
		binding_mode = false
		rebinding_action = ""
		_rebuild_current_page()
		return
	if awaiting_input:
		awaiting_input = false
		_rebuild_current_page()
		return
	if dropdown_open:
		dropdown_open = false
		_rebuild_current_page()
		return
	if focus_on_sections:
		_exit_action()
		return
	if focus_on_bottom:
		focus_on_bottom = false
		selected_index = mini(entries.size() - 1, scroll_offset + max_visible_rows - 1)
		queue_redraw()
		return
	focus_on_sections = true
	focus_on_bottom = false
	queue_redraw()

func _handle_mouse_motion(pos: Vector2) -> void:
	if not dragging_slider:
		return
	var line_y := padding + line_height * 2 + (selected_index - scroll_offset) * line_height
	var base_rect := _get_base_bar_rect(selected_index, line_y)
	if base_rect.size.x <= 0:
		return
	var float_offset := _get_float_offset_for_entry(selected_index)
	var actual_rect := Rect2(base_rect.position + float_offset, base_rect.size).grow(5)
	var ratio := clampf((pos.x - actual_rect.position.x) / actual_rect.size.x, 0.0, 1.0)
	var entry := entries[selected_index]
	# Do NOT call _set_setting during a drag — it triggers apply_settings()
	# 60 times per second, which re-walks the whole scene tree and can hit
	# freed nodes (GameSettings.gd:165 _apply_recursive crash).
	# Just update the dict; apply_settings runs once on release.
	var gs := _gs()
	if gs != null and "settings" in gs:
		gs.settings[entry.param] = int(entry.min + ratio * (entry.max - entry.min))
		gs.dirty = true
	_rebuild_current_page()

func _get_float_offset_for_entry(index: int) -> Vector2:
	var phase := _get_entry_float_index(index) * float_phase_offset
	var f := _compute_float(phase)
	return Vector2(f.x, f.y)

func _get_base_bar_rect(index: int, line_y: float) -> Rect2:
	var layout := _get_entry_layout(index, line_y)
	if layout.has("bar_rect"):
		return layout["bar_rect"]
	return Rect2()

func _input_confirm(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W:
				confirm_selected = (confirm_selected - 1 + 3) % 3
				queue_redraw()
			KEY_DOWN, KEY_S:
				confirm_selected = (confirm_selected + 1) % 3
				queue_redraw()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_confirm_execute(confirm_selected)
			KEY_ESCAPE:
				confirming_exit = false
				_rebuild_current_page()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(confirm_rects.size()):
			if confirm_rects[i].has_point(event.position):
				_confirm_execute(i)
				break
	elif event is InputEventMouseMotion:
		for i in range(confirm_rects.size()):
			if confirm_rects[i].has_point(event.position) and confirm_selected != i:
				confirm_selected = i
				queue_redraw()
				break

func _confirm_execute(index: int) -> void:
	match index:
		0:
			_save_all()
			_exit_to_main_menu()
		1:
			var gs := _gs()
			if gs != null:
				if gs.has_method("load_settings"): gs.load_settings()
				if gs.has_method("load_player_input_map"): gs.load_player_input_map()
				if gs.has_method("apply_settings"): gs.apply_settings()
			_set_dirty(false)
			_exit_to_main_menu()
		2:
			confirming_exit = false
			_rebuild_current_page()

func _input_binding(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			binding_mode = false
			rebinding_action = ""
			_rebuild_current_page()
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_remove_last_binding(rebinding_action)
			binding_mode = false
			rebinding_action = ""
			_rebuild_current_page()
		else:
			_add_binding(rebinding_action, event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_add_binding(rebinding_action, event)
	elif event is InputEventJoypadButton and event.pressed:
		_add_binding(rebinding_action, event)
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.5:
		var ev := InputEventJoypadMotion.new()
		ev.axis = event.axis
		ev.axis_value = 1.0 if event.axis_value > 0 else -1.0
		_add_binding(rebinding_action, ev)

func _add_binding(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if _events_equal(e, event):
			return
	InputMap.action_add_event(action, event)
	_set_dirty(true)
	binding_mode = false
	rebinding_action = ""
	_rebuild_current_page()

func _remove_last_binding(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var events := InputMap.action_get_events(action)
	if not events.is_empty():
		InputMap.action_erase_event(action, events[-1])
		_set_dirty(true)

func _events_equal(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.keycode == b.keycode and a.physical_keycode == b.physical_keycode
	elif a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	elif a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	elif a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
	return false

func _input_dropdown(event: InputEvent) -> void:
	var parent_phase := _get_entry_float_index(dropdown_parent_index) * float_phase_offset
	var f := _compute_float(parent_phase)
	var tf := Transform2D(f.z, Vector2(f.x, f.y))
	var inv_tf := tf.affine_inverse()

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W:
				dropdown_selected = (dropdown_selected - 1 + dropdown_options.size()) % dropdown_options.size()
				queue_redraw()
			KEY_DOWN, KEY_S:
				dropdown_selected = (dropdown_selected + 1) % dropdown_options.size()
				queue_redraw()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_set_setting(dropdown_target, dropdown_options[dropdown_selected])
				dropdown_open = false
				_rebuild_current_page()
			KEY_ESCAPE:
				dropdown_open = false
				_rebuild_current_page()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos = inv_tf * event.position
		var dd_rect := _get_dropdown_rect()
		if dd_rect.has_point(local_pos):
			var idx := int((local_pos.y - dd_rect.position.y - dropdown_padding) / line_height)
			if idx >= 0 and idx < dropdown_options.size():
				_set_setting(dropdown_target, dropdown_options[idx])
		dropdown_open = false
		_rebuild_current_page()
	elif event is InputEventMouseMotion:
		var local_pos = inv_tf * event.position
		var dd_rect := _get_dropdown_rect()
		if dd_rect.has_point(local_pos):
			var idx := int((local_pos.y - dd_rect.position.y - dropdown_padding) / line_height)
			if idx >= 0 and idx < dropdown_options.size() and idx != dropdown_selected:
				dropdown_selected = idx
				queue_redraw()

func _input_rebind(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			awaiting_input = false
			_rebuild_current_page()
			return
		_assign_action_event(rebinding_action, event)
	elif event is InputEventMouseButton and event.pressed:
		_assign_action_event(rebinding_action, event)
	elif event is InputEventJoypadButton and event.pressed:
		_assign_action_event(rebinding_action, event)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.65:
		_assign_action_event(rebinding_action, event)

func _assign_action_event(action: String, event: InputEvent) -> void:
	var events := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	for previous in events:
		var same_family := (event is InputEventKey and previous is InputEventKey) or (event is InputEventMouseButton and previous is InputEventMouseButton) or (event is InputEventJoypadButton and previous is InputEventJoypadButton) or (event is InputEventJoypadMotion and previous is InputEventJoypadMotion)
		if not same_family:
			InputMap.action_add_event(action, previous)
	_set_dirty(true)
	awaiting_input = false
	_rebuild_current_page()

func _activate_selected() -> void:
	if selected_index < 0 or selected_index >= entries.size():
		return
	var entry := entries[selected_index]
	match entry.action:
		"toggle":
			var key: String = entry.param
			_set_setting(key, not bool(_get_setting(key, false)))
			_rebuild_current_page()
		"cycle":
			dropdown_open = true
			dropdown_target = entry.param
			dropdown_options = entry.options
			dropdown_selected = maxi(0, entry.options.find(_get_setting(entry.param, entry.options[0])))
			dropdown_parent_index = selected_index
			var line_y := padding + line_height * 2 + (selected_index - scroll_offset) * line_height
			dropdown_anchor = Vector2(padding + 200, line_y + line_height)
			queue_redraw()
		"rebind":
			binding_mode = true
			rebinding_action = entry.param
			queue_redraw()
		"reset_keys":
			_reset_keys_action()

func _adjust_option(dir: int) -> void:
	if selected_index < 0 or selected_index >= entries.size():
		return
	var entry := entries[selected_index]
	if entry.action == "adjust":
		var key: String = entry.param
		var val := clampi(int(_get_setting(key, 0)) + dir * 5, int(entry.min), int(entry.max))
		_set_setting(key, val)
		_rebuild_current_page()
	elif entry.action == "cycle":
		var opts: Array = entry.options
		var current = _get_setting(entry.param, opts[0])
		var idx := opts.find(current)
		idx = (idx + dir + opts.size()) % opts.size()
		_set_setting(entry.param, opts[idx])
		_rebuild_current_page()

func _save_all() -> void:
	var gs := _gs()
	if gs != null:
		if gs.has_method("save_settings"): gs.save_settings()
		if gs.has_method("save_player_input_map"): gs.save_player_input_map()
		if gs.has_method("apply_settings"): gs.apply_settings()
	_set_dirty(false)
	_rebuild_current_page()

func _exit_to_main_menu() -> void:
	if has_meta("embedded_options") or (get_parent() != null and get_parent() != get_tree().root and get_tree().current_scene != self):
		queue_free()
	else:
		Transition.change_scene("res://scenes/main scenes/main_menu.tscn")

func _get_custom_actions() -> Array[String]:
	var result: Array[String] = []
	for action in InputMap.get_actions():
		if not str(action).begins_with("ui_") or str(action) in ["ui_left", "ui_right", "ui_up", "ui_down"]:
			result.append(str(action))
	return result

func _bool_text(label: String, value: bool) -> String:
	return "%s: [%s]" % [label, "X" if value else " "]

func _slider_entry(label: String, key: String, min_val: float, max_val: float) -> Dictionary:
	var value := int(_get_setting(key, min_val))
	var bar_str := _slider_bar(value, min_val, max_val)
	return {
		"text": "%s: [%s] %d" % [label, bar_str, value],
		"action": "adjust",
		"param": key,
		"min": min_val,
		"max": max_val,
		"label": label,
		"bar": bar_str
	}

func _cycle_entry(label: String, key: String, options: Array) -> Dictionary:
	var current = _get_setting(key, options[0])
	var display := "Uncapped" if key == "max_fps" and int(current) == 0 else str(current)
	return {"text": "%s: < %s >" % [label, display], "action": "cycle", "param": key, "options": options}

func _slider_bar(value: float, min_val: float, max_val: float, width: int = 20) -> String:
	var ratio := (value - min_val) / maxf(max_val - min_val, 1.0)
	var filled := int(ratio * width)
	return "=".repeat(clampi(filled, 0, width)) + "-".repeat(width - clampi(filled, 0, width))

func _on_input_device_changed() -> void:
	if current_page == "controls" and not binding_mode and not awaiting_input:
		_build_controls_page()
	queue_redraw()
