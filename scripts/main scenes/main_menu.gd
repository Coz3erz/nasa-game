# CHANGELOG (2026-11-15): Persistent nonspatial menu music including embedded options, with offline synthesized fallback.
extends Control
## CRASHFALL title screen. Same space background as the options menu, floating text, digital look.
## PLAY and OPTIONS always show. HOW TO PLAY appears once the tutorial has been finished.
const OptionsScript := preload("res://scripts/main scenes/options.gd")
@export var game_title: String = "CRASHFALL"
@export_file("*.tscn") var play_scene: String = "res://scenes/main scenes/cutscene.tscn"
@export_file("*.tscn") var tutorial_scene: String = "res://scenes/main scenes/tutorial.tscn"
@export var options_scene: String = "res://scenes/main scenes/options.tscn"

const RED := Color(0.95, 0.12, 0.2)
const CYAN := Color(0.4, 0.92, 1.0)

var _items: Array[Dictionary] = []
var _rects: Array[Rect2] = []
var _sel := 0
var _t := 0.0
var _busy := false
var _in_options := false
var _options: Control
var _bg: ColorRect
var _glow: ColorRect
var _glow_pts: Array[Vector2] = []
var _glitch := 0.0
var _glitch_next := 2.5
var _blip: AudioStreamPlayer
var _font: Font
var _logo_font: Font

func _ready() -> void:
	GameAudio.set_menu_music(true)
	set_meta("no_polish", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = GameFont.get_font()
	_logo_font = load("res://resources/fonts/Cynatar.otf")
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0.005, 0.008, 0.02, 0.98)
	_bg.z_index = -3
	add_child(_bg)
	_glow = ColorRect.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.color = Color(0, 0, 0, 0)
	_glow.z_index = -1
	var sh := Shader.new()
	sh.code = OptionsScript.SPACE_MENU_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_glow.material = mat
	add_child(_glow)
	_blip = AudioStreamPlayer.new()
	_blip.bus = &"SFX"
	_blip.stream = SynthSfx.beep_wav()
	_blip.volume_db = -14.0
	add_child(_blip)
	_items.append({"label": "PLAY", "act": "play"})
	if SaveFlags.get_flag("tutorial_done"):
		_items.append({"label": "HOW TO PLAY", "act": "how"})
	_items.append({"label": "OPTIONS", "act": "options"})

# ------------------------------------------------------------------ float (same maths as the options menu)
func _float(phase: float) -> Vector2:
	var y := sin(_t * 0.18 * TAU + phase) * 4.5 + sin(_t * 0.18 * 1.7 + phase * 2.0) * 1.8
	var x := sin(_t * 0.13 * TAU + phase * 0.7) * 2.2 + cos(_t * 0.13 * 1.3 + phase) * 1.1
	return Vector2(x, y)

func _process(delta: float) -> void:
	_t += delta
	_glitch = maxf(0.0, _glitch - delta)
	_glitch_next -= delta
	if _glitch_next <= 0.0:
		_glitch = 0.22
		_glitch_next = randf_range(2.0, 5.0)
	if _in_options:
		return
	_push_shader()
	queue_redraw()

func _push_shader() -> void:
	var mat := _glow.material as ShaderMaterial
	var vs := get_viewport_rect().size
	var count := mini(_glow_pts.size(), 32)
	var arr := []
	for i in count:
		arr.append(Vector2(_glow_pts[i].x / maxf(vs.x, 1.0), _glow_pts[i].y / maxf(vs.y, 1.0)))
	for i in range(count, 32):
		arr.append(Vector2.ZERO)
	mat.set_shader_parameter("glow_count", count)
	mat.set_shader_parameter("glow_positions", arr)
	mat.set_shader_parameter("time", _t)
	mat.set_shader_parameter("base_glow_color", Color(0.01, 0.04, 0.10, 1.0))
	mat.set_shader_parameter("ring_color", Color(0.0268, 0.2236, 0.4553, 1.0))
	mat.set_shader_parameter("secondary_ring_color", Color(0.0954, 0.2607, 0.389, 1.0))
	mat.set_shader_parameter("foam_color", Color(0.0, 0.1938, 0.2316, 0.85))
	mat.set_shader_parameter("nebula_a", Color(0.006, 0.004, 0.018, 1.0))
	mat.set_shader_parameter("nebula_b", Color(0.004, 0.014, 0.032, 1.0))
	mat.set_shader_parameter("bleed", 18.0)
	mat.set_shader_parameter("ring_speed", 0.045)
	mat.set_shader_parameter("secondary_ring_speed", 0.028)
	mat.set_shader_parameter("foam_speed", 0.065)
	mat.set_shader_parameter("foam_width", 0.012)
	mat.set_shader_parameter("foam_wave_freq", 5.0)
	mat.set_shader_parameter("foam_wave_amp", 0.014)
	mat.set_shader_parameter("circle_correction", 1.0)
	mat.set_shader_parameter("glow_strength", 0.28)
	mat.set_shader_parameter("inv_aspect", vs.y / maxf(vs.x, 1.0))

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	if _in_options:
		return
	var vs := size
	var base := minf(vs.x, vs.y)
	var fs := clampi(int(base * 0.06), 26, 52)
	var tfs := clampi(int(base * 0.19), 60, 170)
	var lx := vs.x * 0.09
	_glow_pts.clear()
	_rects.clear()

	# corner brackets
	var m := 28.0
	var bl := 46.0
	for c in [Vector2(m, m), Vector2(vs.x - m, m), Vector2(m, vs.y - m), Vector2(vs.x - m, vs.y - m)]:
		var sx: float = 1.0 if c.x < vs.x * 0.5 else -1.0
		var sy: float = 1.0 if c.y < vs.y * 0.5 else -1.0
		draw_line(c, c + Vector2(bl * sx, 0), Color(CYAN, 0.55), 2.0)
		draw_line(c, c + Vector2(0, bl * sy), Color(CYAN, 0.55), 2.0)

	# title
	var tf := _float(0.0) * 1.8
	tfs = mini(tfs, int((vs.x - lx * 2.0) / maxf(_logo_font.get_string_size(game_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 1).x, 0.01)))
	var tsize := _logo_font.get_string_size(game_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs)
	var tpos := Vector2(lx, vs.y * 0.37) + tf
	var g := _glitch / 0.22
	var jitter := Vector2(randf_range(-9.0, 9.0) * g, 0.0)
	draw_string(_logo_font, tpos + Vector2(6, 5), game_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0, 0, 0, 0.75))
	draw_string(_logo_font, tpos + Vector2(-5.0 - 8.0 * g, 2.0), game_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(RED, 0.8))
	draw_string(_logo_font, tpos + Vector2(5.0 + 8.0 * g, -2.0), game_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(CYAN, 0.8))
	draw_string(_logo_font, tpos + jitter, game_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0.97, 0.99, 1.0))
	if g > 0.0:
		for i in 3:
			var sy := tpos.y - tsize.y * randf_range(0.2, 0.9)
			draw_rect(Rect2(tpos.x + randf_range(-20.0, tsize.x * 0.8), sy, randf_range(60.0, 240.0), randf_range(3.0, 8.0)), Color(CYAN if i % 2 == 0 else RED, 0.55))
	_glow_pts.append(tpos + Vector2(tsize.x * 0.5, -tsize.y * 0.35))
	# bar under the title
	var uy := tpos.y + 18.0
	draw_rect(Rect2(lx + tf.x, uy + tf.y, 90, 6), RED)
	draw_rect(Rect2(lx + 100.0 + tf.x, uy + 2.0 + tf.y, tsize.x - 100.0, 2), Color(CYAN, 0.7))

	# items
	var top := vs.y * 0.52
	var step := fs * 1.85
	for i in _items.size():
		var e := clampf((_t - 0.35 - i * 0.14) * 3.2, 0.0, 1.0)
		e = 1.0 - pow(1.0 - e, 3.0)
		var f := _float(1.0 + i * 0.5)
		var label: String = _items[i].label
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var h := _font.get_height(fs) + 14.0
		var selected := i == _sel
		var x := lx + f.x - (1.0 - e) * 300.0 + (18.0 if selected else 0.0)
		var y := top + i * step + f.y
		var r := Rect2(x - 22.0, y, tw.x + 76.0, h)
		_rects.append(r)
		_glow_pts.append(r.get_center())
		var a := e
		var sk := 18.0
		if selected:
			var poly := PackedVector2Array([r.position + Vector2(sk, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(sk, 0), Vector2(r.position.x, r.end.y)])
			var shadow := PackedVector2Array()
			for p in poly:
				shadow.append(p + Vector2(8, 8))
			draw_colored_polygon(shadow, Color(0, 0, 0, 0.75 * a))
			var edge := PackedVector2Array()
			for p in poly:
				edge.append(p + Vector2(-5, -4))
			draw_polyline(edge + PackedVector2Array([edge[0]]), Color(CYAN, 0.9 * a), 2.0)
			draw_colored_polygon(poly, Color(RED, a))
			draw_string(_font, Vector2(x + 8.0, y + 7.0 + _font.get_ascent(fs)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
			draw_rect(Rect2(r.position.x - 38.0, y + h * 0.5 - 3.0, 22, 6), Color(RED, a))
		else:
			draw_line(Vector2(lx - 26.0 + f.x, y + h * 0.5), Vector2(lx - 8.0 + f.x, y + h * 0.5), Color(CYAN, 0.45 * a), 2.0)
			draw_string(_font, Vector2(x + 8.0, y + 7.0 + _font.get_ascent(fs)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.82, 0.92, 1.0, 0.8 * a))

# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if _busy or _in_options or not GameAudio._web_audio_unlocked:
		return
	event = InputSupport.menu_event(event)
	if event is InputEventMouseMotion:
		for i in _rects.size():
			if _rects[i].has_point(event.position) and i != _sel:
				_select(i)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _rects.size():
			if _rects[i].has_point(event.position):
				_sel = i
				_activate()
				return
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W:
				_select((_sel - 1 + _items.size()) % _items.size())
			KEY_DOWN, KEY_S:
				_select((_sel + 1) % _items.size())
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()

func _select(i: int) -> void:
	_sel = i
	_blip.pitch_scale = 1.2 + 0.1 * i
	_blip.play()

func _activate() -> void:
	_blip.pitch_scale = 1.8
	_blip.play()
	match String(_items[_sel].act):
		"play":
			_start(play_scene)
		"how":
			_start(tutorial_scene)
		"options":
			_open_options()

func _start(path: String) -> void:
	if _busy:
		return
	_busy = true
	GameAudio.set_menu_music(false)
	GameManager.restart_all()
	Transition.change_scene(path)

func _open_options() -> void:
	if _in_options:
		return
	var scene := load(options_scene) as PackedScene
	if scene == null:
		return
	_in_options = true
	_glow.hide()
	_bg.hide()
	queue_redraw()
	_options = scene.instantiate() as Control
	_options.set_meta("no_polish", true)
	_options.set_meta("embedded_options", true)
	_options.tree_exited.connect(_on_options_closed)
	add_child(_options)
	_options.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _on_options_closed() -> void:
	_options = null
	_in_options = false
	_glow.show()
	_bg.show()
