extends Node2D
class_name ModuleArt

const GHOST_CODE := """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.35, 0.85, 1.3, 1.0);
varying vec2 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	float l = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	float lines = 0.7 + 0.3 * step(0.5, fract(wpos.y * 0.3));
	float sweep = pow(max(0.0, sin(wpos.y * 0.045 - TIME * 2.6)), 20.0);
	vec3 c = tint.rgb * (0.25 + l * 1.15) * lines + tint.rgb * sweep * 0.7;
	COLOR = vec4(c, COLOR.a * 0.92);
}
"""

static var _ghost_shader: Shader

var host: BaseModule
var kind: String = ""
var rect := Rect2(0, 0, 256, 256)
var ghost := false
var t := 0.0
var spin := 0.0
var flow := 0.0
var slow := 0.0
var power_k := 0.0
var broken_k := 0.0
var build_k := 1.0
var box := StyleBoxFlat.new()
var rng := RandomNumberGenerator.new()
var _blocked := false
var _synced := false
var _phase := 0.0

static func make_ghost_material() -> ShaderMaterial:
	if _ghost_shader == null:
		_ghost_shader = Shader.new()
		_ghost_shader.code = GHOST_CODE
	var m := ShaderMaterial.new()
	m.shader = _ghost_shader
	return m

func _ready() -> void:
	host = get_parent() as BaseModule
	if host == null:
		set_process(false)
		return
	kind = host.module_name
	ghost = bool(host.get_meta("is_ghost", false))
	_phase = randf() * 10.0
	t = _phase
	box.anti_aliasing = true
	var col := host.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		var sz: Vector2 = (col.shape as RectangleShape2D).size
		rect = Rect2(col.position - sz * 0.5, sz)
	if ghost:
		process_mode = Node.PROCESS_MODE_ALWAYS
		power_k = 1.0
		material = make_ghost_material()
		_sync_ghost()

func _is_active() -> bool:
	if ghost:
		return true
	if host.is_broken or host.is_constructing:
		return false
	if kind == "Solar Panel":
		return true
	if kind == "Reactor":
		return BaseManager.reactor_energy > 0.0
	return host.is_powered

func _process(delta: float) -> void:
	if host == null:
		return
	t += delta
	var target := 1.0 if _is_active() else 0.0
	power_k = lerpf(power_k, target, 1.0 - exp(-5.0 * delta))
	broken_k = lerpf(broken_k, 1.0 if host.is_broken else 0.0, 1.0 - exp(-8.0 * delta))
	build_k = clampf(host.build_progress / 100.0, 0.0, 1.0) if host.is_constructing else 1.0
	spin += delta * 9.0 * power_k
	flow += delta * 70.0 * power_k
	slow += delta * (0.35 + 0.9 * power_k)
	if ghost:
		_sync_ghost()
	queue_redraw()

func _sync_ghost() -> void:
	var m := host.modulate
	var blocked := m.r > m.b * 1.4
	if _synced and blocked == _blocked:
		return
	_synced = true
	_blocked = blocked
	var tint := Color(1.8, 0.35, 0.3) if blocked else Color(0.35, 0.85, 1.3)
	(material as ShaderMaterial).set_shader_parameter("tint", tint)
	for ch in host.get_children():
		if ch is CanvasItem and (ch as CanvasItem).material is ShaderMaterial:
			((ch as CanvasItem).material as ShaderMaterial).set_shader_parameter("tint", tint)

func _col(c: Color, k: float, a: float = 1.0) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, a)

func _rbox(r: Rect2, fill: Color, border: Color = Color(0, 0, 0, 0), radius: int = 6, bw: int = 0) -> void:
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(bw)
	box.set_corner_radius_all(radius)
	draw_style_box(box, r)

func _glow(p: Vector2, rad: float, col: Color, a: float) -> void:
	for i in 5:
		var k := float(i) / 4.0
		draw_circle(p, rad * (1.0 + k * 1.3), Color(col.r, col.g, col.b, a * (1.0 - k) * 0.28))

func _disc(p: Vector2, rad: float, fill: Color, rim: Color, w: float) -> void:
	draw_circle(p, rad, fill)
	draw_arc(p, rad, 0.0, TAU, 48, rim, w, true)

func _led(p: Vector2, col: Color, on: float) -> void:
	var lit := on * (0.65 + 0.35 * sin(t * 5.0 + p.x))
	draw_circle(p, 3.6, Color(0.04, 0.05, 0.07))
	draw_circle(p, 2.5, col.darkened(0.75).lerp(_col(col, 1.3), lit))
	if lit > 0.3:
		_glow(p, 3.0, col, lit)

func _bolts(r: Rect2, inset: float) -> void:
	for i in 4:
		var p := Vector2(r.position.x + inset if i % 2 == 0 else r.end.x - inset, r.position.y + inset if i < 2 else r.end.y - inset)
		draw_circle(p, 3.4, Color(0.3, 0.34, 0.4))
		draw_circle(p, 1.6, Color(0.1, 0.11, 0.14))

func _brackets(r: Rect2, col: Color, ln: float, w: float) -> void:
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var sx: Array[float] = [1.0, -1.0, -1.0, 1.0]
	var sy: Array[float] = [1.0, 1.0, -1.0, -1.0]
	for i in 4:
		var p: Vector2 = corners[i]
		draw_line(p, p + Vector2(ln * sx[i], 0.0), col, w)
		draw_line(p, p + Vector2(0.0, ln * sy[i]), col, w)

func _hex(c: Vector2, rad: float, rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(c + Vector2.from_angle(rot + i * PI / 3.0) * rad)
	return pts

func _loop(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out

func _path_len(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	return total

func _path_point(pts: PackedVector2Array, s: float) -> Vector2:
	var rem := s
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if rem <= seg:
			return pts[i].lerp(pts[i + 1], rem / maxf(seg, 0.001))
		rem -= seg
	return pts[pts.size() - 1]

func _draw() -> void:
	if host == null:
		return
	if not ghost:
		_rbox(Rect2(rect.position + Vector2(6, 10), rect.size), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 12, 0)
	match kind:
		"Solar Panel":
			_draw_solar()
		"Reactor":
			_draw_reactor()
		"Life Support":
			_draw_life()
		"Thermal Control":
			_draw_thermal()
		"Shield":
			_draw_shield()
		"Comms":
			_draw_comms()
		_:
			_rbox(rect, Color(0.2, 0.22, 0.28), Color(0.6, 0.65, 0.75), 8, 3)
	if ghost:
		_draw_blueprint()
	elif host.is_constructing:
		_draw_scaffold()
	else:
		_draw_state()

func _draw_solar() -> void:
	var r := rect
	var c := r.get_center()
	var on := power_k
	var gold := Color(1.0, 0.8, 0.25)
	_rbox(r, Color(0.17, 0.19, 0.24), Color(0.62, 0.68, 0.78), 8, 3)
	var inner := Rect2(r.position + Vector2(12, 12), Vector2(r.size.x - 50.0, r.size.y - 24.0))
	_rbox(inner, Color(0.04, 0.06, 0.1), Color(0.02, 0.03, 0.05), 4, 2)
	var cols := 4
	var rows := 3
	var gap := 4.0
	var cw := (inner.size.x - gap * (cols + 1)) / cols
	var ch := (inner.size.y - gap * (rows + 1)) / rows
	for j in rows:
		for i in cols:
			var cr := Rect2(inner.position + Vector2(gap + i * (cw + gap), gap + j * (ch + gap)), Vector2(cw, ch))
			var wave := 0.5 + 0.5 * sin(t * 2.4 - float(i + j) * 0.8)
			var glow := on * wave
			_rbox(cr, Color(0.05, 0.1, 0.24).lerp(Color(0.1, 0.32, 0.66), glow), Color(0.5, 0.68, 0.95, 0.55), 2, 1)
			for k in range(1, 4):
				var x := cr.position.x + cw * k / 4.0
				draw_line(Vector2(x, cr.position.y + 1.0), Vector2(x, cr.end.y - 1.0), Color(0.45, 0.65, 1.0, 0.28), 1.0)
			for k in range(1, 3):
				var y := cr.position.y + ch * k / 3.0
				draw_line(Vector2(cr.position.x + 1.0, y), Vector2(cr.end.x - 1.0, y), Color(0.45, 0.65, 1.0, 0.28), 1.0)
			draw_rect(cr, Color(1.0, 0.92, 0.6, glow * 0.16))
			draw_line(cr.position + Vector2(cw * 0.2, ch * 0.9), cr.position + Vector2(cw * 0.8, ch * 0.1), Color(1, 1, 1, glow * 0.4), 1.5, true)
	var jb := Rect2(r.end.x - 34.0, c.y - 36.0, 34.0, 72.0)
	_rbox(jb, Color(0.22, 0.24, 0.3), Color(0.7, 0.74, 0.82), 4, 2)
	_rbox(jb.grow(-6.0), Color(0.07, 0.08, 0.11), Color(0, 0, 0, 0), 3, 0)
	for k in 3:
		_led(Vector2(jb.position.x + 17.0, jb.position.y + 18.0 + k * 18.0), gold if k != 1 else Color(0.3, 1.0, 0.5), on)
	draw_line(Vector2(jb.end.x - 6.0, c.y), Vector2(r.end.x + 4.0, c.y), _col(gold, 0.4 + 1.2 * on, 0.4 + 0.6 * on), 4.0, true)
	_bolts(r, 6.0)

func _draw_reactor() -> void:
	var r := rect
	var c := r.get_center()
	var energy := clampf(BaseManager.reactor_energy / 100.0, 0.0, 1.0)
	var on := power_k
	var cyan := Color(0.2, 0.95, 1.0)
	var core_col := cyan.lerp(Color(1.0, 0.3, 0.15), 1.0 - energy)
	_rbox(r, Color(0.1, 0.13, 0.17), Color(0.2, 0.75, 0.9), 14, 3)
	_rbox(r.grow(-8.0), Color(0.05, 0.07, 0.1), Color(0.14, 0.26, 0.32), 10, 1)
	for si in 2:
		var s := -1.0 if si == 0 else 1.0
		for i in 3:
			var x := c.x + s * (70.0 + i * 16.0)
			var h := 64.0
			_rbox(Rect2(x - 5.0, c.y - h * 0.5, 10.0, h), Color(0.08, 0.12, 0.16), Color(0.2, 0.3, 0.36), 3, 1)
			var fill := clampf(energy * on * (0.65 + 0.35 * sin(t * 3.0 - i * 0.8 + s)), 0.0, 1.0)
			var fh := maxf((h - 6.0) * fill, 1.0)
			_rbox(Rect2(x - 3.0, c.y + h * 0.5 - 3.0 - fh, 6.0, fh), _col(core_col, 0.5 + 0.8 * on), Color(0, 0, 0, 0), 2, 0)
		_rbox(Rect2(c.x + s * 120.0 - 6.0, c.y - 26.0, 12.0, 52.0), Color(0.03, 0.04, 0.06), Color(0.25, 0.4, 0.48), 3, 1)
	_disc(c, 47.0, Color(0.05, 0.07, 0.1), Color(0.35, 0.42, 0.5), 3.0)
	_disc(c, 39.0, Color(0.08, 0.11, 0.15), Color(0.2, 0.25, 0.3), 2.0)
	if on > 0.01:
		_glow(c, 26.0, core_col, on)
	for i in 3:
		var a := slow * (1.6 + 0.3 * i) + i * TAU / 3.0
		draw_arc(c, 33.0 - i * 5.0, a, a + 1.7, 18, Color(core_col.r, core_col.g, core_col.b, 0.25 + 0.65 * on), 3.0, true)
	var pulse := 1.0 + 0.12 * sin(t * 6.0)
	draw_circle(c, 16.0 * pulse * (0.45 + 0.55 * on), _col(core_col, 0.35 + 1.3 * on))
	draw_circle(c, 7.0, Color(1, 1, 1, 0.35 + 0.65 * on))
	draw_arc(c, 52.0, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 4.0, true)
	if energy > 0.01:
		draw_arc(c, 52.0, -PI * 0.5, -PI * 0.5 + TAU * energy, 64, _col(core_col, 1.2), 4.0, true)

func _draw_life() -> void:
	var r := rect
	var c := r.get_center()
	var on := power_k
	var teal := Color(0.2, 0.95, 0.8)
	_rbox(r, Color(0.09, 0.15, 0.17), Color(0.25, 0.8, 0.75), 12, 3)
	_rbox(r.grow(-10.0), Color(0.06, 0.1, 0.12), Color(0.12, 0.3, 0.32), 8, 1)
	_bolts(r, 10.0)
	var tpos: Array[Vector2] = [Vector2(c.x - 58.0, c.y - 62.0), Vector2(c.x + 58.0, c.y - 62.0)]
	var pipe_y := c.y + 8.0
	draw_line(Vector2(tpos[0].x, tpos[0].y + 30.0), Vector2(tpos[0].x, pipe_y), Color(0.3, 0.38, 0.42), 11.0)
	draw_line(Vector2(tpos[1].x, tpos[1].y + 30.0), Vector2(tpos[1].x, pipe_y), Color(0.3, 0.38, 0.42), 11.0)
	draw_line(Vector2(tpos[0].x, pipe_y), Vector2(tpos[1].x, pipe_y), Color(0.3, 0.38, 0.42), 11.0)
	draw_line(Vector2(c.x, pipe_y), Vector2(c.x, c.y + 24.0), Color(0.3, 0.38, 0.42), 11.0)
	draw_line(Vector2(tpos[0].x + 2.0, pipe_y - 2.0), Vector2(tpos[1].x - 2.0, pipe_y - 2.0), _col(teal, 0.3 + 0.7 * on, 0.6), 2.0)
	for ti in 2:
		var tp: Vector2 = tpos[ti]
		_disc(tp, 44.0, Color(0.1, 0.18, 0.2), Color(0.35, 0.55, 0.6), 3.0)
		_disc(tp, 36.0, Color(0.06, 0.14, 0.16), Color(0.15, 0.4, 0.42), 2.0)
		var lvl := 0.3 + 0.7 * on
		draw_circle(tp, 29.0, Color(0.05 + 0.1 * lvl, 0.2 + 0.5 * lvl, 0.2 + 0.45 * lvl, 0.95))
		if on > 0.05:
			_glow(tp, 20.0, teal, on * 0.7)
			for b in 5:
				var ph := fposmod(t * 0.45 + b * 0.2 + ti * 0.37, 1.0)
				var bp := tp + Vector2(sin(ph * 9.0 + b) * 10.0, 22.0 - ph * 46.0)
				draw_circle(bp, 2.0 + float(b % 3) * 0.7, Color(0.8, 1.0, 1.0, (1.0 - ph) * 0.7 * on))
		draw_arc(tp, 22.0, PI * 1.1, PI * 1.7, 12, Color(1, 1, 1, 0.35), 3.0, true)
		for k in 12:
			var a := k * TAU / 12.0
			draw_line(tp + Vector2.from_angle(a) * 38.0, tp + Vector2.from_angle(a) * 42.0, Color(0.5, 0.75, 0.8, 0.7), 2.0)
	var fc := Vector2(c.x, c.y + 72.0)
	_disc(fc, 50.0, Color(0.08, 0.12, 0.14), Color(0.4, 0.6, 0.65), 3.0)
	draw_circle(fc, 45.0, Color(teal.r, teal.g, teal.b, 0.1 * on))
	for b in 5:
		var a := spin + b * TAU / 5.0
		var blade := PackedVector2Array([
			fc + Vector2.from_angle(a) * 8.0,
			fc + Vector2.from_angle(a - 0.18) * 43.0,
			fc + Vector2.from_angle(a + 0.5) * 41.0,
			fc + Vector2.from_angle(a + 0.55) * 10.0])
		draw_colored_polygon(blade, Color(0.35, 0.6, 0.62).lerp(teal, on * 0.5))
	_disc(fc, 9.0, Color(0.15, 0.2, 0.22), _col(teal, 0.5 + 0.8 * on), 2.0)
	for si in 2:
		var s := -1.0 if si == 0 else 1.0
		for k in 5:
			var vx := c.x + s * (72.0 + k * 8.0)
			draw_line(Vector2(vx, c.y + 56.0), Vector2(vx, c.y + 100.0), Color(0.03, 0.06, 0.07), 3.0)

func _draw_thermal() -> void:
	var r := rect
	var on := power_k
	var hot := Color(1.0, 0.45, 0.12)
	_rbox(r, Color(0.16, 0.1, 0.08), Color(0.9, 0.4, 0.15), 10, 3)
	_rbox(r.grow(-8.0), Color(0.1, 0.07, 0.06), Color(0.3, 0.15, 0.1), 6, 1)
	for si in 2:
		var fx := r.position.x + 14.0 if si == 0 else r.end.x - 36.0
		for i in 8:
			var fy := r.position.y + 16.0 + i * 20.5
			var heat := on * (0.5 + 0.5 * sin(t * 3.0 - i * 0.6 + si * PI))
			_rbox(Rect2(fx, fy, 22.0, 12.0), Color(0.28, 0.22, 0.2).lerp(hot, heat * 0.85), Color(0.08, 0.06, 0.05), 2, 1)
	var br := Rect2(r.position + Vector2(44, 16), Vector2(r.size.x - 88.0, r.size.y - 32.0))
	_rbox(br, Color(0.07, 0.05, 0.05), Color(0.5, 0.25, 0.12), 6, 2)
	var pts := PackedVector2Array()
	var rows := 6
	for i in rows:
		var y := br.position.y + 18.0 + i * ((br.size.y - 36.0) / (rows - 1))
		var lx := br.position.x + 14.0
		var rx := br.end.x - 14.0
		if i % 2 == 0:
			pts.append(Vector2(lx, y))
			pts.append(Vector2(rx, y))
		else:
			pts.append(Vector2(rx, y))
			pts.append(Vector2(lx, y))
	draw_polyline(pts, Color(0.22, 0.13, 0.1), 9.0, true)
	draw_polyline(pts, _col(hot, 0.3 + 1.1 * on), 5.0, true)
	if on > 0.05:
		var total := _path_len(pts)
		for k in 6:
			var p := _path_point(pts, fposmod(flow + k * total / 6.0, total))
			_glow(p, 3.5, Color(1.0, 0.8, 0.4), on * 0.8)
			draw_circle(p, 3.0, Color(1.6, 1.3, 0.8, on))
	var gauge := clampf(BaseManager.temp_level / 100.0, 0.0, 1.0)
	var gc := Vector2(br.get_center().x, br.position.y - 1.0)
	draw_arc(gc, 9.0, 0.0, PI, 12, Color(0.2, 0.2, 0.25), 3.0, true)
	draw_arc(gc, 9.0, PI, PI + PI * gauge, 12, Color(0.4, 0.9, 1.0).lerp(hot, 1.0 - gauge), 3.0, true)

func _draw_shield() -> void:
	var r := rect
	var c := r.get_center()
	var on := power_k
	var vio := Color(0.65, 0.4, 1.0)
	_rbox(r, Color(0.1, 0.08, 0.16), Color(0.55, 0.35, 0.95), 12, 3)
	_rbox(r.grow(-8.0), Color(0.07, 0.05, 0.11), Color(0.25, 0.15, 0.4), 8, 1)
	_bolts(r, 11.0)
	var hr := 70.0
	var hp := _hex(c, hr)
	draw_colored_polygon(hp, Color(0.05, 0.04, 0.09))
	draw_polyline(_loop(hp), _col(vio, 0.5 + 0.8 * on), 3.0, true)
	for i in 7:
		var off := Vector2.ZERO if i == 0 else Vector2.from_angle(PI / 6.0 + (i - 1) * PI / 3.0) * 31.2
		var hc := c + off
		var pulse := 0.5 + 0.5 * sin(t * 3.0 - i * 0.9)
		var hx := _hex(hc, 17.0)
		draw_colored_polygon(hx, Color(vio.r, vio.g, vio.b, 0.08 + 0.4 * on * pulse))
		draw_polyline(_loop(hx), _col(vio, 0.45 + 0.9 * on * pulse), 2.0, true)
	for k in 6:
		var v := c + Vector2.from_angle(k * PI / 3.0) * hr
		if on > 0.05:
			_glow(v, 6.0, vio, on)
		_disc(v, 6.5, Color(0.12, 0.09, 0.2), _col(vio, 0.6 + 0.8 * on), 2.0)
		draw_circle(v, 2.5, _col(vio, 0.4 + 1.4 * on))
	for k in 12:
		var a := slow * 0.9 + k * TAU / 12.0
		draw_arc(c, 84.0, a, a + 0.32, 6, Color(vio.r, vio.g, vio.b, 0.3 + 0.6 * on), 3.0, true)
	var d := 11.0 + 2.0 * sin(t * 4.0) * on
	var diamond := PackedVector2Array([c + Vector2(0, -d * 1.4), c + Vector2(d, 0), c + Vector2(0, d * 1.4), c + Vector2(-d, 0)])
	draw_colored_polygon(diamond, _col(vio, 0.4 + 1.5 * on))
	draw_polyline(_loop(diamond), Color(1, 1, 1, 0.3 + 0.6 * on), 1.5, true)
	if on > 0.02:
		var br := 122.0 + 5.0 * sin(t * 2.0)
		draw_circle(c, br, Color(vio.r, vio.g, vio.b, 0.05 * on))
		draw_arc(c, br, 0.0, TAU, 72, Color(vio.r, vio.g, vio.b, 0.35 * on), 3.0, true)
		draw_arc(c, br - 8.0, 0.0, TAU, 72, Color(1.0, 0.8, 1.0, 0.12 * on), 1.5, true)

func _draw_comms() -> void:
	var r := rect
	var c := r.get_center()
	var on := power_k
	var pink := Color(1.0, 0.35, 0.7)
	_rbox(r, Color(0.14, 0.09, 0.13), Color(0.9, 0.3, 0.6), 10, 3)
	_rbox(r.grow(-8.0), Color(0.09, 0.06, 0.09), Color(0.3, 0.13, 0.25), 6, 1)
	var rack := Rect2(r.position + Vector2(14, 14), Vector2(52.0, r.size.y - 28.0))
	_rbox(rack, Color(0.06, 0.04, 0.07), Color(0.4, 0.2, 0.35), 4, 2)
	for i in 6:
		var ry := rack.position.y + 7.0 + i * ((rack.size.y - 14.0) / 6.0)
		_rbox(Rect2(rack.position.x + 5.0, ry, rack.size.x - 10.0, 10.0), Color(0.14, 0.1, 0.15), Color(0.3, 0.2, 0.3), 2, 1)
		_led(Vector2(rack.position.x + 13.0, ry + 5.0), pink if i % 2 == 0 else Color(0.4, 1.0, 0.6), on)
		var bar := (0.3 + 0.7 * absf(sin(t * 2.0 + i * 1.3))) * on
		draw_rect(Rect2(rack.position.x + 22.0, ry + 3.0, (rack.size.x - 32.0) * bar, 4.0), _col(pink, 0.8 + 0.6 * on))
	var dc := Vector2(r.end.x - 62.0, c.y)
	_disc(dc, 52.0, Color(0.13, 0.11, 0.14), Color(0.8, 0.8, 0.9), 3.0)
	for k in 4:
		draw_arc(dc, 44.0 - k * 10.0, 0.0, TAU, 40, Color(0.75, 0.75, 0.85, 0.2 + 0.08 * k), 2.0, true)
	for k in 10:
		var a := k * TAU / 10.0
		draw_line(dc + Vector2.from_angle(a) * 8.0, dc + Vector2.from_angle(a) * 50.0, Color(0.55, 0.55, 0.65, 0.55), 1.5)
	var aim := sin(slow * 1.1 + _phase) * 0.5
	var feed := dc + Vector2.from_angle(aim) * 34.0
	draw_line(dc, feed, Color(0.7, 0.7, 0.8), 4.0, true)
	_disc(dc, 8.0, Color(0.2, 0.2, 0.25), Color(0.8, 0.8, 0.9), 2.0)
	if on > 0.05:
		_glow(feed, 6.0, pink, on)
	_disc(feed, 6.0, Color(0.2, 0.1, 0.16), _col(pink, 0.6 + 0.9 * on), 2.0)
	if on > 0.05:
		for i in 3:
			var rr := fposmod(t * 34.0 + i * 14.0, 42.0)
			draw_arc(feed, rr + 8.0, aim - 0.7, aim + 0.7, 12, Color(pink.r, pink.g, pink.b, (1.0 - rr / 42.0) * 0.9 * on), 2.5, true)
	var blink := 1.0 if fmod(t, 1.2) < 0.2 else 0.15
	_led(Vector2(rack.end.x + 12.0, r.position.y + 18.0), Color(1.0, 0.25, 0.2), on * blink)

func _draw_state() -> void:
	var c := rect.get_center()
	var idle := 1.0 - power_k
	if idle > 0.02 and not host.is_broken:
		_rbox(rect, Color(0.01, 0.02, 0.04, 0.5 * idle), Color(0, 0, 0, 0), 8, 0)
		var blink := 0.55 + 0.45 * sin(t * 4.0)
		_bolt_icon(c, Color(1.0, 0.8, 0.2, idle * blink))
	if broken_k > 0.02:
		var fl := 0.5 + 0.5 * sin(t * 14.0)
		_rbox(rect, Color(1.0, 0.08, 0.05, 0.22 * broken_k * (0.4 + 0.6 * fl)), Color(1.0, 0.2, 0.15, broken_k * fl), 8, 3)
		_warn_icon(c, broken_k, fl)

func _bolt_icon(p: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(3, -22), Vector2(-9, 2), Vector2(-1, 2), Vector2(-4, 22), Vector2(10, -4), Vector2(2, -4)])
	for i in pts.size():
		pts[i] += p
	draw_colored_polygon(pts, col)
	draw_line(p + Vector2(-16, -20), p + Vector2(16, 20), Color(1.0, 0.2, 0.15, col.a), 3.5, true)

func _warn_icon(p: Vector2, k: float, fl: float) -> void:
	var s := 1.0 + 0.1 * fl
	var pts := PackedVector2Array([Vector2(0, -26) * s + p, Vector2(24, 18) * s + p, Vector2(-24, 18) * s + p])
	draw_colored_polygon(pts, Color(1.0, 0.15, 0.1, 0.85 * k))
	draw_polyline(_loop(pts), Color(1.0, 0.8, 0.7, k), 2.5, true)
	draw_line(p + Vector2(0, -9) * s, p + Vector2(0, 5) * s, Color(1, 1, 1, k), 4.0, true)
	draw_circle(p + Vector2(0, 12) * s, 2.8, Color(1, 1, 1, k))

func _sparks(k: float) -> void:
	rng.seed = int(t * 9.0) * 7919 + 13
	for i in 5:
		var p := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
		var d := Vector2.from_angle(rng.randf() * TAU) * (6.0 + rng.randf() * 14.0)
		draw_line(p, p + d, Color(1.8, 1.4, 0.5, k), 2.0, true)
		draw_circle(p, 2.0, Color(2.0, 1.8, 1.0, k))

func _draw_scaffold() -> void:
	var r := rect
	var cut := r.size.y * (1.0 - build_k)
	if cut > 1.0:
		_rbox(Rect2(r.position, Vector2(r.size.x, cut)), Color(0.04, 0.16, 0.28, 0.82), Color(0.3, 0.8, 1.0, 0.8), 6, 1)
		var gx := r.position.x + 16.0
		while gx < r.end.x:
			draw_line(Vector2(gx, r.position.y), Vector2(gx, r.position.y + cut), Color(0.4, 0.9, 1.0, 0.18), 1.0)
			gx += 16.0
		var gy := r.position.y + 16.0
		while gy < r.position.y + cut:
			draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Color(0.4, 0.9, 1.0, 0.18), 1.0)
			gy += 16.0
	var sy := r.position.y + cut
	draw_line(Vector2(r.position.x, sy), Vector2(r.end.x, sy), Color(0.5, 1.6, 2.0, 0.95), 3.0, true)
	_brackets(r.grow(6.0), Color(0.5, 1.4, 1.8, 0.6 + 0.4 * sin(t * 8.0)), 22.0, 3.0)

func _draw_blueprint() -> void:
	var r := rect
	var gx := r.position.x + 32.0
	while gx < r.end.x - 1.0:
		draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), Color(1, 1, 1, 0.14), 1.0)
		gx += 32.0
	var gy := r.position.y + 32.0
	while gy < r.end.y - 1.0:
		draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Color(1, 1, 1, 0.14), 1.0)
		gy += 32.0
	draw_line(r.position, r.end, Color(1, 1, 1, 0.1), 1.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(1, 1, 1, 0.1), 1.0)
	draw_rect(r, Color(1, 1, 1, 0.55), false, 2.0)
	_brackets(r.grow(8.0), Color(1, 1, 1, 0.9), 26.0, 3.0)
