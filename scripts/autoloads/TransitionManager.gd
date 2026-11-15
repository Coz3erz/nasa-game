extends CanvasLayer
## Plain fade (used by the cutscene - unchanged) + a new SHUTTER wipe used by day/shop/survival.

var overlay: ColorRect
var transitioning: bool = false

var shutter: ColorRect
var shutter_progress: float = 0.0
var _shutter_mat: ShaderMaterial
var _shutter_tween: Tween

## set by game.gd from its "Transition SFX" exports
var sfx_close: AudioStream
var sfx_open: AudioStream
var sfx_volume_db: float = -4.0

const SHUTTER_SHADER := """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float strips = 12.0;
float hash(float n) { return fract(sin(n * 91.345) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float row = floor(uv.y * strips);
	float stagger = hash(row) * 0.4;
	float p = clamp((progress * 1.4 - stagger), 0.0, 1.0);
	p = p * p * (3.0 - 2.0 * p);
	// alternate rows sweep in from opposite sides so they meet in the middle
	float x = (mod(row, 2.0) < 1.0) ? uv.x : 1.0 - uv.x;
	float covered = step(x, p);
	float d = x - p;
	float moving = step(0.001, p) * step(p, 0.995);
	float glow = exp(-abs(d) * 55.0) * moving;
	float core = exp(-abs(d) * 260.0) * moving;
	// faint seams between strips that vanish as the screen closes
	float seam = smoothstep(0.0, 0.06, fract(uv.y * strips));
	seam *= smoothstep(1.0, 0.0, fract(uv.y * strips) * 14.0 - 12.0);
	float seam_amt = (1.0 - smoothstep(0.85, 1.0, progress)) * covered;
	vec3 base = vec3(0.012, 0.016, 0.026);
	base += edge_color.rgb * 0.05 * (1.0 - seam) * seam_amt * 6.0;
	base *= 0.94 + 0.06 * sin(uv.y * 900.0);
	vec3 col = base + edge_color.rgb * glow * 0.9 + vec3(1.0) * core * 1.6;
	float a = max(covered, clamp(glow * 0.9 + core, 0.0, 1.0));
	COLOR = vec4(col, a);
}
"""

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate.a = 0.0
	add_child(overlay)

	shutter = ColorRect.new()
	shutter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shutter.visible = false
	var sh := Shader.new()
	sh.code = SHUTTER_SHADER
	_shutter_mat = ShaderMaterial.new()
	_shutter_mat.shader = sh
	shutter.material = _shutter_mat
	add_child(shutter)

func fade_to_black(duration: float = 0.8) -> void:
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, duration)
	await tw.finished

func fade_from_black(duration: float = 0.8) -> void:
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, duration)
	await tw.finished
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func change_scene(path: String, duration: float = 0.8) -> void:
	if transitioning:
		return
	transitioning = true
	await fade_to_black(duration)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await fade_from_black(duration)
	transitioning = false

# ───────────────────────────── shutter wipe ─────────────────────────────
func _set_shutter(v: float) -> void:
	shutter_progress = v
	shutter.visible = v > 0.0
	_shutter_mat.set_shader_parameter("progress", v)

func _run_shutter(to: float, duration: float, color: Color) -> void:
	_shutter_mat.set_shader_parameter("edge_color", color)
	if _shutter_tween != null and _shutter_tween.is_valid():
		_shutter_tween.kill()
	shutter.mouse_filter = Control.MOUSE_FILTER_STOP
	_play(sfx_close if to >= 1.0 else sfx_open)
	_shutter_tween = create_tween()
	_shutter_tween.tween_method(_set_shutter, shutter_progress, to, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _shutter_tween.finished
	if to <= 0.0:
		shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Blinds slam shut with a glowing edge.
func shutter_close(duration: float = 0.6, color: Color = Color(0.4, 0.9, 1.0)) -> void:
	await _run_shutter(1.0, duration, color)

## Blinds sweep open.
func shutter_open(duration: float = 0.7, color: Color = Color(0.4, 0.9, 1.0)) -> void:
	await _run_shutter(0.0, duration, color)

func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = stream
	pl.volume_db = sfx_volume_db
	if AudioServer.get_bus_index("SFX") != -1:
		pl.bus = &"SFX"
	add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()
