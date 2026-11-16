extends Control
## ENDING - plays after Day 5. Set Game node's `win_scene` to ending.tscn.
## Night -> sunrise over Mars, story lines type on, rescue ship descends, title slams in.

@export_group("Audio")
@export var ambient_audio: AudioStream
@export var audio_volume_db: float = -8.0
@export var typing_sfx: AudioStream
@export var typing_sfx_volume_db: float = -8.0
@export var title_sfx: AudioStream            ## plays when the title slams in
@export var ship_sfx: AudioStream             ## plays when the rescue ship appears

@export_group("Story")
@export var story_lines: Array[String] = [
	"The storms have passed.",
	"Every system held.",
	"Your distress beacon was answered.",
	"A rescue ship is on its way.",
]
@export var title_text: String = "YOU SURVIVED"
@export var subtitle_text: String = "All %d days on Mars complete"   ## %d = total days
@export var prompt_text: String = "PRESS ANY KEY"
@export var char_delay: float = 0.045
@export var line_hold: float = 1.3

@export_group("Look")
@export var title_color: Color = Color(1.0, 0.85, 0.35)
@export var text_color: Color = Color(0.85, 0.95, 1.0)
@export var accent_color: Color = Color(0.42, 1.0, 0.55)
@export var dawn_duration: float = 24.0

@export_group("Scene")
@export_file("*.tscn") var next_scene: String = "res://scenes/main scenes/main_menu.tscn"

const FONT_PATH := "res://resources/fonts/Monospace.ttf"

const SKY_SHADER := """
shader_type canvas_item;
uniform bool flat_quality = false;
uniform float dawn = 0.0;
uniform float ship_t = -1.0;
uniform float aspect = 1.7778;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 glow(vec2 p, vec2 c, float k) { float d = distance(p, c); return vec3(0.75, 0.92, 1.0) * k * (0.0007 / (d * d + 0.00025)); }
void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	if (flat_quality) {
		vec3 flat_col = uv.y > 0.80 ? vec3(0.18, 0.07, 0.04) : mix(vec3(0.008, 0.012, 0.035), vec3(0.30, 0.15, 0.12), dawn);
		if (ship_t >= 0.0) {
			vec2 ship = mix(vec2(0.98 * aspect, 0.04), vec2(0.82 * aspect, 0.30), clamp(ship_t, 0.0, 1.0));
			ship.y += sin(max(ship_t, 0.0) * 3.0) * 0.02;
			if (abs(p.x - ship.x) < 0.035 && abs(p.y - ship.y) < 0.012) { flat_col = vec3(0.75, 0.92, 1.0); }
		}
		COLOR = vec4(flat_col, 1.0);
	} else {
	float horizon = 0.80 + 0.018 * sin(uv.x * 6.0 + 1.0) + 0.01 * sin(uv.x * 19.0) + 0.006 * sin(uv.x * 43.0);
	vec3 night = mix(vec3(0.008, 0.012, 0.035), vec3(0.05, 0.035, 0.10), uv.y);
	vec3 morning = mix(vec3(0.06, 0.09, 0.22), vec3(1.0, 0.50, 0.22), pow(smoothstep(0.25, horizon, uv.y), 1.7));
	vec3 col = mix(night, morning, smoothstep(0.0, 1.0, dawn));
	// stars
	vec2 g = p * 70.0;
	vec2 id = floor(g);
	float h = hash(id);
	vec2 f = fract(g) - 0.5 - (vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5) * 0.6;
	float star = step(0.965, h) * smoothstep(0.22, 0.0, length(f)) * (0.6 + 0.4 * sin(TIME * (1.0 + h * 4.0) + h * 40.0));
	col += vec3(0.85, 0.92, 1.0) * star * (1.0 - dawn * 0.92) * smoothstep(horizon, 0.3, uv.y);
	// sun glow behind the ridge
	float sd = distance(vec2(p.x, uv.y * 1.6), vec2(0.40 * aspect, horizon * 1.6));
	col += vec3(1.0, 0.62, 0.26) * exp(-sd * 2.6) * dawn * 1.1;
	col += vec3(1.0, 0.9, 0.7) * exp(-sd * 12.0) * dawn * 0.9;
	// rescue ship descending with a trail
	if (ship_t >= 0.0) {
		vec2 a = vec2(0.98 * aspect, 0.04);
		vec2 b = vec2(0.82 * aspect, 0.30);   // hovers upper-right, clear of the text
		for (int i = 0; i < 10; i++) {
			float t = max(ship_t - float(i) * 0.02, 0.0);
			vec2 sp = mix(a, b, t);
			sp.y += sin(t * 3.0) * 0.02;
			col += glow(p, sp, (1.0 - float(i) * 0.09) * (i == 0 ? 1.0 : 0.35));
		}
	}
	// martian ground silhouette, rim-lit by the dawn
	if (uv.y > horizon) {
		float depth = (uv.y - horizon) / (1.0 - horizon);
		vec3 ground = mix(vec3(0.20, 0.08, 0.04) * dawn, vec3(0.012, 0.006, 0.006), smoothstep(0.0, 0.5, depth));
		ground += vec3(1.0, 0.45, 0.18) * exp(-depth * 40.0) * dawn * 0.55;
		col = ground;
	}
	col *= 1.0 - smoothstep(0.45, 1.0, distance(uv, vec2(0.5))) * 0.55;
	COLOR = vec4(col, 1.0);
	}
}
"""

var font: Font
var sky_mat: ShaderMaterial
var story: Label
var title_row: HBoxContainer
var sub: Label
var prompt: Label
var flash: ColorRect
var shade: TextureRect
var ready_for_input := false
var leaving := false
var _tick_player: AudioStreamPlayer

func _ready() -> void:
	font = load(FONT_PATH)
	if font == null:
		push_warning("ending: failed to load " + FONT_PATH + ", using fallback")
		font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# soft bloom, only for this scene
	GameSettings.set_hdr_preference(true)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 0.9
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.0
	we.environment = env
	add_child(we)

	var sky := ColorRect.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	GameSettings.quality_changed.connect(_apply_quality)
	_apply_quality()
	sky.material = sky_mat
	add_child(sky)

	# soft dark pool behind the text so it reads against the bright sunrise
	var sg := Gradient.new()
	sg.set_color(0, Color(0, 0, 0, 0.62))
	sg.set_color(1, Color(0, 0, 0, 0.0))
	var stex := GradientTexture2D.new()
	stex.gradient = sg
	stex.fill = GradientTexture2D.FILL_RADIAL
	stex.fill_from = Vector2(0.5, 0.5)
	stex.fill_to = Vector2(1.0, 0.5)
	stex.width = 256
	stex.height = 256
	shade = TextureRect.new()
	shade.texture = stex
	shade.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	shade.custom_minimum_size = Vector2(1500, 560)
	shade.offset_left = -750
	shade.offset_right = 750
	shade.offset_top = -280
	shade.offset_bottom = 280
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.modulate.a = 0.0
	add_child(shade)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	story = _lbl(30, text_color, 6)
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story.custom_minimum_size = Vector2(0, 50)
	vb.add_child(story)

	title_row = HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 0)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title_row)

	sub = _lbl(26, accent_color, 6)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.visible_ratio = 0.0
	vb.add_child(sub)

	prompt = _lbl(20, text_color, 6)
	prompt.text = prompt_text
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.modulate.a = 0.0
	vb.add_child(prompt)

	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	var fade := ColorRect.new()       # fade in from black
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	create_tween().tween_property(fade, "color:a", 0.0, 2.0)
	get_tree().create_timer(2.1).timeout.connect(fade.queue_free)

	if ambient_audio != null:
		var ap := AudioStreamPlayer.new()
		ap.stream = ambient_audio
		ap.volume_db = audio_volume_db
		add_child(ap)
		ap.play()
	_tick_player = AudioStreamPlayer.new()
	_tick_player.stream = typing_sfx
	_tick_player.volume_db = typing_sfx_volume_db
	add_child(_tick_player)

	create_tween().tween_method(func(v: float): sky_mat.set_shader_parameter("dawn", v), 0.0, 1.0, dawn_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_run()

func _lbl(size: int, col: Color, outline: int = 4) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0, 0.7)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _tick() -> void:
	if typing_sfx != null:
		_tick_player.pitch_scale = randf_range(0.95, 1.08)
		_tick_player.play()

func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _type(l: Label, text: String) -> void:
	create_tween().tween_property(shade, "modulate:a", 0.55, 0.6)
	l.text = text
	l.visible_characters = 0
	l.modulate.a = 1.0
	for i in text.length():
		l.visible_characters = i + 1
		if text[i] != " ":
			_tick()
		await get_tree().create_timer(char_delay).timeout

func _run() -> void:
	await get_tree().create_timer(2.4).timeout
	for i in story_lines.size():
		if i == story_lines.size() - 1:
			_play(ship_sfx)
			create_tween().tween_method(func(v: float): sky_mat.set_shader_parameter("ship_t", v), 0.0, 1.0, 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await _type(story, story_lines[i])
		await get_tree().create_timer(line_hold).timeout
		var fo := create_tween()
		fo.tween_property(story, "modulate:a", 0.0, 0.5)
		await fo.finished
	await get_tree().create_timer(1.2).timeout
	await _slam_title()
	sub.text = subtitle_text % GameManager.total_days if "%d" in subtitle_text else subtitle_text
	var st := create_tween()
	st.tween_property(sub, "visible_ratio", 1.0, 1.0)
	await st.finished
	await get_tree().create_timer(1.5).timeout
	var pt := create_tween()
	pt.tween_property(prompt, "modulate:a", 1.0, 0.6)
	await pt.finished
	var blink := prompt.create_tween().set_loops()
	blink.tween_property(prompt, "modulate:a", 0.3, 0.8)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.8)
	ready_for_input = true

func _slam_title() -> void:
	_play(title_sfx)
	create_tween().tween_property(shade, "modulate:a", 1.0, 0.8)
	var letters: Array[Label] = []
	var fsize := 120 if title_text.length() <= 8 else (96 if title_text.length() <= 13 else 76)
	for ch in title_text:
		var l := _lbl(fsize, Color(title_color.r * 1.25, title_color.g * 1.25, title_color.b * 1.25), 10)
		l.text = ch
		l.modulate = Color(3, 3, 3, 0)
		title_row.add_child(l)
		letters.append(l)
	await get_tree().process_frame
	for l in letters:
		l.pivot_offset = l.size * 0.5
		l.scale = Vector2(2.6, 2.6)
	flash.color.a = 0.8
	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "color:a", 0.0, 0.8)
	for i in letters.size():
		tw.tween_property(letters[i], "scale", Vector2.ONE, 0.5).set_delay(0.06 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(letters[i], "modulate", Color.WHITE, 0.5).set_delay(0.06 * i)
	await tw.finished

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_input or leaving:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		leaving = true
		var trans := get_node_or_null("/root/Transition")
		if trans != null:
			await trans.change_scene(next_scene, 1.5)
		else:
			get_tree().change_scene_to_file(next_scene)

func _apply_quality() -> void:
	if sky_mat != null:
		sky_mat.set_shader_parameter("flat_quality", GameSettings.ultra_enabled())

func _exit_tree() -> void:
	GameSettings.set_hdr_preference(false)
