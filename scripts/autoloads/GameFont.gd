extends Node
## AUTOLOAD (keep it FIRST in the autoload list). The only thing to edit: FONT_PATH.
## Paste the path of your .ttf / .otf below, e.g. "res://fonts/Silkscreen-Regular.ttf".
## Leave it empty and it picks the first font it finds in res://fonts/.
## Every label, button, dialogue box and shop card in the game uses this one font.
const FONT_PATH := ""
const FONT_FOLDER := "res://fonts"
const PIXEL_FONT := true        # true = crisp pixel look (no smoothing). false for normal fonts.

var _font: Font

func get_font() -> Font:
	if _font != null:
		return _font
	var path := FONT_PATH if FONT_PATH != "" else _first_font_in_folder()
	if path != "" and ResourceLoader.exists(path):
		var loaded := load(path) as Font
		if loaded != null:
			if loaded is FontFile and PIXEL_FONT:
				var ff := loaded as FontFile
				ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
				ff.hinting = TextServer.HINTING_NONE
				ff.generate_mipmaps = false
			_font = loaded
			return _font
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
	_font = fallback
	return _font

func _first_font_in_folder() -> String:
	var dir := DirAccess.open(FONT_FOLDER)
	if dir == null:
		return ""
	for f in dir.get_files():
		var name := f.trim_suffix(".import")
		var ext := name.get_extension().to_lower()
		if ext == "ttf" or ext == "otf" or ext == "woff2" or ext == "woff":
			return FONT_FOLDER + "/" + name
	return ""

func _ready() -> void:
	var f := get_font()
	ThemeDB.get_default_theme().default_font = f
	ThemeDB.fallback_font = f
