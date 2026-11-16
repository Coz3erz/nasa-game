@tool
extends Node2D
## CRASHED SHIP - attach to any Node2D. Draws a wrecked spaceship at the node's position:
## snapped hull, torn wing, exposed cables, scorched gouge trail, scattered debris,
## plus (all optional) collision, light occluders, smoke / fire / sparks and a flickering glow.
##
## * Nose points along +X, the gouge trail runs behind it (-X). ROTATE THE NODE to aim it.
## * Everything is drawn once (cached) - only a few particles animate, and they switch off
##   automatically when the wreck is off-screen.
## * It is a @tool script: tweak exports in the editor and it updates live.

@export_group("Ship")
@export var ship_length: float = 380.0:
	set(v):
		ship_length = v
		_request_rebuild()
@export var hull_color: Color = Color(0.46, 0.50, 0.56):
	set(v):
		hull_color = v
		_request_rebuild()
@export var accent_color: Color = Color(0.95, 0.45, 0.18):
	set(v):
		accent_color = v
		_request_rebuild()
@export var ship_name: String = "ARES-7":   ## painted on the hull, empty = none
	set(v):
		ship_name = v
		_request_rebuild()
@export var random_seed: int = 1337:
	set(v):
		random_seed = v
		_request_rebuild()

@export_group("Ground & Debris")
@export var trail_length: float = 560.0:
	set(v):
		trail_length = v
		_request_rebuild()
@export var debris_count: int = 26:
	set(v):
		debris_count = v
		_request_rebuild()
@export var ground_tint: Color = Color(0.50, 0.22, 0.12):
	set(v):
		ground_tint = v
		_request_rebuild()

@export_group("Collision")
@export var enable_collision: bool = true:
	set(v):
		enable_collision = v
		_request_rebuild()
@export_flags_2d_physics var collision_layer_bits: int = 1:
	set(v):
		collision_layer_bits = v
		_request_rebuild()
@export var casts_shadows: bool = true:   ## LightOccluder2D on the hull
	set(v):
		casts_shadows = v
		_request_rebuild()

@export_group("Effects")
@export var effects_enabled: bool = true:
	set(v):
		effects_enabled = v
		_request_rebuild()
@export var fire_light: bool = true:
	set(v):
		fire_light = v
		_request_rebuild()
@export var light_energy: float = 1.1:
	set(v):
		light_energy = v
		_request_rebuild()

@export_tool_button("Rebuild", "Reload") var rebuild_now = _rebuild

# ship-unit geometry (nose = +X, about 440 units long; scaled by ship_length / 440)
const FR_ROT := -0.07
const FR_OFF := Vector2(14, -6)
const RE_ROT := 0.10
const RE_OFF := Vector2(-10, 8)
const FRONT := [Vector2(-26,-60), Vector2(60,-70), Vector2(130,-52), Vector2(190,-22), Vector2(212,0), Vector2(190,22), Vector2(130,52), Vector2(60,70), Vector2(-26,60), Vector2(-12,42), Vector2(-34,28), Vector2(-14,10), Vector2(-32,-6), Vector2(-10,-24), Vector2(-30,-40)]
const FRONT_BREAK := [Vector2(-26,60), Vector2(-12,42), Vector2(-34,28), Vector2(-14,10), Vector2(-32,-6), Vector2(-10,-24), Vector2(-30,-40), Vector2(-26,-60)]
const FRONT_COL := [Vector2(-26,-60), Vector2(60,-70), Vector2(130,-52), Vector2(190,-22), Vector2(212,0), Vector2(190,22), Vector2(130,52), Vector2(60,70), Vector2(-26,60)]
const REAR := [Vector2(-62,-58), Vector2(-120,-66), Vector2(-190,-56), Vector2(-216,-40), Vector2(-216,40), Vector2(-190,56), Vector2(-120,66), Vector2(-62,58), Vector2(-44,38), Vector2(-66,22), Vector2(-42,4), Vector2(-64,-14), Vector2(-46,-32), Vector2(-66,-46)]
const REAR_BREAK := [Vector2(-62,58), Vector2(-44,38), Vector2(-66,22), Vector2(-42,4), Vector2(-64,-14), Vector2(-46,-32), Vector2(-66,-46), Vector2(-62,-58)]
const REAR_COL := [Vector2(-62,-58), Vector2(-120,-66), Vector2(-190,-56), Vector2(-216,-40), Vector2(-216,40), Vector2(-190,56), Vector2(-120,66), Vector2(-62,58)]
const WING_UP := [Vector2(-40,-60), Vector2(-85,-150), Vector2(-150,-175), Vector2(-172,-160), Vector2(-142,-100), Vector2(-112,-60)]
const WING_STUB := [Vector2(36,62), Vector2(12,100), Vector2(-6,94), Vector2(-10,112), Vector2(-24,62)]
const WING_CHUNK := [Vector2(-50,-20), Vector2(40,-24), Vector2(58,-4), Vector2(46,14), Vector2(-42,22), Vector2(-58,6)]
const GLASS := [Vector2(112,-20), Vector2(158,-12), Vector2(172,0), Vector2(158,12), Vector2(112,20), Vector2(96,0)]

var _s := 1.0
var _debris: Array = []
var _dirty := false
var _emitters: Array = []
var _light: PointLight2D = null
var _onscreen := true
var _font: SystemFont
static var _soft_tex: GradientTexture2D = null
static var _blob_tex: GradientTexture2D = null

# ───────────────────────────────────────────────────────── lifecycle ──
func _ready() -> void:
	set_notify_transform(true)
	_rebuild()

func _request_rebuild() -> void:
	if not is_inside_tree() or _dirty:
		return
	_dirty = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	_s = ship_length / 440.0
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Courier New", "monospace"])
	_generate()
	_clear_generated()
	_build_nodes()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		for e in _emitters:                       # smoke always rises straight up on screen
			if is_instance_valid(e):
				e.global_rotation = 0.0

func _process(_d: float) -> void:
	if _light != null and is_instance_valid(_light):
		var t := Time.get_ticks_msec() * 0.001
		var flick := 0.82 + 0.12 * sin(t * 11.0) + 0.06 * sin(t * 27.0 + 1.3)
		_light.energy = light_energy * flick

# ──────────────────────────────────────────────────────────── helpers ──
static func _tp(pts, rot: float, off: Vector2, s: float) -> PackedVector2Array:
	var xf := Transform2D(rot, off)
	var out := PackedVector2Array()
	for p in pts:
		out.append((xf * p) * s)
	return out

func _pt(p: Vector2, rot: float, off: Vector2) -> Vector2:
	return (Transform2D(rot, off) * p) * _s

static func _centroid(pts) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / maxf(1.0, float(pts.size()))

func _base_xf() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))

func _sec_xf(rot: float, off: Vector2) -> void:
	draw_set_transform(off * _s, rot, Vector2(_s, _s))

func _closed(pts) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out

func _scaled(pts, k: float, shift: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var c := _centroid(pts)
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k + shift)
	return out

# ───────────────────────────────────────────────────── debris layout ──
func _generate() -> void:
	_debris.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var trail_u := trail_length / _s
	var big_target := maxi(2, debris_count / 8)
	var bigs := 0
	for i in debris_count:
		var kind := rng.randi_range(0, 3)
		var big := false
		if bigs < big_target and i % 4 == 0:
			kind = 4
			big = true
			bigs += 1
		var t := pow(rng.randf(), 1.4)
		var x := lerpf(170.0, -trail_u * 0.85, t)
		var spread := 60.0 + (170.0 - x) * 0.14
		var y := clampf(rng.randfn(0.0, spread), -300.0, 300.0)
		if absf(y) < 84.0 and x > -250.0 and x < 230.0:      # keep clear of the hull
			y = signf(y if y != 0.0 else 1.0) * (90.0 + rng.randf() * 40.0)
		var size := rng.randf_range(9.0, 24.0)
		if big:
			size = rng.randf_range(30.0, 46.0)
		var shade := rng.randf_range(0.55, 1.05) if rng.randf() > 0.3 else rng.randf_range(0.22, 0.4)
		var pts := PackedVector2Array()
		var n := rng.randi_range(4, 6)
		for k in n:                                      # star-shaped = always a simple polygon
			var a := TAU * float(k) / float(n) + rng.randf_range(-0.2, 0.2)
			var r := size * rng.randf_range(0.55, 1.0)
			var sq := Vector2(1.0, 1.0)
			if kind == 1:
				sq = Vector2(2.2, 0.28)
			elif kind == 2:
				sq = Vector2(1.2, 0.7)
			pts.append(Vector2(cos(a) * sq.x, sin(a) * sq.y) * r)
		_debris.append({"pos": Vector2(x, y), "rot": rng.randf() * TAU, "kind": kind, "size": size, "shade": shade, "pts": pts, "big": big})
	# the torn-off wing lies off to one side
	_debris.append({"pos": Vector2(-150, 178), "rot": 0.55, "kind": 5, "size": 58.0, "shade": 0.9, "pts": PackedVector2Array(WING_CHUNK), "big": true})

# ───────────────────────────────────────────────────────────── drawing ──
func _draw() -> void:
	if _s <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed + 99
	_draw_ground(rng)
	_draw_debris(true)       # shadows first
	_draw_debris(false)
	_draw_ship(rng)
	_draw_text()

func _draw_ground(rng: RandomNumberGenerator) -> void:
	_base_xf()
	var trail_u := trail_length / _s
	var x_far := -trail_u
	var x_near := -70.0                        # runs UNDER the hull so there is never a visible end cap
	var gouge := Color(0.07, 0.03, 0.02)
	var dirt_hi := Color(minf(ground_tint.r * 1.3, 1.0), minf(ground_tint.g * 1.25, 1.0), minf(ground_tint.b * 1.2, 1.0))
	var dirt_lo := Color(ground_tint.r * 0.55, ground_tint.g * 0.5, ground_tint.b * 0.5)
	var wobble := rng.randf() * TAU
	# broad soft gouge: many feathered blobs, fading in smoothly from nothing
	for i in 110:
		var t := pow(rng.randf(), 0.85)
		var x := lerpf(x_far, x_near, t)
		var w := lerpf(12.0, 62.0, t)
		var y := sin(x * 0.012 + wobble) * 10.0 * (1.0 - t) + rng.randfn(0.0, w * 0.42)
		var fade := smoothstep(0.0, 0.35, t)
		var sz := Vector2(rng.randf_range(70.0, 140.0), rng.randf_range(44.0, 100.0)) * lerpf(0.55, 1.15, t)
		_blob(Vector2(x, y), sz, Color(gouge.r, gouge.g, gouge.b, rng.randf_range(0.16, 0.30) * fade), rng.randf_range(-0.15, 0.15))
	# long thin soot streaks (feathered, never a line with a cap)
	for i in 7:
		var t := rng.randf_range(0.3, 1.0)
		var x := lerpf(x_far, x_near, t)
		_blob(Vector2(x, rng.randf_range(-34.0, 34.0) * t), Vector2(rng.randf_range(180.0, 320.0), rng.randf_range(8.0, 16.0)), Color(0, 0, 0, 0.17 * smoothstep(0.0, 0.4, t)))
	# dirt berms thrown up along both sides, irregular and broken up
	for side: float in [-1.0, 1.0]:
		for i in 38:
			var t := pow(rng.randf(), 0.9)
			if rng.randf() < 0.25:
				continue                                         # gaps so it isn't a clean ridge
			var x := lerpf(x_far, x_near - 40.0, t)
			var w := lerpf(12.0, 62.0, t)
			var y := side * (w + rng.randf_range(2.0, 16.0)) + rng.randfn(0.0, 3.0)
			var fade := smoothstep(0.05, 0.4, t)
			var r := rng.randf_range(16.0, 34.0) * lerpf(0.6, 1.1, t)
			_blob(Vector2(x, y + 3.0), Vector2(r * 1.5, r), Color(dirt_lo.r, dirt_lo.g, dirt_lo.b, 0.26 * fade))
			_blob(Vector2(x - 2.0, y - 2.0), Vector2(r * 1.2, r * 0.8), Color(dirt_hi.r, dirt_hi.g, dirt_hi.b, 0.2 * fade))
	# scorch pool under / behind the engines: clustered, uneven, feathered
	for i in 16:
		var p := Vector2(rng.randfn(-215.0, 38.0), rng.randfn(8.0, 30.0))
		_blob(p, Vector2(rng.randf_range(80.0, 170.0), rng.randf_range(60.0, 120.0)), Color(0, 0, 0, rng.randf_range(0.08, 0.15)), rng.randf_range(-0.4, 0.4))
	for i in 6:
		_blob(Vector2(rng.randfn(-225.0, 18.0), rng.randfn(8.0, 14.0)), Vector2(70.0, 55.0), Color(0, 0, 0, 0.08))
	# dirt shoved up in front of the nose
	for i in 9:
		var p := Vector2(228.0 + rng.randf_range(-10.0, 34.0), rng.randfn(0.0, 30.0))
		var r := rng.randf_range(14.0, 30.0)
		_blob(p + Vector2(2, 4), Vector2(r * 1.7, r * 1.3), Color(dirt_lo.r, dirt_lo.g, dirt_lo.b, 0.30))
		_blob(p + Vector2(-2, -3), Vector2(r * 1.2, r * 0.9), Color(dirt_hi.r, dirt_hi.g, dirt_hi.b, 0.22))

func _draw_debris(shadow: bool) -> void:
	for d in _debris:
		var pos: Vector2 = d["pos"]
		var pts: PackedVector2Array = d["pts"]
		var sh: float = d["shade"]
		var kind: int = d["kind"]
		if shadow:
			var sz: float = d["size"]
			_blob(pos + Vector2(5, 7), Vector2(sz * 2.0, sz * 1.5), Color(0, 0, 0, 0.13))          # soft contact shadow
			draw_set_transform((pos + Vector2(4, 6)) * _s, d["rot"], Vector2(_s, _s))
			draw_colored_polygon(pts, Color(0, 0, 0, 0.22))
			continue
		draw_set_transform(pos * _s, d["rot"], Vector2(_s, _s))
		var col := Color(hull_color.r * sh, hull_color.g * sh, hull_color.b * sh, 1.0)
		if kind == 4 or kind == 5:
			col = Color(hull_color.r * 0.9, hull_color.g * 0.9, hull_color.b * 0.9)
		draw_colored_polygon(pts, col)
		if kind == 0 or kind == 4 or kind == 5:
			draw_colored_polygon(_scaled(pts, 0.6, Vector2(-1.5, -1.5)), Color(1, 1, 1, 0.12))
		if kind == 2:
			draw_line(pts[0] * 0.5, pts[2] * 0.5, Color(accent_color.r, accent_color.g, accent_color.b, 0.85), 2.0)
		if kind == 4 or kind == 5:                         # torn edge, still hot
			draw_polyline(_closed(pts), Color(0.06, 0.05, 0.05, 1), 2.5, true)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), Color(1.0, 0.48, 0.14, 0.9), 2.0, true)
			if kind == 5:
				draw_line(Vector2(-40, 2), Vector2(40, -2), Color(accent_color.r, accent_color.g, accent_color.b, 0.9), 4.0)
		else:
			draw_polyline(_closed(pts), Color(0.05, 0.05, 0.06, 0.9), 1.5, true)
	_base_xf()

func _draw_hull_piece(pts, break_pts, base: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), base)
	draw_colored_polygon(_scaled(pts, 0.72, Vector2(-5, -6)), Color(1, 1, 1, 0.10))     # sun-lit top
	draw_colored_polygon(_scaled(pts, 0.45, Vector2(8, 10)), Color(0, 0, 0, 0.14))      # shaded belly
	draw_polyline(_closed(pts), Color(0.07, 0.07, 0.09, 1.0), 3.0, true)
	if break_pts.size() >= 2:
		draw_polyline(PackedVector2Array(break_pts), Color(1.0, 0.48, 0.14, 0.95), 2.6, true)  # glowing torn edge

func _draw_ship(rng: RandomNumberGenerator) -> void:
	var dark := Color(hull_color.r * 0.62, hull_color.g * 0.62, hull_color.b * 0.66)
	var base := hull_color
	# drop shadow of the whole wreck
	for part in [[FRONT, FR_ROT, FR_OFF], [REAR, RE_ROT, RE_OFF], [WING_UP, RE_ROT, RE_OFF]]:
		for i in 6:                                        # stacked, growing, fading copies = soft shadow edge
			_sec_xf(part[1], part[2] + Vector2(5.0 + i * 2.4, 8.0 + i * 3.4))
			draw_colored_polygon(_scaled(part[0], 1.0 + i * 0.035), Color(0, 0, 0, 0.085))
	_base_xf()
	_blob(Vector2(-20, 14), Vector2(560, 210), Color(0, 0, 0, 0.14))      # wide ambient occlusion under the whole wreck
	# exposed interior between the two halves
	_base_xf()
	draw_colored_polygon(PackedVector2Array([Vector2(-72,-52), Vector2(-20,-54), Vector2(-20,54), Vector2(-72,50)]), Color(0.03, 0.03, 0.04))
	for i in 4:                                              # ribs
		var x := -66.0 + i * 11.0
		draw_line(Vector2(x, -46), Vector2(x + rng.randf_range(-3, 3), 46), Color(0.25, 0.26, 0.3), 2.0)
	var cable_cols := [Color(0.9, 0.2, 0.2), Color(0.25, 0.55, 1.0), Color(1.0, 0.8, 0.2)]
	for i in 3:                                              # hanging cables
		var y := -30.0 + i * 24.0
		var pl := PackedVector2Array()
		for k in 9:
			var t := float(k) / 8.0
			pl.append(Vector2(lerpf(-60.0, -24.0, t), y) + Vector2(0, sin(t * PI) * (10.0 + i * 4.0)))
		draw_polyline(pl, cable_cols[i], 2.0, true)

	# ── rear half: engines + upper wing ──
	_sec_xf(RE_ROT, RE_OFF)
	for sgn in [-1.0, 1.0]:
		draw_rect(Rect2(-242, 12 * sgn - (0 if sgn > 0 else 32), 28, 32), Color(0.1, 0.1, 0.12))
		draw_rect(Rect2(-238, 16 * sgn - (0 if sgn > 0 else 24), 18, 24), Color(1.0, 0.42, 0.12, 0.95))
		for k in 3:
			_blob(Vector2(-262 - rng.randf_range(0, 24), 28 * sgn + (k - 1) * 11), Vector2(rng.randf_range(60, 110), 12), Color(0, 0, 0, 0.16))
	_draw_hull_piece(WING_UP, [], Color(base.r * 0.9, base.g * 0.9, base.b * 0.95))
	for k in 3:                                              # wing ribs
		var f := 0.25 + k * 0.22
		draw_line(Vector2(lerpf(-45, -150, f), lerpf(-62, -166, f)), Vector2(lerpf(-108, -168, f), lerpf(-62, -150, f)), Color(0, 0, 0, 0.35), 1.5)
	_draw_hull_piece(REAR, REAR_BREAK, base)
	draw_rect(Rect2(-216, -8, 150, 16), Color(accent_color.r, accent_color.g, accent_color.b, 0.9))    # livery stripe
	for x in [-100.0, -150.0]:
		draw_line(Vector2(x, -52), Vector2(x, 52), Color(0, 0, 0, 0.3), 1.5)
	for i in 6:                                                         # soot smudges
		_blob(Vector2(rng.randf_range(-205, -75), rng.randf_range(-44, 44)), Vector2(rng.randf_range(36, 80), rng.randf_range(24, 50)), Color(0, 0, 0, 0.16), rng.randf_range(-0.5, 0.5))
	draw_colored_polygon(PackedVector2Array([Vector2(-150, 30), Vector2(-118, 34), Vector2(-112, 52), Vector2(-146, 54)]), Color(dark.r, dark.g, dark.b, 0.9))   # missing access panel
	# ── front half: cockpit + wing stub ──
	_sec_xf(FR_ROT, FR_OFF)
	_draw_hull_piece(WING_STUB, [], Color(base.r * 0.9, base.g * 0.9, base.b * 0.95))
	draw_polyline(PackedVector2Array([Vector2(-24, 62), Vector2(-10, 110), Vector2(-6, 94)]), Color(1.0, 0.48, 0.14, 0.95), 2.4, true)
	_draw_hull_piece(FRONT, FRONT_BREAK, base)
	draw_rect(Rect2(-14, -8, 200, 16), Color(accent_color.r, accent_color.g, accent_color.b, 0.9))
	for x in [40.0, 96.0]:
		draw_line(Vector2(x, -50), Vector2(x, 50), Color(0, 0, 0, 0.3), 1.5)
	draw_colored_polygon(PackedVector2Array(GLASS), Color(0.07, 0.16, 0.22, 0.97))                  # cockpit
	draw_colored_polygon(PackedVector2Array([Vector2(118, -16), Vector2(152, -9), Vector2(120, -2)]), Color(0.5, 0.85, 1.0, 0.30))
	draw_polyline(_closed(GLASS), Color(0.05, 0.05, 0.07), 3.0, true)
	for c in [[Vector2(150, -8), Vector2(126, 5)], [Vector2(150, -8), Vector2(162, 7)], [Vector2(140, -3), Vector2(128, -15)]]:
		draw_line(c[0], c[1], Color(1, 1, 1, 0.65), 1.2)                                           # cracks
	for i in 5:
		_blob(Vector2(rng.randf_range(10, 180), rng.randf_range(-42, 42)), Vector2(rng.randf_range(34, 76), rng.randf_range(22, 46)), Color(0, 0, 0, 0.15), rng.randf_range(-0.5, 0.5))   # scorch marks
	_base_xf()

func _draw_text() -> void:
	if ship_name == "" or _font == null:
		return
	_sec_xf(RE_ROT, RE_OFF)
	draw_string(_font, Vector2(-196, -18), ship_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.95, 1.0, 0.75))
	_base_xf()

# ──────────────────────────────────────────────── collision + effects ──
func _clear_generated() -> void:
	for c in get_children():
		if c.has_meta("crash_gen"):
			remove_child(c)
			c.queue_free()
	_emitters.clear()
	_light = null
	set_process(false)

func _tag(n: Node) -> Node:
	n.set_meta("crash_gen", true)
	return n

func _build_nodes() -> void:
	var front_pts := _tp(FRONT_COL, FR_ROT, FR_OFF, _s)
	var rear_pts := _tp(REAR_COL, RE_ROT, RE_OFF, _s)
	var wing_pts := _tp(WING_UP, RE_ROT, RE_OFF, _s)
	var stub_pts := _tp(WING_STUB, FR_ROT, FR_OFF, _s)

	if enable_collision:
		var body := StaticBody2D.new()
		body.name = "CrashBody"
		body.collision_layer = collision_layer_bits
		body.collision_mask = 0
		add_child(_tag(body))
		for pts in [front_pts, rear_pts, wing_pts, stub_pts]:
			_add_convex(body, pts)
		for d in _debris:
			if d["big"]:
				var cs := CollisionShape2D.new()
				var c := CircleShape2D.new()
				c.radius = float(d["size"]) * 0.42 * _s
				cs.shape = c
				cs.position = (d["pos"] as Vector2) * _s
				body.add_child(cs)

	if casts_shadows:
		for pts in [front_pts, rear_pts, wing_pts]:
			var occ := LightOccluder2D.new()
			var op := OccluderPolygon2D.new()
			op.polygon = PackedVector2Array(_hull_order(pts))
			occ.occluder = op
			add_child(_tag(occ))

	if effects_enabled:
		_build_effects()

	var trail_px := trail_length
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-trail_px - 80.0 * _s, -320.0 * _s, trail_px + 400.0 * _s, 640.0 * _s)
	notifier.screen_entered.connect(_set_active.bind(true))
	notifier.screen_exited.connect(_set_active.bind(false))
	add_child(_tag(notifier))

static func _hull_order(pts: PackedVector2Array) -> PackedVector2Array:
	var h := Geometry2D.convex_hull(pts)
	if h.size() > 3 and h[0] == h[h.size() - 1]:
		h.remove_at(h.size() - 1)
	return h

func _add_convex(body: StaticBody2D, pts: PackedVector2Array) -> void:
	var cs := CollisionShape2D.new()
	var sh := ConvexPolygonShape2D.new()
	sh.set_point_cloud(pts)
	cs.shape = sh
	body.add_child(cs)

## smooth gaussian-ish falloff: used for every shadow / scorch / soot so nothing has a hard edge
func _blob_texture() -> GradientTexture2D:
	if _blob_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.78), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.0)])
		_blob_tex = GradientTexture2D.new()
		_blob_tex.gradient = g
		_blob_tex.fill = GradientTexture2D.FILL_RADIAL
		_blob_tex.fill_from = Vector2(0.5, 0.5)
		_blob_tex.fill_to = Vector2(1.0, 0.5)
		_blob_tex.width = 128
		_blob_tex.height = 128
	return _blob_tex

func _blob(pos: Vector2, size: Vector2, col: Color, rot: float = 0.0) -> void:
	if rot != 0.0:
		draw_set_transform(pos * _s, rot, Vector2(_s, _s))
		draw_texture_rect(_blob_texture(), Rect2(-size * 0.5, size), false, col)
		_base_xf()
	else:
		draw_texture_rect(_blob_texture(), Rect2(pos - size * 0.5, size), false, col)

func _tex() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(1.0, 0.5)
		_soft_tex.width = 64
		_soft_tex.height = 64
	return _soft_tex

func _fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.18, Color(1, 1, 1, 1))
	return g

func _emitter(pos: Vector2, add: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _tex()
	p.position = pos
	p.local_coords = false
	p.direction = Vector2(0, -1)
	p.z_index = 5
	p.color_ramp = _fade_ramp()
	if add:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	add_child(_tag(p))
	p.global_rotation = 0.0
	_emitters.append(p)
	return p

func _build_effects() -> void:
	var break_pos := _pt(Vector2(-48, 0), RE_ROT, RE_OFF)
	var eng_a := _pt(Vector2(-238, -28), RE_ROT, RE_OFF)
	var eng_b := _pt(Vector2(-238, 28), RE_ROT, RE_OFF)
	var nose := _pt(Vector2(90, -40), FR_ROT, FR_OFF)
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.0))
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1.0))
	shrink.add_point(Vector2(1, 0.15))

	for pos in [break_pos, eng_a, nose]:                     # smoke columns
		var s := _emitter(pos, false)
		s.amount = 11
		s.lifetime = 4.0
		s.preprocess = 4.0
		s.spread = 18.0
		s.initial_velocity_min = 10.0
		s.initial_velocity_max = 22.0
		s.gravity = Vector2(5, -9)
		s.scale_amount_min = 0.5 * _s * 2.0
		s.scale_amount_max = 1.0 * _s * 2.0
		s.scale_amount_curve = grow
		s.color = Color(0.14, 0.14, 0.17, 0.62)
		s.emitting = true
	for pos in [break_pos, eng_b]:                           # flames
		var f := _emitter(pos, true)
		f.amount = 10
		f.lifetime = 0.8
		f.preprocess = 0.8
		f.spread = 22.0
		f.initial_velocity_min = 12.0
		f.initial_velocity_max = 30.0
		f.gravity = Vector2(0, -22)
		f.scale_amount_min = 0.22 * _s * 2.0
		f.scale_amount_max = 0.42 * _s * 2.0
		f.scale_amount_curve = shrink
		f.color = Color(1.9, 0.62, 0.15, 0.95)
		f.emitting = true
	var sp := _emitter(break_pos, true)                      # sparks from the torn hull
	sp.amount = 6
	sp.lifetime = 1.5
	sp.preprocess = 1.5
	sp.spread = 80.0
	sp.initial_velocity_min = 40.0
	sp.initial_velocity_max = 95.0
	sp.gravity = Vector2(0, 170)
	sp.scale_amount_min = 0.03
	sp.scale_amount_max = 0.06
	sp.color = Color(3.0, 1.9, 0.7, 1.0)
	sp.emitting = true

	if fire_light:
		_light = PointLight2D.new()
		_light.texture = _tex()
		_light.position = break_pos
		_light.texture_scale = 7.0 * _s
		_light.color = Color(1.0, 0.55, 0.25)
		_light.energy = light_energy
		_light.z_index = 5
		add_child(_tag(_light))
		set_process(true)

func _set_active(on: bool) -> void:
	_onscreen = on
	for e in _emitters:
		if is_instance_valid(e):
			e.emitting = on
	set_process(on and _light != null)
