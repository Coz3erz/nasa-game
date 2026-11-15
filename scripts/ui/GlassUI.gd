# CHANGELOG (2026-11-15): Transparent keyboard-focus outline avoids stacking a second filled hover selection.
class_name GlassUI
## Shared digital UI look: near-black panels, hard cyan edges, hard offset shadow, red highlight.
const CYAN := Color(0.35, 0.9, 1.0)
const RED := Color(0.95, 0.12, 0.2)
const INK := Color(0.015, 0.025, 0.045)

static func panel(bg: Color = Color(0.015, 0.025, 0.045, 0.95), border: Color = CYAN, _radius: int = 0, _glow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.border_width_left = 5
	s.shadow_color = Color(border.r, border.g, border.b, 0.35)
	s.shadow_size = 1
	s.shadow_offset = Vector2(5, 5)
	return s

static func gloss(_parent: Control, _a: float = 0.0, _b: float = 0.0) -> void:
	pass

static func style_button(b: Button, size: int = 22) -> void:
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.45, 0.5))
	var n := panel(INK, Color(0.3, 0.6, 0.7))
	var h := panel(RED, Color.WHITE)
	h.shadow_color = Color(0, 0, 0, 0.8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	var focus := panel(Color(0, 0, 0, 0), Color.WHITE)
	focus.shadow_size = 0
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", n)
	b.focus_mode = Control.FOCUS_ALL
