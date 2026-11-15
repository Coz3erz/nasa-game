
extends CanvasLayer
class_name DayLoop

const TAGLINES := [
	"Build the base and get the power on.",
	"Machines fail more often today.",
	"Dust storms can start today. Stay close to your equipment.",
	"Almost there. Keep everything running.",
	"Last day. Hold on until the rescue team lands."
]
const AMBER := Color(1.0, 0.82, 0.35)
const CYAN := Color(0.4, 0.9, 1.0)
const RED := Color(1.0, 0.35, 0.3)
const MUTED := Color(0.65, 0.72, 0.82)

var win_scene: String = ""

## set by game.gd from its "Transition SFX" exports (all optional)
var sfx_card_slam: AudioStream
var sfx_type: AudioStream
var sfx_card_out: AudioStream
var sfx_timer_start: AudioStream
var sfx_volume_db: float = -4.0
var debug_mode: bool = false
var _cover: ColorRect
var _intro_card: Control
var time_left: float = 0.0
var running: bool = false
var ended: bool = false

var font: Font
var panel: PanelContainer
var day_lbl: Label
var time_lbl: Label
var bar: ProgressBar
var kit_lbl: Label
var _t: float = 0.0

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = GameFont.get_font()
	_cover = ColorRect.new()
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.color = Color.BLACK
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	time_left = GameManager.day_length
	_build_panel()
	GameManager.day_failed.connect(_on_failed)

func _exit_tree() -> void:
	if GameManager.day_failed.is_connected(_on_failed):
		GameManager.day_failed.disconnect(_on_failed)

func _lbl(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(2, size / 10))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = 16
	panel.offset_right = -16
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.9)
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	sb.border_width_right = 5
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	day_lbl = _lbl(15, AMBER)
	day_lbl.text = "DAY %d / %d" % [GameManager.current_sol, GameManager.total_days]
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(day_lbl)
	time_lbl = _lbl(36, Color.WHITE)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(time_lbl)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(170, 6)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.16)
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	vb.add_child(bar)
	kit_lbl = _lbl(13, Color(1.0, 0.55, 0.6))
	kit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kit_lbl.visible = false
	vb.add_child(kit_lbl)
	if debug_mode:
		var dbg := _lbl(12, Color(0.6, 1.0, 0.6))
		dbg.text = "DEBUG  [N] SKIP DAY"
		dbg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vb.add_child(dbg)
	panel.visible = false
	add_child(panel)

const BACKDROP_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float alpha = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float d = distance(uv, vec2(0.5));
	vec3 col = vec3(0.012, 0.018, 0.03);
	col += tint.rgb * 0.16 * smoothstep(0.75, 0.0, d);
	float row = floor(uv.y * 38.0);
	float sp = 0.15 + h(vec2(row, 1.0)) * 0.5;
	float sx = fract(uv.x * 0.6 - TIME * sp + h(vec2(row, 7.0)));
	float streak = smoothstep(0.0, 0.04, sx) * smoothstep(0.35, 0.04, sx) * step(0.82, h(vec2(row, 3.0)));
	col += tint.rgb * streak * 0.22;
	col *= 0.93 + 0.07 * sin(uv.y * 900.0);
	col *= 1.0 - smoothstep(0.35, 0.95, d) * 0.7;
	COLOR = vec4(col, alpha);
}
"""
const BAR_H := 84.0

## solid   = opaque intro card (stays up as _intro_card; play_intro/reveal wipe it away)
## dismiss = animate out and free itself (used by banners)
## neither = stays up (end-of-day cards; the next shutter covers them)
func _card(title: String, sub: String, col: Color, hold: float, solid: bool, dismiss: bool = false) -> void:
	var card := Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsh := Shader.new()
	bsh.code = BACKDROP_SHADER
	var bmat := ShaderMaterial.new()
	bmat.shader = bsh
	bmat.set_shader_parameter("tint", col)
	bmat.set_shader_parameter("alpha", 1.0 if solid else 0.84)
	bg.material = bmat
	card.add_child(bg)

	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0.9)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(flash)

	# cinematic letterbox bars with a glowing inner edge
	var bars: Array[ColorRect] = []
	for is_top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if is_top else Control.PRESET_BOTTOM_WIDE)
		var edge := ColorRect.new()
		edge.color = Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, 0.9)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if is_top else Control.PRESET_TOP_WIDE)
		if is_top:
			edge.offset_top = -2.0
		else:
			edge.offset_bottom = 2.0
		bar.add_child(edge)
		card.add_child(bar)
		bars.append(bar)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)

	# title: one label per letter so each can slam in separately
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	var fsize := 112 if title.length() <= 8 else (96 if title.length() <= 11 else 80)
	var letters: Array[Label] = []
	for ch in title:
		var l := _lbl(fsize, Color(col.r * 1.3, col.g * 1.3, col.b * 1.3))
		l.text = ch
		l.modulate = Color(3.0, 3.0, 3.0, 0.0)
		row.add_child(l)
		letters.append(l)

	var line := ColorRect.new()
	line.color = Color(col.r * 1.4, col.g * 1.4, col.b * 1.4)
	line.custom_minimum_size = Vector2(0, 4)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(line)

	var s := _lbl(24, AMBER if col != RED else Color(1.0, 0.7, 0.6))
	s.text = sub
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.visible_ratio = 0.0
	vb.add_child(s)

	var pips := _pips(col)
	pips.modulate.a = 0.0
	vb.add_child(pips)

	if solid:
		card.modulate.a = 0.0
		create_tween().tween_property(card, "modulate:a", 1.0, 0.25)

	await get_tree().process_frame
	for l in letters:
		l.pivot_offset = l.size * 0.5
		l.scale = Vector2(2.4, 2.4)
	vb.pivot_offset = vb.size * 0.5

	_play(sfx_card_slam)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(bars[0], "offset_bottom", BAR_H, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(bars[1], "offset_top", -BAR_H, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in letters.size():
		var l := letters[i]
		var dl := 0.05 * i
		tw.tween_property(l, "scale", Vector2.ONE, 0.45).set_delay(dl).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(l, "modulate", Color.WHITE, 0.5).set_delay(dl)
	var t_end := 0.05 * letters.size()
	tw.tween_property(flash, "color:a", 0.0, 0.55)
	tw.tween_property(line, "custom_minimum_size:x", 460.0, 0.7).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var type_t := clampf(sub.length() * 0.025, 0.4, 1.4)
	var build_t := 0.35 + t_end + type_t          # time until all text is on screen
	tw.tween_property(s, "visible_ratio", 1.0, type_t).set_delay(0.35 + t_end)
	if sfx_type != null:
		var last := [0]
		tw.tween_method(func(v: float):
			var n := int(v * sub.length())
			if n != last[0]:
				last[0] = n
				if n > 0 and n <= sub.length() and sub[n - 1] != " ":
					_play(sfx_type, randf_range(0.95, 1.08), -6.0)
		, 0.0, 1.0, type_t).set_delay(0.35 + t_end)
	tw.tween_property(pips, "modulate:a", 1.0, 0.4).set_delay(0.5 + t_end)
	tw.tween_property(vb, "scale", Vector2(1.04, 1.04), build_t + hold + 0.5)   # slow push-in

	# `hold` = how long everything stays fully readable AFTER the build-in finishes
	await get_tree().create_timer(build_t + hold).timeout

	if solid:
		_intro_card = card
		if get_node_or_null("/root/Transition") == null:
			var out := create_tween()
			out.tween_property(card, "modulate:a", 0.0, 0.7)
			await out.finished
		return
	if dismiss:
		_play(sfx_card_out)
		var ex := create_tween().set_parallel(true)
		ex.tween_property(vb, "modulate:a", 0.0, 0.5)
		ex.tween_property(vb, "scale", Vector2(1.2, 1.2), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		ex.tween_property(bg, "modulate:a", 0.0, 0.5).set_delay(0.15)
		ex.tween_property(bars[0], "offset_bottom", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		ex.tween_property(bars[1], "offset_top", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await ex.finished
		card.queue_free()

## row of day pips: finished days filled, today pulsing, future dim
func _pips(col: Color) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in maxi(GameManager.total_days, 1):
		var p := ColorRect.new()
		p.custom_minimum_size = Vector2(26, 6)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d := i + 1
		if d < GameManager.current_sol:
			p.color = Color(col.r * 1.3, col.g * 1.3, col.b * 1.3)
		elif d == GameManager.current_sol:
			p.color = Color(AMBER.r * 1.4, AMBER.g * 1.4, AMBER.b * 1.4)
			var pl := p.create_tween().set_loops()
			pl.tween_property(p, "modulate:a", 0.35, 0.5)
			pl.tween_property(p, "modulate:a", 1.0, 0.5)
		else:
			p.color = Color(1, 1, 1, 0.15)
		hb.add_child(p)
	return hb

## cinematic title that plays over the game and then clears itself
func banner(title: String, sub: String, col: Color, hold: float = 2.0) -> void:
	await _card(title, sub, col, hold, false, true)

func survive_sub() -> String:
	return "Keep air, heat and power running until sunrise"

func play_intro() -> void:
	var trans := get_node_or_null("/root/Transition")
	if trans != null:
		if trans.overlay.modulate.a > 0.0:
			trans.fade_from_black(0.35)
		if trans.shutter_progress > 0.0:
			trans.shutter_open(0.7)          # coming back from a day reload: blinds sweep open on the card
	var day := GameManager.current_sol
	var tag: String = TAGLINES[clampi(day - 1, 0, TAGLINES.size() - 1)]
	await _card("DAY %d" % day, tag, CYAN, 2.4, true)
	if trans != null:
		await trans.shutter_close(0.55)      # card -> blinds slam shut; shop is built behind them

func reveal() -> void:
	var trans := get_node_or_null("/root/Transition")
	if trans != null and trans.shutter_progress > 0.99:
		if is_instance_valid(_intro_card):
			_intro_card.queue_free()
		_cover.queue_free()
		await get_tree().process_frame
		await trans.shutter_open(0.85)       # blinds sweep open on the finished shop
		return
	await get_tree().create_timer(0.5).timeout
	var tw := create_tween()
	tw.tween_property(_cover, "modulate:a", 0.0, 0.9)
	await tw.finished
	_cover.queue_free()
	if is_instance_valid(_intro_card):
		_intro_card.queue_free()

func start_timer() -> void:
	_play(sfx_timer_start)
	running = true
	panel.visible = true
	panel.modulate = Color(2.2, 2.2, 2.2, 0.0)
	await get_tree().process_frame
	panel.pivot_offset = Vector2(panel.size.x, 0.0)
	panel.scale = Vector2(0.7, 0.7)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate", Color.WHITE, 0.5)

func _process(delta: float) -> void:
	_t += delta
	var kits := GameManager.get_item_count("Med Kit")
	kit_lbl.visible = kits > 0
	if kits > 0:
		kit_lbl.text = "MED KITS %d  [H] USE" % kits
	if not running or ended:
		return
	time_left = maxf(0.0, time_left - delta)
	var secs := int(ceil(time_left))
	time_lbl.text = "%02d:%02d" % [floori(secs / 60.0), secs % 60]
	bar.value = time_left / maxf(GameManager.day_length, 1.0) * 100.0
	var low := time_left <= 30.0
	var col := Color.WHITE
	if low:
		var p := 0.5 + 0.5 * sin(_t * 8.0)
		col = Color.WHITE.lerp(RED, 0.5 + 0.5 * p)
	time_lbl.add_theme_color_override("font_color", col)
	if time_left <= 0.0:
		_end_day()

func _unhandled_input(event: InputEvent) -> void:
	if debug_mode and running and not ended and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		_end_day()
		return
	if ended or GameManager.current_phase != GameManager.Phase.SURVIVE:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		if GameManager.get_item_count("Med Kit") <= 0:
			return
		if BaseManager.health >= 99.0:
			_popup("You are already healthy!", MUTED)
			return
		GameManager.remove_from_inventory("Med Kit")
		BaseManager.health = minf(100.0, BaseManager.health + 45.0)
		_popup("+45 health", Color(1.0, 0.5, 0.55))

func _popup(msg: String, col: Color) -> void:
	var l := _lbl(26, col)
	l.text = msg
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position.y = 140
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 100.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)

func _end_day() -> void:
	if ended:
		return
	ended = true
	running = false
	GameManager.current_phase = GameManager.Phase.DEBRIEF
	var day := GameManager.current_sol
	var trans := get_node_or_null("/root/Transition")
	if day >= GameManager.total_days:
		await _card("RESCUE TEAM LANDED", "You held the base for all %d days" % day, AMBER, 3.2, false)
		GameManager.restart_all()
		var path := win_scene
		if path == "" or not ResourceLoader.exists(path):
			path = "res://scenes/main scenes/cutscene.tscn"
		if trans != null:
			await trans.change_scene(path, 1.2)
		else:
			get_tree().change_scene_to_file(path)
		return
	await _card("DAY %d CLEAR" % day, "Nice work! Tomorrow is harder.", CYAN, 2.4, false)
	GameManager.advance_day()
	await _reload()

func _on_failed(reason: String) -> void:
	if ended:
		return
	ended = true
	running = false
	GameManager.current_phase = GameManager.Phase.DEBRIEF
	Hazards.clear()
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("set_input_locked"):
			p.set_input_locked(true)
	await _death_sequence(reason)
	GameManager.restart_day()
	get_tree().reload_current_scene()

func _death_shake(v: float, cam: Camera2D) -> void:
	if is_instance_valid(cam):
		cam.offset = Vector2(randf_range(-v, v), randf_range(-v, v))

## Crash sound, orange flash and screen shake, then a slow fade to black with a short message.
func _death_sequence(reason: String) -> void:
	var layer_fx := CanvasLayer.new()
	layer_fx.layer = 95
	layer_fx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer_fx)
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.38, 0.1, 0.65)
	flash.mouse_filter = Control.MOUSE_FILTER_STOP
	layer_fx.add_child(flash)
	var black := ColorRect.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_fx.add_child(black)
	var msg := Label.new()
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_font_override("font", font)
	msg.add_theme_font_size_override("font_size", 26)
	msg.add_theme_color_override("font_color", Color(1.0, 0.62, 0.3))
	msg.text = "SIGNAL LOST\n\n%s\n\nStarting day %d again..." % [reason.capitalize(), GameManager.current_sol]
	msg.modulate.a = 0.0
	layer_fx.add_child(msg)
	var snd := AudioStreamPlayer.new()
	snd.stream = SynthSfx.crash_wav()
	snd.volume_db = -1.0
	if AudioServer.get_bus_index("SFX") != -1:
		snd.bus = &"SFX"
	layer_fx.add_child(snd)
	snd.play()
	var cam := get_viewport().get_camera_2d()
	var tw_shake := create_tween()
	tw_shake.tween_method(_death_shake.bind(cam), 26.0, 0.0, 1.5)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.9)
	tw.parallel().tween_property(black, "color:a", 1.0, 1.7).set_delay(0.5)
	tw.tween_property(msg, "modulate:a", 1.0, 0.6)
	tw.tween_interval(2.0)
	await tw.finished
	if is_instance_valid(cam):
		cam.offset = Vector2.ZERO

func _reload(col: Color = CYAN) -> void:
	var trans := get_node_or_null("/root/Transition")
	if trans != null:
		await trans.shutter_close(0.7, col)
	get_tree().reload_current_scene()

func _play(stream: AudioStream, pitch: float = 1.0, extra_db: float = 0.0) -> void:
	if stream == null:
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = stream
	pl.pitch_scale = pitch
	pl.volume_db = sfx_volume_db + extra_db
	if AudioServer.get_bus_index("SFX") != -1:
		pl.bus = &"SFX"
	add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()
