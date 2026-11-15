extends Control
## Title screen. PLAY and OPTIONS always show. HOW TO PLAY unlocks after the briefing has been finished once.
@export var title_text: String = "MARS // OUTPOST"
@export_file("*.tscn") var play_scene: String = "res://scenes/main scenes/cutscene.tscn"
@export_file("*.tscn") var tutorial_scene: String = "res://scenes/main scenes/tutorial.tscn"
@export var menu_font: Font

var _options: Control
var _menu: VBoxContainer
var _options_button: Button
var _busy: bool = false
var _t := 0.0
var _bubbles: Array[Dictionary] = []

func _ready() -> void:
	set_meta("no_polish", true)
	var sky := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.01, 0.05, 0.10), Color(0.02, 0.16, 0.24), Color(0.03, 0.22, 0.26)])
	g.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	sky.texture = gt
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	for i in 14:
		_bubbles.append({"x": randf(), "y": randf(), "r": randf_range(10.0, 46.0), "s": randf_range(0.01, 0.035), "p": randf() * TAU})
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	center.add_child(card)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 16)
	card.add_child(_menu)
	var font: Font = menu_font if menu_font != null else GameFont.get_font()
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.85, 1.0, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.2, 0.9, 1.0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	_menu.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Hellas Planitia, Mars"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", font)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.85, 0.9))
	_menu.add_child(subtitle)
	var play := _button("PLAY", font)
	play.pressed.connect(_start.bind(play_scene))
	if SaveFlags.get_flag("tutorial_done"):
		var how := _button("HOW TO PLAY", font)
		how.pressed.connect(_start.bind(tutorial_scene))
	_options_button = _button("OPTIONS", font)
	_options_button.pressed.connect(_open_options)
	play.grab_focus()

func _card_style() -> StyleBoxFlat:
	var s := GlassUI.panel(Color(0.02, 0.09, 0.14, 0.72), Color(0.45, 0.95, 1.0, 0.8), 22, 22)
	s.content_margin_left = 54
	s.content_margin_right = 54
	s.content_margin_top = 34
	s.content_margin_bottom = 40
	return s

func _button(text: String, font: Font) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 54)
	button.add_theme_font_override("font", font)
	GlassUI.style_button(button, 22)
	_menu.add_child(button)
	return button

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var v := size
	for b in _bubbles:
		var y: float = fposmod(b.y - _t * b.s, 1.0)
		var pos := Vector2(b.x * v.x + sin(_t * 0.4 + b.p) * 18.0, y * (v.y + 120.0) - 60.0)
		var r: float = b.r
		draw_circle(pos, r, Color(0.5, 0.95, 1.0, 0.07))
		draw_arc(pos, r, 0.0, TAU, 40, Color(0.7, 1.0, 1.0, 0.22), 1.5, true)
		draw_circle(pos + Vector2(-r * 0.3, -r * 0.35), r * 0.22, Color(1, 1, 1, 0.16))

func _start(path: String) -> void:
	if _busy:
		return
	_busy = true
	GameManager.restart_all()
	for child in _menu.get_children():
		if child is Button:
			child.disabled = true
	Transition.change_scene(path)

func _open_options() -> void:
	if _busy or is_instance_valid(_options):
		return
	var scene := load("res://scenes/main scenes/options.tscn") as PackedScene
	if scene == null:
		return
	_menu.get_parent().hide()
	_options = scene.instantiate() as Control
	_options.set_meta("no_polish", true)
	_options.tree_exited.connect(_on_options_closed)
	add_child(_options)
	_options.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _on_options_closed() -> void:
	_options = null
	_menu.get_parent().show()
	_options_button.grab_focus.call_deferred()
