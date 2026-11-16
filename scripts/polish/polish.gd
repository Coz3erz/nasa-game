extends Node
## POLISH - drop-in visual layer for the Game scene (autoload).
## Adds: bloom, ambient lighting + shadows, module glow, dust/spark particles,
## CRT/vignette post FX, themed shop UI (cutscene font), survival HUD, alerts.
## It only READS existing game state. It never edits game scripts or the cutscene.

const GAME_SCENE := "game.tscn"
## Name of the Game-node property that holds your shop CanvasLayer. If it's missing/renamed,
## Polish falls back to auto-detecting any other CanvasLayer under the Game node.
const SHOP_PROPERTY := "shop_layer"
## Buttons whose text contains one of these words get the "primary" pulse.
## (Or tag any node yourself:  node.set_meta("polish_primary", true) )
## To exclude any node + its children from Polish:  node.set_meta("no_polish", true)
const PRIMARY_WORDS := ["CONFIRM", "DEPLOY", "LAUNCH", "START", "BEGIN", "PLAY"]
const GLOW := 1.12   # HDR multiplier for glowing things (1.0 = no bloom from them)

const C_BG      := Color(0.04, 0.06, 0.09, 0.96)
const C_PANEL   := Color(0.06, 0.09, 0.13, 0.92)
const C_EDGE    := Color(0.20, 0.75, 0.95, 0.85)
const C_GREEN   := Color(0.40, 1.00, 0.55)
const C_CYAN    := Color(0.30, 0.85, 1.00)
const C_AMBER   := Color(1.00, 0.85, 0.30)
const C_RED     := Color(1.00, 0.25, 0.20)

var font: Font
var mono: Font
var ui_theme: Theme
var soft_tex: GradientTexture2D
var ring_tex: GradientTexture2D

var _scene: Node = null
var _installed := false
var _game: Node2D
var _t := 0.0

# lighting
var _modulate: CanvasModulate
var _player_light: PointLight2D
var _reactor_light: PointLight2D
var _module_lights: Dictionary = {}   # module -> PointLight2D
var _dust: CPUParticles2D
var _sparks: CPUParticles2D

# shop
var _shop_seen: CanvasLayer = null
var _shop_labels: Dictionary = {}   # Label -> [last_text, base_modulate]
var _card_idx := 0
var _fx_layer: CanvasLayer
var _fx_dust: CPUParticles2D
var _fx_bokeh: CPUParticles2D
var _fx_embers: CPUParticles2D
var _fx_size := Vector2.ZERO

# hud
var _hud: CanvasLayer
var _bars: Dictionary = {}
var _alert_box: VBoxContainer
var _crit_label: Label
var _crit_flash: ColorRect
var _crit_time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = GameFont.get_font()
	mono = GameFont.get_font()
	soft_tex = _radial_tex(256, 0.0)
	ring_tex = _radial_tex(64, 0.0)
	ui_theme = _build_theme()
	get_tree().node_added.connect(_on_node_added)
	GameSettings.quality_changed.connect(_apply_quality)

func _process(delta: float) -> void:
	_t += delta
	var cs := get_tree().current_scene
	if cs != _scene:
		_scene = cs
		_installed = false
		_teardown()
		if cs != null and cs.scene_file_path.get_file() in [GAME_SCENE, "tutorial.tscn"]:
			_install(cs)
	if not _installed or get_tree().paused:
		return
	_update_lighting(delta)
	_update_particles()
	_update_shop(delta)
	_update_hud(delta)

func _teardown() -> void:
	# The root viewport outlives scenes. Reset before another scene draws.
	GameSettings.set_hdr_preference(false)
	_post_rect = null
	_post_mat = null
	_module_lights.clear()
	_shop_labels.clear()
	_shop_seen = null
	_bars.clear()
	_crit_time = 0.0

# - install -
func _install(game: Node) -> void:
	_game = game as Node2D
	_installed = true
	_setup_environment()
	_setup_lighting()
	_setup_particles()
	_setup_post_fx()
	_setup_hud()
	_apply_quality()
	# connect signals once per install
	if not EventBus.module_broken.is_connected(_on_module_broken):
		EventBus.module_broken.connect(_on_module_broken)
	if not EventBus.game_over.is_connected(_on_game_over):
		EventBus.game_over.connect(_on_game_over)
	for n in _game.get_children():
		_style_existing(n)

func _style_existing(n: Node) -> void:
	if n is Line2D:
		_bloom_wire(n)

func _on_node_added(n: Node) -> void:
	if not _installed or not is_instance_valid(_game) or not _game.is_ancestor_of(n):
		return
	if n is Control and is_instance_valid(_shop_seen) and _shop_seen.is_ancestor_of(n):
		_decorate_control.call_deferred(n)
		return
	if n is ProgressBar:
		if not (n.get_parent() is Container):   # module repair/build bars only (HUD bars are themed already)
			(n as ProgressBar).theme = ui_theme
	elif n is Line2D:
		_bloom_wire.call_deferred(n)

func _bloom_wire(l: Line2D) -> void:
	if not is_instance_valid(l):
		return
	# real wire (opaque colour) gets an HDR boost so bloom picks it up; shadow line is left alone
	if l.default_color.a > 0.9 and l.width >= 8.0:
		l.modulate = Color(GLOW, GLOW, GLOW, 1.0)

# - environment/bloom -
func _setup_environment() -> void:
	GameSettings.set_hdr_preference(true)
	var we := _game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		_game.add_child(we)
	var env := we.environment.duplicate() as Environment if we.environment != null else Environment.new()
	# duplicate() also copies metadata from the scene's previous environment.
	# Snapshot the configured Polish defaults, not that resource's older profile.
	if env.has_meta("crashfall_defaults"):
		env.remove_meta("crashfall_defaults")
	we.environment = env
	env.background_mode = Environment.BG_CANVAS      # required for 2D glow
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR   # keep your original colours
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 0.45
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.15
	env.glow_hdr_scale = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in range(7):
		env.set_glow_level(i, 1.0 if i in [1, 2, 4] else 0.55)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	GameSettings._apply_visual_node(we)

# - lighting -
func _setup_lighting() -> void:
	_modulate = CanvasModulate.new()
	_modulate.name = "AmbientDark"
	_modulate.color = Color(0.36, 0.40, 0.52)
	_game.add_child(_modulate)

	# soft blob shadow under the player (fake contact shadow)
	var player := _game.get_node_or_null("Player") as Node2D
	if player != null:
		var blob := Sprite2D.new()
		blob.name = "BlobShadow"
		blob.texture = soft_tex
		blob.modulate = Color(0, 0, 0, 0.55)
		blob.scale = Vector2(0.28, 0.12)
		blob.position = Vector2(0, 30)
		blob.show_behind_parent = true
		player.add_child(blob)

		_player_light = _make_light(Color(0.75, 0.92, 1.0), 1.25, 3.2, true)
		_player_light.name = "PlayerTorch"
		_player_light.position = Vector2(0, -6)
		player.add_child(_player_light)

	var reactor := _game.get_node_or_null("Reactor") as Node2D
	if reactor != null:
		_reactor_light = _make_light(Color(0.2, 0.85, 1.0), 1.3, 4.2, false)
		_reactor_light.name = "ReactorGlow"
		_reactor_light.position = Vector2(64, 64)
		reactor.add_child(_reactor_light)
		_add_occluder_from_body(reactor)

	_build_wall_occluders_and_lamps()

func _make_light(col: Color, energy: float, scl: float, shadows: bool) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = soft_tex
	l.texture_scale = scl
	l.color = col
	l.energy = energy
	l.shadow_enabled = shadows
	if shadows:
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		l.shadow_filter_smooth = 2.0
		l.shadow_color = Color(0, 0, 0, 0.75)
	return l

func _add_occluder_from_body(body: Node2D) -> void:
	var cs := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or not (cs.shape is RectangleShape2D):
		return
	var sz := (cs.shape as RectangleShape2D).size
	var h := sz * 0.5
	var occ := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		cs.position + Vector2(-h.x, -h.y), cs.position + Vector2(h.x, -h.y),
		cs.position + Vector2(h.x, h.y), cs.position + Vector2(-h.x, h.y)])
	occ.occluder = poly
	body.add_child(occ)

func _build_wall_occluders_and_lamps() -> void:
	var tm := _game.get_node_or_null("spacestation") as TileMapLayer
	if tm == null or tm.tile_set == null:
		return
	var cells := tm.get_used_cells()
	var solid := {}
	var floor_cells: Array[Vector2i] = []
	for c in cells:
		var td := tm.get_cell_tile_data(c)
		if td != null and td.get_collision_polygons_count(0) > 0:
			solid[c] = true
		else:
			floor_cells.append(c)
	var half := Vector2(tm.tile_set.tile_size) * 0.5
	var made := 0
	for c in solid.keys():
		var edge := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not solid.has(c + d):
				edge = true
				break
		if not edge or made > 700:
			continue
		var occ := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		var p := tm.map_to_local(c)
		poly.polygon = PackedVector2Array([
			p + Vector2(-half.x, -half.y), p + Vector2(half.x, -half.y),
			p + Vector2(half.x, half.y), p + Vector2(-half.x, half.y)])
		occ.occluder = poly
		tm.add_child(occ)
		made += 1
	# ceiling lamps on a sparse grid over walkable floor
	var lamps := 0
	for c in floor_cells:
		if lamps >= 9:
			break
		if c.x % 7 == 0 and c.y % 6 == 0:
			var lamp := _make_light(Color(0.62, 0.80, 1.0), 0.85, 3.6, lamps < 5)
			lamp.position = tm.map_to_local(c)
			tm.add_child(lamp)
			lamps += 1

func _update_lighting(delta: float) -> void:
	# keep every module glowing in its own colour, reacting to power / broken state
	for m in BaseManager.active_modules:
		if not is_instance_valid(m):
			continue
		if not _module_lights.has(m):
			var vis := m.get_node_or_null("Visual") as ColorRect
			if vis == null:
				continue
			var l := _make_light(vis.color, 1.0, 2.2, false)
			l.position = vis.position + vis.size * 0.5
			m.add_child(l)
			_module_lights[m] = l
			_add_occluder_from_body(m)   # modules now cast shadows from lamps / torch
		var light: PointLight2D = _module_lights[m]
		var vis2 := m.get_node_or_null("Visual") as ColorRect
		if vis2 == null:
			continue
		if m.is_broken:
			var pulse := 0.5 + 0.5 * sin(_t * 10.0)
			light.color = Color(1.0, 0.15, 0.1)
			light.energy = 0.5 + 1.0 * pulse
			vis2.modulate = Color(1.0 + 0.3 * pulse, 1.0, 1.0)
		elif m.is_powered or m.module_name == "Reactor":
			light.color = m.base_visual_color
			light.energy = lerpf(light.energy, 1.3 + 0.12 * sin(_t * 3.0), delta * 6.0)
			vis2.modulate = Color(GLOW, GLOW, GLOW)
		else:
			light.energy = lerpf(light.energy, 0.12, delta * 4.0)
			vis2.modulate = Color(1, 1, 1)
	if _reactor_light != null and is_instance_valid(_reactor_light):
		var e := clampf(BaseManager.reactor_energy / 100.0, 0.0, 1.0)
		_reactor_light.energy = (0.4 + 1.1 * e) * (0.94 + 0.06 * sin(_t * 5.0))
	if _player_light != null:
		_player_light.energy = 1.15 + 0.06 * sin(_t * 2.3)
	# critical ambient: tint the whole base red when a system is nearly dead
	var danger := _danger_level()
	var target := Color(0.36, 0.40, 0.52).lerp(Color(0.46, 0.22, 0.24), danger)
	_modulate.color = _modulate.color.lerp(target, delta * 3.0)

func _danger_level() -> float:
	var worst := minf(BaseManager.oxygen_level, BaseManager.temp_level)
	return clampf(1.0 - worst / 30.0, 0.0, 1.0) if GameManager.current_phase == GameManager.Phase.SURVIVE else 0.0

# - particles -
## Ambient particles live on their own CanvasLayer (screen space), so the dark
## ambient tint can't swallow them and they always read clearly.
func _emitter(amount: int, life: float, add_mat: Material) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = ring_tex
	p.material = add_mat
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(960, 540)
	p.gravity = Vector2.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 1))
	g.add_point(0.75, Color(1, 1, 1, 1))
	p.color_ramp = g
	return p

func _world_motes(parent: Node, pts: PackedVector2Array, amount: int, life: float, vmin: float, vmax: float, col: Color, smin: float, smax: float, mat: Material) -> CPUParticles2D:
	var e := CPUParticles2D.new()
	e.texture = ring_tex
	e.material = mat
	e.amount = amount
	e.lifetime = life
	e.preprocess = life
	e.local_coords = true                       # they move WITH the station, not with the screen
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	e.emission_points = pts
	e.direction = Vector2(0, -1)
	e.spread = 180.0
	e.gravity = Vector2.ZERO
	e.initial_velocity_min = vmin
	e.initial_velocity_max = vmax
	e.scale_amount_min = smin
	e.scale_amount_max = smax
	e.color = col
	e.z_index = 6
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 1))
	g.add_point(0.75, Color(1, 1, 1, 1))
	e.color_ramp = g
	parent.add_child(e)
	return e

func _setup_particles() -> void:
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# 1) dust motes: only spawn over the station floor and drift a tiny bit,
	#    so they sit in the rooms like real floating dust
	var tm := _game.get_node_or_null("spacestation") as TileMapLayer
	if tm != null and tm.tile_set != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var tsz := Vector2(tm.tile_set.tile_size)
		var floor_pts := PackedVector2Array()
		for c in tm.get_used_cells():
			var td := tm.get_cell_tile_data(c)
			if td != null and td.get_collision_polygons_count(0) == 0:
				floor_pts.append(tm.map_to_local(c) + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) * tsz)
		if floor_pts.size() > 0:
			var step := maxi(1, floor_pts.size() / 600)
			var pts := PackedVector2Array()
			for i in range(0, floor_pts.size(), step):
				pts.append(floor_pts[i])
			_fx_dust = _world_motes(tm, pts, 220, 9.0, 3.0, 10.0, Color(2.2, 2.8, 3.4, 0.7), 0.04, 0.11, add_mat)

	# 2) reactor sparks live in the world and stay on the reactor
	var reactor := _game.get_node_or_null("Reactor") as Node2D
	if reactor != null:
		_sparks = _emitter(40, 2.4, add_mat)
		_sparks.name = "ReactorSparks"
		_sparks.local_coords = false
		_sparks.position = Vector2(64, 64)
		_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_sparks.emission_sphere_radius = 60.0
		_sparks.direction = Vector2(0, -1)
		_sparks.spread = 180.0
		_sparks.initial_velocity_min = 16.0
		_sparks.initial_velocity_max = 60.0
		_sparks.scale_amount_min = 0.05
		_sparks.scale_amount_max = 0.12
		_sparks.color = Color(1.2, 3.0, 3.6, 1.0)
		_sparks.z_index = 60
		reactor.add_child(_sparks)

func _update_particles() -> void:
	if _sparks != null and is_instance_valid(_sparks):
		_sparks.emitting = BaseManager.reactor_energy > 0.0 and GameSettings.particles_enabled()

# - post-process -
const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette = 0.30;
uniform float aberration = 0.0;
uniform bool optimize_samples = true;
uniform float scan = 0.0;
uniform float grain = 0.0;
uniform float danger = 0.0;
uniform float bloom_amount = 0.0;
float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }
void fragment(){
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float d = dot(c, c);
	vec2 off = c * d * aberration * 0.012;
	vec3 col;
	if (optimize_samples && aberration == 0.0) {
		col = texture(screen_tex, uv).rgb;
	} else {
		col.r = texture(screen_tex, uv + off).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - off).b;
	}
	// Small fixed tap count; works on WebGL 2 without HDR framebuffer support.
	if (bloom_amount > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE * 5.0;
		vec3 glow = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb;
		glow += texture(screen_tex, uv - vec2(px.x, 0.0)).rgb;
		glow += texture(screen_tex, uv + vec2(0.0, px.y)).rgb;
		glow += texture(screen_tex, uv - vec2(0.0, px.y)).rgb;
		glow *= 0.25;
		col += max(glow - vec3(0.62), vec3(0.0)) * bloom_amount;
	}
	float line = sin(uv.y * 900.0) * 0.5 + 0.5;
	col *= 1.0 - scan * line;
	col += (hash(uv * 900.0 + fract(TIME)) - 0.5) * grain;
	float v = smoothstep(0.15, 0.85, d * 2.2);
	col *= 1.0 - v * vignette;
	col = mix(col, col * vec3(1.4, 0.55, 0.55), danger * v * 1.5);
	COLOR = vec4(col, 1.0);
}
"""
var _post_rect: ColorRect
var _post_mat: ShaderMaterial

func _setup_post_fx() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PostFX"
	layer.layer = 50
	_game.add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = POST_SHADER
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = sh
	rect.material = _post_mat
	layer.add_child(rect)
	_post_rect = rect

func _apply_quality() -> void:
	if is_instance_valid(_post_rect):
		_post_rect.visible = not GameSettings.reduced_detail() and not GameSettings.mobile_quality()
		_post_mat.set_shader_parameter("bloom_amount", 0.55 if GameSettings.glow_enabled() else 0.0)
		_post_mat.set_shader_parameter("optimize_samples", GameSettings.baseline_enabled())

# - theme -
func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 18

	t.set_color("font_color", "Label", Color(0.85, 0.92, 0.95))
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)

	t.set_stylebox("panel", "PanelContainer", _box(C_PANEL, C_EDGE * Color(1, 1, 1, 0.45), 1, 14, 0))
	t.set_stylebox("normal", "Button", _box(Color(0.16, 0.42, 0.62, 1.0), Color(0.55, 0.8, 1.0, 1.0), 2, 12, 0))
	t.set_stylebox("hover", "Button", _box(Color(0.22, 0.55, 0.8, 1.0), Color.WHITE, 2, 12, 0))
	t.set_stylebox("pressed", "Button", _box(Color(0.12, 0.32, 0.5, 1.0), Color.WHITE, 2, 12, 0))
	t.set_stylebox("disabled", "Button", _box(Color(0.08, 0.1, 0.12, 0.7), Color(0.3, 0.3, 0.35, 0.4), 1, 4, 0))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), C_GREEN, 2, 4, 0))
	t.set_color("font_color", "Button", Color(1, 1, 1))
	t.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.45, 0.5))

	t.set_stylebox("background", "ProgressBar", _box(Color(0.02, 0.03, 0.04, 0.85), Color(1, 1, 1, 0.25), 1, 3, 0))
	t.set_stylebox("fill", "ProgressBar", _box(Color(1, 1, 1, 0.95), Color(0, 0, 0, 0), 0, 3, 0))

	var sep := StyleBoxLine.new()
	sep.color = C_EDGE * Color(1, 1, 1, 0.5)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	return t

func _box(bg: Color, border: Color, bw: int, radius: int, glow: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(border.r, border.g, border.b, 0.28 if glow > 0 else 0.0)
	s.shadow_size = glow
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _radial_tex(sz: int, _unused: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = sz
	tex.height = sz
	return tex

# - shop UI -
class Brackets extends Control:
	var col := Color(0.3, 0.85, 1.0, 0.9)
	var arm := 16.0
	var phase := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	func _process(delta: float) -> void:
		phase += delta
		queue_redraw()
	func _draw() -> void:
		var a := arm + 2.0 * sin(phase * 2.0)
		var c := col
		var s := size
		var w := 2.0
		draw_line(Vector2(0, 0), Vector2(a, 0), c, w)
		draw_line(Vector2(0, 0), Vector2(0, a), c, w)
		draw_line(Vector2(s.x, 0), Vector2(s.x - a, 0), c, w)
		draw_line(Vector2(s.x, 0), Vector2(s.x, a), c, w)
		draw_line(Vector2(0, s.y), Vector2(a, s.y), c, w)
		draw_line(Vector2(0, s.y), Vector2(0, s.y - a), c, w)
		draw_line(Vector2(s.x, s.y), Vector2(s.x - a, s.y), c, w)
		draw_line(Vector2(s.x, s.y), Vector2(s.x, s.y - a), c, w)

const GRID_SHADER := """
shader_type canvas_item;
uniform vec4 top : source_color = vec4(0.10, 0.13, 0.28, 1.0);
uniform vec4 bottom : source_color = vec4(0.03, 0.04, 0.10, 1.0);
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment(){
	vec3 col = mix(top.rgb, bottom.rgb, UV.y);
	vec2 cell = floor(FRAGCOORD.xy / 6.0);
	float star = step(0.9965, h(cell));
	float tw = 0.5 + 0.5 * sin(TIME * 1.5 + h(cell + 3.0) * 20.0);
	col += vec3(1.0) * star * (0.3 + 0.7 * tw);
	COLOR = vec4(col, 1.0);
}
"""

func _find_shop() -> CanvasLayer:
	var v = _game.get(SHOP_PROPERTY)
	if v is CanvasLayer and is_instance_valid(v) and not v.is_queued_for_deletion():
		return v
	if v != null:
		return null
	# fallback: any CanvasLayer under Game that isn't one of ours
	for ch in _game.get_children():
		if ch is CanvasLayer and ch != _hud and ch != _fx_layer and ch.name != "PostFX" \
				and not ch.has_meta("no_polish") and not ch.is_queued_for_deletion() and ch.get_child_count() > 0:
			return ch
	return null

func _update_shop(_delta: float) -> void:
	var shop := _find_shop()
	if shop != _shop_seen:
		_shop_seen = shop
		_shop_labels.clear()
		if shop != null:
			_decorate_shop(shop)
	if shop == null:
		return
	# generic "value changed" juice for EVERY label in the shop
	for l in _shop_labels.keys():
		if not is_instance_valid(l):
			_shop_labels.erase(l)
			continue
		var info: Array = _shop_labels[l]
		if l.text != info[0]:
			info[0] = l.text
			_label_pop(l, info[1])

func _label_pop(l: Label, base: Color) -> void:
	if l.size.x < 500.0:
		l.pivot_offset = l.size * 0.5
		l.scale = Vector2(1.18, 1.18)
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(l, "scale", Vector2.ONE, 0.25)
	l.modulate = Color(1.5, 1.5, 1.3)
	create_tween().tween_property(l, "modulate", base, 0.4)

func _is_skipped(n: Node) -> bool:
	var p := n
	while p != null and p != _shop_seen:
		if p.has_meta("no_polish"):
			return true
		p = p.get_parent()
	return false

func _decorate_shop(shop: CanvasLayer) -> void:
	_card_idx = 0
	var bg_done := false
	for k in shop.get_children():
		if not (k is Control) or k.has_meta("no_polish"):
			continue
		var c := k as Control
		var full := c.anchor_right >= 0.99 and c.anchor_bottom >= 0.99
		if c is ColorRect and full and not bg_done and c.material == null:
			bg_done = true
			var sh := Shader.new()
			sh.code = GRID_SHADER
			var sm := ShaderMaterial.new()
			sm.shader = sh
			c.material = sm
			continue
		if c.theme == null:
			c.theme = ui_theme
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, 0.5)
	_walk_decorate(shop)
	# title = biggest label in the shop: soft glow + type-on
	var title: Label = null
	var best := 0
	for l in _shop_labels.keys():
		var fs: int = (l as Label).get_theme_font_size("font_size")
		if fs > best:
			best = fs
			title = l
	if title != null and best >= 26:
		title.modulate = Color(GLOW, GLOW, GLOW)
		_shop_labels[title][1] = title.modulate
		title.add_theme_color_override("font_shadow_color", Color(0.2, 1.0, 0.4, 0.35))
		title.add_theme_constant_override("shadow_offset_x", 0)
		title.add_theme_constant_override("shadow_offset_y", 0)

func _walk_decorate(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			_decorate_control(c)
		_walk_decorate(c)

## Decorates ONE control purely by its type - no assumptions about layout.
func _decorate_control(c: Node) -> void:
	if not is_instance_valid(c) or not (c is Control) or c.has_meta("polished") or _is_skipped(c):
		return
	c.set_meta("polished", true)
	if c is Brackets:
		return
	if c is Button:
		_juice_button(c)
	elif c is PanelContainer:
		_decorate_card(c)
	elif c is Label:
		_shop_labels[c] = [(c as Label).text, (c as Label).modulate]

func _decorate_card(card: PanelContainer) -> void:
	var delay := minf(0.1 + _card_idx * 0.08, 0.8)
	_card_idx += 1
	card.modulate.a = 0.0
	create_tween().tween_property(card, "modulate:a", 1.0, 0.35).set_delay(delay)

func _juice_button(b: Button) -> void:
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func():
		b.pivot_offset = b.size * 0.5
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2(1.06, 1.06), 0.15)
		b.modulate = Color(GLOW, GLOW, GLOW))
	b.mouse_exited.connect(func():
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.12)
		b.modulate = Color.WHITE)
	b.button_down.connect(func():
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(0.94, 0.94))
	b.button_up.connect(func():
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2(1.06, 1.06), 0.18))
	var up := b.text.to_upper()
	var primary := b.has_meta("polish_primary")
	for w in PRIMARY_WORDS:
		if up.contains(w):
			primary = true
	if primary:
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "self_modulate", Color(GLOW, GLOW, GLOW), 0.9)
		tw.tween_property(b, "self_modulate", Color.WHITE, 0.9)

# - HUD -
func _setup_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "SurvivalHUD"
	_hud.layer = 20
	_game.add_child(_hud)

	_crit_flash = ColorRect.new()
	_crit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crit_flash.color = Color(1, 0.05, 0.05, 0.0)
	_hud.add_child(_crit_flash)

	var root := MarginContainer.new()
	root.theme = ui_theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "top", "right", "bottom"]:
		root.add_theme_constant_override("margin_" + s, 24)
	_hud.add_child(root)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var ps := _box(Color(0.03, 0.05, 0.08, 0.9), Color(0.35, 0.85, 1.0, 0.8), 2, 3, 0)
	ps.border_width_left = 5
	ps.content_margin_left = 14
	ps.content_margin_right = 14
	ps.content_margin_top = 10
	ps.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", ps)
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var head_row := HBoxContainer.new()
	vb.add_child(head_row)
	var head := Label.new()
	head.text = "BASE STATUS"
	head.add_theme_font_override("font", mono)
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", C_CYAN)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head)
	var tog := Button.new()
	tog.text = "-"
	tog.flat = true
	tog.focus_mode = Control.FOCUS_NONE
	tog.custom_minimum_size = Vector2(28, 22)
	tog.add_theme_font_override("font", mono)
	tog.add_theme_font_size_override("font_size", 20)
	tog.add_theme_color_override("font_color", C_CYAN)
	head_row.add_child(tog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	vb.add_child(body)
	body.add_child(HSeparator.new())
	_add_bar(body, "AIR   ", "o2", C_CYAN)
	_add_bar(body, "WARMTH", "temp", Color(1.0, 0.55, 0.25))
	_add_bar(body, "HEALTH", "hp", Color(1.0, 0.4, 0.45))
	_add_bar(body, "LOAD  ", "load", C_AMBER)
	tog.pressed.connect(func() -> void:
		body.visible = not body.visible
		tog.text = "-" if body.visible else "+")
	_hud_panel = panel

	_alert_box = VBoxContainer.new()
	_alert_box.theme = ui_theme
	_alert_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alert_box.position.y = 28
	_alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_alert_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_hud.add_child(_alert_box)

	_crit_label = Label.new()
	_crit_label.theme = ui_theme
	_crit_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crit_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crit_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_crit_label.add_theme_font_size_override("font_size", 40)
	_crit_label.add_theme_color_override("font_color", C_RED)
	_crit_label.modulate = Color(1.3, 0.7, 0.6, 0.0)
	_crit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_crit_label)
	_hud_panel.modulate.a = 0.0

var _hud_panel: PanelContainer

func _add_bar(parent: Node, text: String, key: String, col: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", mono)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	row.add_child(l)
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(190, 16)
	pb.max_value = 100.0
	pb.show_percentage = false
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.modulate = col * Color(GLOW, GLOW, GLOW, 1.0)
	row.add_child(pb)
	var v := Label.new()
	v.custom_minimum_size = Vector2(52, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_override("font", mono)
	v.add_theme_font_size_override("font_size", 16)
	row.add_child(v)
	_bars[key] = {"bar": pb, "val": v, "col": col}

func _update_hud(delta: float) -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	var live = GameManager.current_phase == GameManager.Phase.SURVIVE or (is_instance_valid(_game) and _game.get_meta("show_hud", false))
	_hud_panel.modulate.a = lerpf(_hud_panel.modulate.a, 1.0 if live else 0.0, delta * 4.0)
	if not live:
		return
	var vals := {
		"o2": BaseManager.oxygen_level,
		"temp": BaseManager.temp_level,
		"hp": BaseManager.health,
		"load": clampf(BaseManager.current_power_draw / maxf(BaseManager.total_power, 1.0) * 100.0, 0.0, 100.0)}
	for k in vals.keys():
		var d: Dictionary = _bars[k]
		var pb: ProgressBar = d["bar"]
		pb.value = lerpf(pb.value, vals[k], delta * 8.0)
		(d["val"] as Label).text = "%d%%" % int(vals[k])
		var low: bool = vals[k] < 25.0 and k != "load"
		var base: Color = d["col"]
		if low:
			var p := 0.5 + 0.5 * sin(_t * 9.0)
			pb.modulate = base.lerp(C_RED, 0.7) * Color(1.0 + 0.3 * p, 1.0 + 0.3 * p, 1.0 + 0.3 * p, 1.0)
			(d["val"] as Label).add_theme_color_override("font_color", C_RED)
		else:
			pb.modulate = base * Color(GLOW, GLOW, GLOW, 1.0)
			(d["val"] as Label).add_theme_color_override("font_color", Color(0.85, 0.92, 0.95))
	# danger overlay + post-fx
	var danger := _danger_level()
	if _post_mat != null:
		_post_mat.set_shader_parameter("danger", danger * (0.7 + 0.3 * sin(_t * 6.0)))
	_crit_flash.color.a = danger * 0.10 * (0.5 + 0.5 * sin(_t * 6.0))
	_crit_time = maxf(0.0, _crit_time - delta)
	_crit_label.modulate.a = clampf(_crit_time, 0.0, 1.0) * (0.6 + 0.4 * sin(_t * 12.0))
func _on_module_broken(module_name: String) -> void:
	if not _installed or _alert_box == null:
		return
	_toast("%s broke! Stand close and hold E to fix it." % module_name, C_AMBER)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var tw := create_tween()
		for i in 8:
			tw.tween_property(cam, "offset", Vector2(randf_range(-8, 8), randf_range(-8, 8)) * (1.0 - i / 8.0), 0.04)
		tw.tween_property(cam, "offset", Vector2.ZERO, 0.05)

func _on_game_over(reason: String) -> void:
	if not _installed or _crit_label == null:
		return
	_crit_label.text = reason
	_crit_time = 2.0   # re-armed every frame the condition persists

func _toast(msg: String, col: Color) -> void:
	var p := PanelContainer.new()
	p.theme = ui_theme
	p.add_theme_stylebox_override("panel", _box(Color(0.12, 0.08, 0.04, 0.92), col, 2, 5, 22))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = msg
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	l.modulate = Color(GLOW, GLOW, GLOW)
	p.add_child(l)
	_alert_box.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
