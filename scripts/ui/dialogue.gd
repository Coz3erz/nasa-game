
extends CanvasLayer
## AUTOLOAD "Dialogue" (scenes/ui/dialogue.tscn).
##   await Dialogue.say("Text", anchor, "Commander", portrait, dim, spotlight)
## - types the text, waits for SPACE / ENTER / click, locks the player the whole time
## - dim = true darkens the whole screen except this box (and the optional spotlight)
## - spotlight can be a Node2D (world object) or a Rect2 (screen rectangle) to leave lit
## - anchor can be a Node2D, a world Vector2, or Dialogue.SCREEN (bottom-centre of the screen)
## The font comes from GameFont automatically. No scroll bar: the box grows to fit the text.
signal line_finished
signal line_dismissed

const SCREEN := &"__screen__"
const SCREEN_TOP := &"__screen_top__"

@export_group("Speaker")
@export var character_sprite: Texture2D
@export var speaker_name: String = "COMMANDER"
@export_group("Typography")
@export var dialogue_font: Font          ## leave empty to use GameFont
@export_range(8, 48) var font_size: int = 20
@export_range(0.0, 120.0) var characters_per_second: float = 30.0
@export_group("Appearance")
@export var box_size: Vector2 = Vector2(560, 170)
@export var anchor_gap: float = 24.0
@export var screen_margin: float = 8.0
@export var background_color: Color = Color(0.015, 0.025, 0.045, 0.97)
@export var border_color: Color = Color(0.35, 0.9, 1.0)
@export var text_color: Color = Color(0.94, 0.96, 1.0)
@export var name_color: Color = Color(1.0, 0.32, 0.38)
@export var dim_strength: float = 0.84

const DIM_SHADER := """
shader_type canvas_item;
uniform float dim = 0.0;
uniform vec2 size = vec2(1152.0, 648.0);
uniform vec4 box = vec4(0.0);
uniform vec4 spot_rect = vec4(0.0);
uniform vec4 spot_circle = vec4(0.0);
float sd_rect(vec2 p, vec4 r){
	if (r.z <= 0.0) { return 100000.0; }
	vec2 c = r.xy + r.zw * 0.5;
	vec2 q = abs(p - c) - r.zw * 0.5;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
void fragment(){
	vec2 p = UV * size;
	float d = min(sd_rect(p, box), sd_rect(p, spot_rect));
	if (spot_circle.z > 0.0) { d = min(d, length(p - spot_circle.xy) - spot_circle.z); }
	float hole = 1.0 - smoothstep(-2.0, 22.0, d);
	COLOR = vec4(0.0, 0.0, 0.025, dim * (1.0 - hole));
}
"""

var dim_rect: ColorRect
var dialogue_box: Panel
var portrait: TextureRect
var name_label: Label
var body: RichTextLabel
var hint_label: Label
var type_player: AudioStreamPlayer
var _font: Font
var _anchor: Node2D
var _world_position := Vector2.ZERO
var _has_world_position := false
var _screen_mode := false
var _screen_top := false
var _reveal := 0.0
var _finished := false
var _dismissible := false
var _line_visible := false
var _full_text := ""
var _spot: Variant = null
var _dim_tween: Tween
var _t := 0.0
var _last_tick := 0

func _ready() -> void:
	layer = 80
	process_priority = 1000
	set_meta("no_polish", true)
	_font = dialogue_font if dialogue_font != null else GameFont.get_font()

	dim_rect = ColorRect.new()
	dim_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = DIM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	dim_rect.material = mat
	dim_rect.visible = false
	add_child(dim_rect)

	dialogue_box = Panel.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_theme_stylebox_override("panel", GlassUI.panel(background_color, border_color, 14, 14))
	add_child(dialogue_box)

	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(portrait)

	name_label = Label.new()
	name_label.add_theme_color_override("font_color", name_color)
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", maxi(8, font_size - 4))
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(name_label)

	body = RichTextLabel.new()
	body.bbcode_enabled = false
	body.scroll_active = false          # no scroll bar, ever
	body.scroll_following = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_color_override("default_color", text_color)
	body.add_theme_font_override("normal_font", _font)
	body.add_theme_font_size_override("normal_font_size", font_size)
	dialogue_box.add_child(body)

	hint_label = Label.new()
	hint_label.text = "SPACE  >"
	hint_label.add_theme_font_override("font", _font)
	hint_label.add_theme_font_size_override("font_size", maxi(8, font_size - 8))
	hint_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(hint_label)

	type_player = AudioStreamPlayer.new()
	type_player.volume_db = -16.0
	if ResourceLoader.exists("res://sounds/cutscene/key_type.mp3"):
		type_player.stream = load("res://sounds/cutscene/key_type.mp3")
	if AudioServer.get_bus_index("SFX") != -1:
		type_player.bus = &"SFX"
	add_child(type_player)

	hide_dialogue()
	EventBus.show_dialogue.connect(_on_legacy_dialogue)

# ------------------------------------------------------------------ API
## Show a line, wait for the player to read it, then hide it. Player input is locked meanwhile.
func say(text: String, location: Variant = null, character: String = "", sprite: Texture2D = null, dim: bool = false, spot: Variant = null) -> void:
	_lock_player(true)
	show_dialogue(text, location, character, sprite, true)
	_set_dim(dim, spot)
	await line_dismissed
	_set_dim(false, null)
	_lock_player(false)

func show_dialogue(text: String, location: Variant = null, character: String = "", sprite: Texture2D = null, dismissible: bool = false) -> void:
	set_anchor(location)
	name_label.text = speaker_name if character.is_empty() else character
	portrait.texture = sprite if sprite != null else character_sprite
	_full_text = text
	body.text = text
	body.visible_characters = 0
	_reveal = 0.0
	_last_tick = 0
	_finished = false
	_dismissible = dismissible
	hint_label.visible = false
	_line_visible = true
	dialogue_box.show()
	_follow_anchor()

func hide_dialogue() -> void:
	_line_visible = false
	if dialogue_box != null:
		dialogue_box.hide()
	_anchor = null
	_has_world_position = false
	_screen_mode = false
	_screen_top = false

func set_anchor(location: Variant) -> void:
	_screen_mode = location is StringName and (location == SCREEN or location == SCREEN_TOP)
	_screen_top = location is StringName and location == SCREEN_TOP
	_anchor = location as Node2D if location is Node2D else null
	_has_world_position = location is Vector2
	if _has_world_position:
		_world_position = location

func _lock_player(locked: bool) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("set_input_locked"):
			p.set_input_locked(locked)

func _set_dim(on: bool, spot: Variant) -> void:
	_spot = spot
	if _dim_tween != null:
		_dim_tween.kill()
	var mat := dim_rect.material as ShaderMaterial
	if on:
		dim_rect.visible = true
	_dim_tween = create_tween()
	var cur: Variant = mat.get_shader_parameter("dim")
	var from_v: float = 0.0 if cur == null else float(cur)
	_dim_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("dim", v), from_v, dim_strength if on else 0.0, 0.25)
	if not on:
		_dim_tween.tween_callback(func() -> void: dim_rect.visible = false)

func _on_legacy_dialogue(sprite: Texture2D, text: String, location: String) -> void:
	var actor: Node2D = null
	var scene := get_tree().current_scene
	if scene != null and not location.is_empty():
		actor = scene.get_node_or_null(NodePath(location)) as Node2D
		if actor == null:
			actor = get_tree().get_first_node_in_group(location) as Node2D
	show_dialogue(text, actor, "", sprite)

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	_t += delta
	if not _line_visible:
		return
	_follow_anchor()
	_update_dim()
	hint_label.visible = _finished and _dismissible
	if hint_label.visible:
		hint_label.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 5.0))
	if _finished:
		return
	_reveal += delta * characters_per_second
	body.visible_characters = -1 if characters_per_second <= 0.0 else int(_reveal)
	if int(_reveal) - _last_tick >= 3 and type_player.stream != null:
		_last_tick = int(_reveal)
		type_player.pitch_scale = randf_range(0.95, 1.1)
		type_player.play()
	if characters_per_second <= 0.0 or body.visible_characters >= body.get_total_character_count():
		_finished = true
		body.visible_characters = -1
		line_finished.emit()

func _input(event: InputEvent) -> void:
	if not _line_visible or not _dismissible:
		return
	var is_press = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	get_viewport().set_input_as_handled()      # nothing reaches the game while a box is open
	if not is_press:
		return
	var accept := event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton:
		accept = event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventKey:
		accept = event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] or event.physical_keycode == KEY_SPACE
	if not accept:
		return
	if not _finished:
		_reveal = float(body.get_total_character_count())
	else:
		hide_dialogue()
		line_dismissed.emit()

# ------------------------------------------------------------------ layout
func _update_dim() -> void:
	if not dim_rect.visible:
		return
	var mat := dim_rect.material as ShaderMaterial
	mat.set_shader_parameter("size", dim_rect.size)
	mat.set_shader_parameter("box", Vector4(dialogue_box.position.x, dialogue_box.position.y, dialogue_box.size.x, dialogue_box.size.y))
	mat.set_shader_parameter("spot_rect", Vector4.ZERO)
	mat.set_shader_parameter("spot_circle", Vector4.ZERO)
	if _spot is Rect2:
		var r: Rect2 = _spot
		mat.set_shader_parameter("spot_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	elif _spot is Node2D and is_instance_valid(_spot):
		var n: Node2D = _spot
		var sp: Vector2 = n.get_canvas_transform() * n.global_position
		var radius := 90.0
		if n is BaseModule:
			radius = maxf(90.0, (n as BaseModule).get_footprint().size.length() * 0.55 * n.get_canvas_transform().get_scale().x)
		mat.set_shader_parameter("spot_circle", Vector4(sp.x, sp.y, radius, 0.0))

func _fit_size(desired: Vector2, available: Vector2) -> Vector2:
	var text_w := maxf(40.0, desired.x - 104.0 - 14.0)
	var h := _font.get_multiline_string_size(_full_text, HORIZONTAL_ALIGNMENT_LEFT, text_w, font_size).y
	var need := h + 41.0 + 14.0 + 26.0
	desired.y = minf(maxf(desired.y, need), available.y)
	return desired

func _follow_anchor() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := Vector2.ONE * maxf(screen_margin, 0.0)
	var available := viewport_size - margin * 2.0
	if available.x <= 0.0 or available.y <= 0.0:
		dialogue_box.hide()
		return
	var desired := _fit_size(box_size.min(available).max(Vector2.ONE), available)
	if _screen_mode:
		dialogue_box.show()
		dialogue_box.position = Vector2((viewport_size.x - desired.x) * 0.5, 24.0 if _screen_top else viewport_size.y - desired.y - 70.0)
		dialogue_box.size = desired
		_layout_content()
		return
	if not is_instance_valid(_anchor) and not _has_world_position:
		_anchor = get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(_anchor) and not _has_world_position:
		dialogue_box.hide()
		return
	var world: Vector2 = _anchor.global_position if is_instance_valid(_anchor) else _world_position
	var canvas := get_viewport().get_canvas_transform()
	if is_instance_valid(_anchor):
		canvas = _anchor.get_canvas_transform()
	var screen_pos: Vector2 = canvas * world
	var gap := maxf(anchor_gap, 16.0)
	var protected := Rect2(screen_pos - Vector2(12, 20), Vector2(24, 40))
	if _anchor is BaseModule:
		var footprint: Rect2 = (_anchor as BaseModule).get_footprint()
		protected = Rect2(canvas * footprint.position, Vector2.ZERO)
		for corner in [footprint.end, Vector2(footprint.position.x, footprint.end.y), Vector2(footprint.end.x, footprint.position.y)]:
			protected = protected.expand(canvas * corner)
	var fit := _find_position(screen_pos, protected, desired, viewport_size, margin, gap)
	if fit.size == Vector2.ZERO:
		protected = Rect2(screen_pos - Vector2(8, 8), Vector2(16, 16))
		fit = _find_position(screen_pos, protected, desired, viewport_size, margin, gap)
	if fit.size == Vector2.ZERO:
		# nowhere clear: pin to the bottom of the screen rather than hiding the text
		fit = Rect2(Vector2((viewport_size.x - desired.x) * 0.5, viewport_size.y - desired.y - margin.y), desired)
	dialogue_box.show()
	dialogue_box.position = fit.position
	dialogue_box.size = fit.size
	_layout_content()

func _find_position(screen_pos: Vector2, protected: Rect2, desired: Vector2, viewport_size: Vector2, margin: Vector2, gap: float) -> Rect2:
	var candidates: Array[Vector2] = [
		Vector2(screen_pos.x - desired.x * 0.5, protected.position.y - desired.y - gap),
		Vector2(screen_pos.x - desired.x * 0.5, protected.end.y + gap),
		Vector2(protected.end.x + gap, screen_pos.y - desired.y * 0.5),
		Vector2(protected.position.x - desired.x - gap, screen_pos.y - desired.y * 0.5)]
	for target in candidates:
		target = target.clamp(margin, viewport_size - desired - margin)
		var rect := Rect2(target, desired)
		if not rect.intersects(protected.grow(8.0), true):
			return rect
	return Rect2()

func _layout_content() -> void:
	var size := dialogue_box.size
	var pad := 14.0
	var picture := minf(76.0, maxf(0.0, size.y - pad * 2.0))
	portrait.visible = portrait.texture != null and size.x >= 260.0 and size.y >= 70.0
	portrait.position = Vector2(pad, pad)
	portrait.size = Vector2.ONE * picture
	var left := pad + picture + 14.0 if portrait.visible else pad
	name_label.visible = size.y >= 60.0
	name_label.position = Vector2(left, pad)
	name_label.size = Vector2(maxf(1.0, size.x - left - pad), 24.0)
	var top := pad + 27.0 if name_label.visible else pad
	body.position = Vector2(left, top)
	body.size = Vector2(maxf(1.0, size.x - left - pad), maxf(1.0, size.y - top - pad - 20.0))
	hint_label.position = Vector2(size.x - 120.0 - pad, size.y - 22.0 - 6.0)
	hint_label.size = Vector2(120.0, 20.0)
