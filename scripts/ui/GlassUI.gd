class_name GlassUI
## Shared "glass" look: dark aqua panels, light borders, soft glow, glossy top highlight.
const AQUA := Color(0.38, 0.92, 1.0)
const MINT := Color(0.55, 1.0, 0.75)
const DEEP := Color(0.02, 0.09, 0.14)

static func panel(bg: Color = Color(0.03, 0.10, 0.16, 0.93), border: Color = AQUA, radius: int = 14, glow: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(border.r, border.g, border.b, 0.28)
	s.shadow_size = glow
	s.anti_aliasing = true
	return s

static func gloss(parent: Control, margin: float = 4.0, height: float = 0.48) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.20), Color(1, 1, 1, 0.02)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_TOP_WIDE)
	r.anchor_bottom = height
	r.offset_left = margin
	r.offset_right = -margin
	r.offset_top = margin
	r.offset_bottom = 0.0
	parent.add_child(r)
	parent.move_child(r, 0)
	return r

static func style_button(b: Button, size: int = 22) -> void:
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.85, 0.98, 1.0))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.5, 0.55))
	var n := panel(Color(0.04, 0.15, 0.22, 0.92), Color(0.3, 0.7, 0.85), 18, 8)
	var h := panel(Color(0.06, 0.28, 0.36, 0.96), MINT, 18, 16)
	var p := panel(Color(0.08, 0.38, 0.42, 1.0), Color.WHITE, 18, 6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("disabled", n)
	b.focus_mode = Control.FOCUS_ALL
	gloss(b, 5.0, 0.5)
