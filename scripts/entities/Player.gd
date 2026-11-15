
extends CharacterBody2D
## PLAYER
##   SPACE           toggle build mode (you can still walk around in it)
##   E (interact)    in build mode: place + start building  |  outside: wires
##   SCROLL / TAB    swap which module you're about to place
## The build ghost is ALWAYS placed directly ahead of the way you're facing.

# - tuning -
@export_group("Movement")
@export var speed: float = 300.0
@export var acceleration: float = 2600.0
@export var friction: float = 3400.0

@export_group("Animation")
## true  = you have idle_up / idle_down / idle_left / idle_right
## false = you only have idle_up / idle_down (left/right idle falls back to the last up/down idle)
@export var all_idles: bool = false

@export_group("Wires")
@export var grab_range: float = 150.0
@export var plug_range: float = 90.0
@export var pickup_range: float = 80.0

@export_group("Build")
@export var build_gap: float = 24.0        ## empty space between you and the ghost
@export var build_grid: float = 32.0       ## placement grid
@export var player_radius: float = 18.0
@export var ghost_glide: float = 22.0
@export var reactor_block_radius: float = 340.0 ## no building inside this circle around the reactor
@export var exit_block_margin: float = 64.0     ## no building this close to the exit area
@export var wire_crawl_speed: float = 30.0      ## speed when the wire is pulled as far as it goes
@export var wire_stretch_range: float = 260.0   ## extra pixels of stretch to reach full slowdown
@export var build_radius: float = 300.0    ## higher = ghost snaps faster

@export_group("Juice")
@export var camera_lookahead: float = 46.0

@export_group("Footstep Audio")
@export var metal_footstep_sfx: AudioStream
@export var mars_footstep_sfx: AudioStream
@export var footstep_interval: float = 0.34
@export var footstep_volume_db: float = -8.0

const BUILD_ACTION := &"build_mode"
const DIR_ACTIONS: Dictionary = {"up": "ui_up", "down": "ui_down", "left": "ui_left", "right": "ui_right"}
const DIR_VECS: Dictionary = {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
const C_CYAN := Color(0.3, 0.85, 1.0)
const C_GREEN := Color(0.4, 1.0, 0.55)
const C_RED := Color(1.0, 0.3, 0.25)
const C_AMBER := Color(1.0, 0.85, 0.3)

@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var player_camera: Camera2D = get_node_or_null("PlayerCamera")
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

# state (names kept so other scripts keep working)
var is_active: bool = false
var input_locked: bool = false
var is_outside: bool = false
var current_wire: Node2D = null
var facing_dir: String = "down"
var facing_vec: Vector2 = Vector2.DOWN
var held_dirs: Array[String] = []
var is_build_mode: bool = false
var build_options: Array[Dictionary] = []
var selected_module_index: int = 0
var ghost_module: Node2D = null
var can_place: bool = false

var _last_vertical := "down"
var _move_vel := Vector2.ZERO
var _t := 0.0
var _font: Font

var _footstep_timer: float = 0.0
var _footstep_player: AudioStreamPlayer
var _default_metal_stream: AudioStreamWAV
var _default_mars_stream: AudioStreamWAV

# juice state
var _sq := Vector2.ONE
var _sq_vel := Vector2.ZERO
var _walk_t := 0.0
var _trauma := 0.0
var _sprite_base_scale := Vector2.ONE
var _sprite_base_pos := Vector2.ZERO
var _sprite_half_h := 24.0
var _cam_base := Vector2.ZERO
var _dust: CPUParticles2D
var _cam_zoom := Vector2.ONE
var _zoom_kick := 0.0
var _ghost_zone := 250.0
var _hint_panel: PanelContainer
var _hint_box: VBoxContainer
var _hint_key_cache := ""
var _hint_kind := ""
var _hint_marks: Array = []
var _hints_node: Hints

# ghost state
var _ghost_origin := Vector2.ZERO
var _ghost_half := Vector2(64, 64)
var _ghost_center_off := Vector2.ZERO
var _ghost_test_shape: Shape2D = null
var _ghost_flash := 0.0
var _hud: CanvasLayer
var _build_panel: PanelContainer
var _build_title: Label
var _build_hint: Label
var _toast: Label
var _hud_key := ""
var _panel_ok: StyleBoxFlat
var _panel_bad: StyleBoxFlat

# - setup -
func _ready() -> void:
	add_to_group("player")
	visible = false
	set_physics_process(false)
	_font = GameFont.get_font()
	_ensure_build_action()
	if sprite != null:
		_sprite_base_scale = sprite.scale
		_sprite_base_pos = sprite.position
		if sprite.texture != null:
			_sprite_half_h = float(sprite.texture.get_height()) / maxf(1.0, float(sprite.vframes)) * 0.5 * absf(sprite.scale.y)
	if player_camera != null:
		_cam_base = player_camera.position
		_cam_zoom = player_camera.zoom
	_make_dust()
	_make_build_hud()
	_make_hint_panel()
	_setup_footstep_audio()
	_hints_node = Hints.new()
	_hints_node.p = self
	add_child(_hints_node)

func _exit_tree() -> void:
	if is_instance_valid(ghost_module):
		ghost_module.queue_free()
	if is_instance_valid(_hud):
		_hud.queue_free()

func _ensure_build_action() -> void:
	if InputMap.has_action(BUILD_ACTION):
		return
	InputMap.add_action(BUILD_ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	InputMap.action_add_event(BUILD_ACTION, ev)

func enable_player() -> void:
	is_active = true
	visible = true
	if _hint_panel != null:
		_hint_panel.visible = true
	set_physics_process(true)
	position = Vector2(320, 600)
	velocity = Vector2.ZERO
	_move_vel = Vector2.ZERO
	if player_camera != null:
		player_camera.enabled = true
	# materialise effect
	_pop(-0.3)
	Fx.burst(get_parent(), global_position, Color(0.5, 1.4, 1.8, 0.9), 26, 60.0, 180.0, 0.7, 0.04, 0.1, true)
	Ring.spawn(get_parent(), global_position, Color(0.4, 1.3, 1.6), 90.0, 0.55)

func set_input_locked(locked: bool) -> void:
	input_locked = locked
	if locked:
		velocity = Vector2.ZERO
		_move_vel = Vector2.ZERO
		held_dirs.clear()
		if is_build_mode:
			_exit_build_mode()
		if current_wire != null and is_instance_valid(current_wire):
			current_wire.drop(global_position)
			current_wire = null
		_update_animation(Vector2.ZERO)

func set_outside_mode(outside: bool, bounds: Rect2) -> void:
	is_outside = outside
	if outside and is_build_mode:
		_exit_build_mode()
	if _dust != null:
		_dust.color = Color(0.92, 0.55, 0.35, 0.65) if outside else Color(0.85, 0.82, 0.75, 0.55)
	if player_camera == null:
		return
	if outside and bounds.size != Vector2.ZERO:
		player_camera.limit_left = int(bounds.position.x)
		player_camera.limit_top = int(bounds.position.y)
		player_camera.limit_right = int(bounds.end.x)
		player_camera.limit_bottom = int(bounds.end.y)
		player_camera.reset_smoothing()
	else:
		player_camera.limit_left = -10000000
		player_camera.limit_top = -10000000
		player_camera.limit_right = 10000000
		player_camera.limit_bottom = 10000000
		player_camera.reset_smoothing()

func _setup_footstep_audio() -> void:
	_footstep_player = AudioStreamPlayer.new()
	_footstep_player.volume_db = footstep_volume_db
	add_child(_footstep_player)
	_default_metal_stream = _generate_metal_step_wav()
	_default_mars_stream = _generate_mars_step_wav()

func _update_footsteps(delta: float, input_dir: Vector2) -> void:
	if input_dir == Vector2.ZERO or _move_vel.length_squared() < 100.0:
		_footstep_timer = footstep_interval * 0.85
		return
	_footstep_timer += delta
	if _footstep_timer >= footstep_interval:
		_footstep_timer = 0.0
		if _footstep_player != null:
			_footstep_player.volume_db = footstep_volume_db
			if is_outside:
				_footstep_player.stream = mars_footstep_sfx if mars_footstep_sfx != null else _default_mars_stream
				_footstep_player.pitch_scale = randf_range(0.88, 1.08)
			else:
				_footstep_player.stream = metal_footstep_sfx if metal_footstep_sfx != null else _default_metal_stream
				_footstep_player.pitch_scale = randf_range(0.94, 1.12)
			_footstep_player.play()

func _generate_metal_step_wav() -> AudioStreamWAV:
	var mix_rate: int = 22050
	var duration: float = 0.09
	var samples: int = int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 48.0)
		var clank: float = sin(t * TAU * 185.0) * 0.55 + sin(t * TAU * 420.0) * 0.3 + sin(t * TAU * 890.0) * 0.15
		var noise: float = randf_range(-0.35, 0.35) * exp(-t * 85.0)
		var sample: float = clampf((clank + noise) * env, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav

func _generate_mars_step_wav() -> AudioStreamWAV:
	var mix_rate: int = 22050
	var duration: float = 0.14
	var samples: int = int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var lp: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(mix_rate)
		var env: float = sin(clampf(t / duration, 0.0, 1.0) * PI) * exp(-t * 14.0)
		var raw: float = randf_range(-1.0, 1.0)
		lp += 0.24 * (raw - lp)
		var thud: float = sin(t * TAU * 90.0) * exp(-t * 35.0) * 0.35
		var sample: float = clampf((lp * 0.9 + thud) * env, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav

# - per-frame -
func _physics_process(delta: float) -> void:
	if not is_active:
		return
	if input_locked:
		_move_vel = Vector2.ZERO
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation(Vector2.ZERO)
		return

	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_update_facing()

	# smooth acceleration / friction (stored separately so wire tension keeps working as before)
	var rate := acceleration if input_dir != Vector2.ZERO else friction
	_move_vel = _move_vel.move_toward(input_dir * speed, rate * delta)
	velocity = _move_vel
	# rubber band: the further the wire is stretched, the slower you can move away from its anchor
	if current_wire != null and is_instance_valid(current_wire) and "socket_pos" in current_wire:
		var away: Vector2 = global_position - current_wire.socket_pos
		var over: float = maxf(current_wire.get_total_rope_length(), away.length()) - current_wire.max_length
		if over > 0.0 and away.length() > 1.0:
			var k := 1.0 - exp(-over / wire_stretch_range * 2.2)
			var f := lerpf(1.0, wire_crawl_speed / speed, k)
			var dir := away.normalized()
			var comp := velocity.dot(dir)
			if comp > 0.0:
				velocity -= dir * comp * (1.0 - f)

	if current_wire != null and is_instance_valid(current_wire) and current_wire.has_method("apply_tension_to_player"):
		var did_snap: bool = current_wire.apply_tension_to_player(self, delta)
		if did_snap:
			current_wire.drop(global_position)
			current_wire = null
			_pop(-0.18)
			shake(0.25)

	var before_move := global_position
	move_and_slide()
	if global_position.distance_squared_to(before_move) > 0.01:
		EventBus.player_moved.emit(self)
	_update_animation(input_dir)
	_update_footsteps(delta, input_dir)

	if is_build_mode:
		_update_build_ghost(delta)

func _process(delta: float) -> void:
	_t += delta
	var d := minf(delta, 0.05)
	_update_squash(d)
	_update_camera(d)
	_update_hints()
	if is_build_mode:
		_update_hud_text()
		queue_redraw()

# - facing -
func _update_facing() -> void:
	for i in range(held_dirs.size() - 1, -1, -1):
		if not Input.is_action_pressed(DIR_ACTIONS[held_dirs[i]]):
			held_dirs.remove_at(i)
	for dname: String in DIR_ACTIONS.keys():
		var action: String = DIR_ACTIONS[dname]
		if Input.is_action_just_pressed(action):
			held_dirs.erase(dname)
			held_dirs.append(dname)
		elif Input.is_action_pressed(action) and not held_dirs.has(dname):
			held_dirs.append(dname)
	if not held_dirs.is_empty():
		var nd: String = held_dirs.back()
		if nd != facing_dir:
			_pop(0.07)
			Fx.burst(get_parent(), global_position + Vector2(0, _sprite_half_h * 0.8), Color(0.7, 0.75, 0.85, 0.35), 4, 10.0, 40.0, 0.35, 0.1, 0.22)
		facing_dir = nd
	facing_vec = DIR_VECS[facing_dir]
	if facing_dir == "up" or facing_dir == "down":
		_last_vertical = facing_dir

func _update_animation(input_dir: Vector2) -> void:
	if anim_player == null:
		return
	var moving := input_dir != Vector2.ZERO
	var anim_name := ""
	if moving:
		anim_name = "walk_" + facing_dir
		anim_player.speed_scale = clampf(_move_vel.length() / speed * 1.1, 0.6, 1.2)
	else:
		var d := facing_dir
		if not all_idles and (d == "left" or d == "right"):
			d = _last_vertical
		anim_name = "idle_" + d
		anim_player.speed_scale = 1.0
		if not anim_player.has_animation(anim_name):
			anim_name = "idle_down"
	if anim_player.has_animation(anim_name) and anim_player.current_animation != anim_name:
		anim_player.play(anim_name)

# - juice -
func _pop(amount: float) -> void:
	# amount > 0 = squash (wide + short), amount < 0 = stretch (tall + thin)
	_sq_vel += Vector2(amount, -amount) * 15.0

func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)
	_zoom_kick = minf(0.1, _zoom_kick + amount * 0.1)

func _update_squash(d: float) -> void:
	_sq_vel += (Vector2.ONE - _sq) * 220.0 * d
	_sq_vel *= maxf(0.0, 1.0 - 14.0 * d)
	_sq += _sq_vel * d
	var spd := _move_vel.length() / speed
	var moving := spd > 0.1
	if moving:
		_walk_t += d * 14.0 * spd
	var bob := sin(_walk_t) * 0.035 * spd if moving else 0.0
	var sc := Vector2(_sq.x - bob, _sq.y + bob)
	if sprite != null:
		sprite.scale = _sprite_base_scale * sc
		sprite.position = _sprite_base_pos + Vector2(0.0, (1.0 - sc.y) * _sprite_half_h)
		sprite.rotation = lerp_angle(sprite.rotation, clampf(_move_vel.x / speed, -1.0, 1.0) * 0.07, 1.0 - exp(-12.0 * d))
	if _dust != null:
		_dust.emitting = is_active and not input_locked and spd > 0.5
		_dust.position = Vector2(0.0, _sprite_half_h * 0.85)
		if moving:
			_dust.direction = -_move_vel.normalized()

func _update_camera(d: float) -> void:
	if player_camera == null:
		return
	var look := facing_vec * camera_lookahead * clampf(_move_vel.length() / speed + 0.25, 0.0, 1.0)
	player_camera.position = player_camera.position.lerp(_cam_base + look, 1.0 - exp(-4.0 * d))
	_zoom_kick = lerpf(_zoom_kick, 0.0, 1.0 - exp(-8.0 * d))
	player_camera.zoom = _cam_zoom * (1.0 + _zoom_kick)
	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - 1.8 * d)
		var s := _trauma * _trauma * 14.0
		player_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * s
	elif player_camera.offset != Vector2.ZERO and _trauma <= 0.0:
		player_camera.offset = player_camera.offset.lerp(Vector2.ZERO, 0.5)

func _make_dust() -> void:
	_dust = CPUParticles2D.new()
	_dust.texture = Fx.tex()
	_dust.amount = 18
	_dust.lifetime = 0.5
	_dust.local_coords = false
	_dust.show_behind_parent = true
	_dust.emitting = false
	_dust.gravity = Vector2.ZERO
	_dust.spread = 22.0
	_dust.initial_velocity_min = 30.0
	_dust.initial_velocity_max = 70.0
	_dust.damping_min = 40.0
	_dust.damping_max = 70.0
	_dust.scale_amount_min = 0.1
	_dust.scale_amount_max = 0.26
	_dust.color = Color(0.85, 0.82, 0.75, 0.55)
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.6))
	cv.add_point(Vector2(1, 1.6))
	_dust.scale_amount_curve = cv
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_dust.color_ramp = g
	add_child(_dust)

# - input -
func _unhandled_input(event: InputEvent) -> void:
	if not is_active or input_locked:
		return
	if event.is_action_pressed(BUILD_ACTION):
		_toggle_build_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		if is_build_mode:
			_attempt_place()
		else:
			_try_interact()
		return
	if is_build_mode:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_cycle_ghost(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_cycle_ghost(1)
			elif event.button_index == MOUSE_BUTTON_LEFT and WirePort.hover_count == 0:
				_attempt_place()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
			_cycle_ghost(1)

# - build mode -
func _toggle_build_mode() -> void:
	if is_build_mode:
		_exit_build_mode()
		return
	if is_outside:
		_flash_hint("Can't build out on the Martian surface!", C_RED)
		_pop(0.08)
		return
	_refresh_build_options()
	if build_options.is_empty():
		_flash_hint("You have nothing to build yet!", C_AMBER)
		_pop(0.08)
		return
	is_build_mode = true
	_spawn_ghost()
	_set_build_hud(true)
	_pop(-0.12)

func _exit_build_mode() -> void:
	is_build_mode = false
	_clear_ghost()
	_set_build_hud(false)
	_pop(0.06)
	queue_redraw()

func _refresh_build_options() -> void:
	var prev_id := ""
	if selected_module_index < build_options.size():
		prev_id = build_options[selected_module_index]["id"]
	build_options.clear()
	selected_module_index = 0
	for item_data in GameManager.catalog:
		var item_id = item_data["id"]
		if GameManager.get_item_count(item_id) > 0:
			var scene = null if not item_data.has("scene_path") or str(item_data["scene_path"]) == "" else load(item_data["scene_path"])
			if scene != null:
				build_options.append({"id": item_id, "scene": scene})
				if item_id == prev_id:
					selected_module_index = build_options.size() - 1

func _cycle_ghost(dir: int) -> void:
	if build_options.size() < 2:
		return
	selected_module_index = posmod(selected_module_index + dir, build_options.size())
	_spawn_ghost()
	_pop(0.06)

func _clear_ghost() -> void:
	if is_instance_valid(ghost_module):
		ghost_module.queue_free()
	ghost_module = null
	_ghost_test_shape = null

func _spawn_ghost() -> void:
	_clear_ghost()
	if build_options.is_empty():
		return
	var option: Dictionary = build_options[selected_module_index]
	var g = option["scene"].instantiate()
	g.set_meta("is_ghost", true)
	g.set("is_constructing", true)            # stops BaseModule._ready from registering the preview
	g.process_mode = Node.PROCESS_MODE_DISABLED
	g.z_index = 20
	get_parent().add_child(g)
	_neutralize_ghost(g)
	ghost_module = g
	# measure the module's footprint from its collision shape
	_ghost_half = Vector2(64, 64)
	_ghost_center_off = Vector2.ZERO
	_ghost_test_shape = null
	var col := g.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null and col.shape != null:
		_ghost_center_off = col.position
		if col.shape is RectangleShape2D:
			var sz: Vector2 = (col.shape as RectangleShape2D).size
			_ghost_half = sz * 0.5
			var ts := RectangleShape2D.new()
			ts.size = sz - Vector2(6, 6)       # tiny shrink so flush neighbours don't count as overlap
			_ghost_test_shape = ts
		else:
			_ghost_test_shape = col.shape
			_ghost_half = Vector2(48, 48)
	_ghost_zone = _ghost_half.length() + BaseModule.ZONE_PAD
	_update_build_ghost(0.0, true)
	g.modulate.a = 0.0
	_hud_key = ""

## The preview must not collide, be interactable, or be treated as a wire target.
func _neutralize_ghost(n: Node) -> void:
	if n is CollisionObject2D:
		(n as CollisionObject2D).collision_layer = 0
		(n as CollisionObject2D).collision_mask = 0
	if n is Area2D:
		(n as Area2D).monitoring = false
		(n as Area2D).monitorable = false
	for grp in n.get_groups():
		if not str(grp).begins_with("_"):
			n.remove_from_group(grp)
	for c in n.get_children():
		_neutralize_ghost(c)

static func _snap_out(v: float, dir: float, grid: float) -> float:
	if dir > 0.0:
		return ceilf(v / grid) * grid
	if dir < 0.0:
		return floorf(v / grid) * grid
	return roundf(v / grid) * grid

func _update_build_ghost(delta: float, snap_now: bool = false) -> void:
	if not is_instance_valid(ghost_module):
		return
	var to_mouse := get_global_mouse_position() - global_position
	var reach := _ghost_reach()
	if to_mouse.length() > reach:
		to_mouse = to_mouse.normalized() * reach
	var center := global_position + to_mouse
	var origin := center - _ghost_center_off
	_ghost_origin = origin

	if snap_now or ghost_module.global_position.distance_to(origin) > 700.0:
		ghost_module.global_position = origin
	else:
		ghost_module.global_position = ghost_module.global_position.lerp(origin, 1.0 - exp(-ghost_glide * delta))

	can_place = not is_outside
	if can_place and _ghost_test_shape != null:
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = _ghost_test_shape
		q.transform = Transform2D(0.0, origin + _ghost_center_off)
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.exclude = [get_rid()]
		can_place = get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()
	if can_place:
		var mine := Rect2(center - _ghost_half, _ghost_half * 2.0).grow(-3.0)
		for mm in get_tree().get_nodes_in_group("modules"):
			if is_instance_valid(mm) and mm is BaseModule and mine.intersects((mm as BaseModule).get_footprint()):
				can_place = false
				break
	if can_place:
		can_place = _reactor_clearance_ok(center)
	if can_place:
		var rc := Rect2(center - _ghost_half, _ghost_half * 2.0)
		var cp := Vector2(clampf(global_position.x, rc.position.x, rc.end.x), clampf(global_position.y, rc.position.y, rc.end.y))
		if cp.distance_to(global_position) < player_radius + 6.0:
			can_place = false

	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	var a := lerpf(ghost_module.modulate.a, 0.5 + 0.2 * pulse, 0.25)
	_ghost_flash = maxf(0.0, _ghost_flash - delta)
	if _ghost_flash > 0.0:
		ghost_module.modulate = Color(2.2, 0.35, 0.35, 0.85)
	elif can_place:
		ghost_module.modulate = Color(0.55, 1.0, 1.3, a)
	else:
		ghost_module.modulate = Color(1.4, 0.3, 0.3, a)

func _draw() -> void:
	pass

func _deny() -> void:
	_ghost_flash = 0.25
	_sq_vel.x += 3.5 * (1.0 if randf() > 0.5 else -1.0)
	shake(0.18)
	_flash_hint("Can't build there - something's in the way!", C_RED)

func _reactor_node() -> BaseModule:
	for candidate in get_tree().get_nodes_in_group("modules"):
		if candidate is BaseModule and candidate.module_name == "Reactor":
			return candidate
	return null

func _exit_rect() -> Rect2:
	var area := get_tree().current_scene.find_child("outside", true, false) as Area2D
	if area == null:
		return Rect2()
	var cs := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return Rect2()
	var sz: Vector2 = cs.shape.get_rect().size * cs.global_scale.abs()
	return Rect2(cs.global_position - sz * 0.5, sz)

## Two rules only: not near the reactor (circle) and not near the exit.
func _reactor_clearance_ok(center: Vector2) -> bool:
	var footprint := Rect2(center - _ghost_half, _ghost_half * 2.0)
	var r := _reactor_node()
	if r != null:
		var rc := r.get_center()
		var cp := Vector2(clampf(rc.x, footprint.position.x, footprint.end.x), clampf(rc.y, footprint.position.y, footprint.end.y))
		if cp.distance_to(rc) < reactor_block_radius:
			return false
	var ex := _exit_rect()
	if ex.size != Vector2.ZERO and footprint.intersects(ex.grow(exit_block_margin), true):
		return false
	return true

func _attempt_place() -> void:
	if is_outside or not is_instance_valid(ghost_module) or build_options.is_empty():
		return
	# Revalidate at commit time as well as when tinting the preview.
	_update_build_ghost(0.0)
	if not can_place or not _reactor_clearance_ok(_ghost_origin + _ghost_center_off):
		_deny()
		return
	var option: Dictionary = build_options[selected_module_index]
	var item_name: String = option["id"]
	if not GameManager.remove_from_inventory(item_name):
		_deny()
		return

	var parent_node := get_parent()
	var m = option["scene"].instantiate()
	m.set("is_constructing", true)
	var p2d := parent_node as Node2D
	m.position = p2d.to_local(_ghost_origin) if p2d != null else _ghost_origin
	parent_node.add_child(m)
	m.start_construction()
	EventBus.module_placed.emit(m)

	var fx := ConstructionFX.new()
	fx.setup(m, self, _ghost_center_off, _ghost_half, _font)
	parent_node.add_child(fx)

	var c := _ghost_origin + _ghost_center_off
	Fx.burst(parent_node, c, Color(0.75, 0.78, 0.85, 0.55), 22, 40.0, 150.0, 0.9, 0.3, 0.7)
	Fx.burst(parent_node, c, Color(1.6, 1.2, 0.5, 1.0), 16, 80.0, 220.0, 0.5, 0.04, 0.09, true, Vector2(0, 260))
	Ring.spawn(parent_node, c, Color(0.4, 1.3, 1.6), maxf(_ghost_half.x, _ghost_half.y) * 1.5, 0.5)
	_pop(0.2)
	shake(0.35)
	_flash_hint("Building %s - stay inside the circle!" % item_name, C_GREEN)

	_refresh_build_options()
	_exit_build_mode()
# - build HUD -
func _box(border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(border.r, border.g, border.b, 0.3)
	s.shadow_size = 14
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func _lbl(size: int, col: Color) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = _font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0, 0.8)
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 15
	_panel_ok = _box(Color(0.3, 0.85, 1.0, 0.85))
	_panel_bad = _box(Color(1.0, 0.3, 0.25, 0.9))
	_build_panel = PanelContainer.new()
	_build_panel.add_theme_stylebox_override("panel", _panel_ok)
	_build_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_build_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_panel.offset_top = -40
	_build_panel.offset_bottom = -40
	_build_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_build_title = _lbl(20, C_CYAN)
	_build_hint = _lbl(14, Color(0.75, 0.82, 0.88))
	_build_hint.text = "E place     SPACE stop     TAB swap"
	vb.add_child(_build_title)
	vb.add_child(_build_hint)
	_build_panel.add_child(vb)
	_hud.add_child(_build_panel)
	_toast = _lbl(18, C_AMBER)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_top = -130
	_toast.offset_bottom = -130
	_toast.modulate.a = 0.0
	_hud.add_child(_toast)
	add_child.call_deferred(_hud)

func _set_build_hud(on: bool) -> void:
	if _build_panel == null:
		return
	_build_panel.visible = on
	if on:
		_build_panel.modulate.a = 0.0
		create_tween().tween_property(_build_panel, "modulate:a", 1.0, 0.15)
	_hud_key = ""

func _update_hud_text() -> void:
	if _build_title == null or build_options.is_empty() or selected_module_index >= build_options.size():
		return
	var id: String = build_options[selected_module_index]["id"]
	var key := "%s|%d|%s" % [id, GameManager.get_item_count(id), str(can_place)]
	if key == _hud_key:
		return
	_hud_key = key
	var txt := "Placing: %s  (x%d left)" % [id, GameManager.get_item_count(id)]
	if not can_place:
		txt += "  -  can't go here"
	_build_title.text = txt
	(_build_title.label_settings as LabelSettings).font_color = C_CYAN if can_place else C_RED
	_build_panel.add_theme_stylebox_override("panel", _panel_ok if can_place else _panel_bad)

func _flash_hint(text: String, col: Color) -> void:
	if _toast == null:
		return
	_toast.text = text
	(_toast.label_settings as LabelSettings).font_color = col
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)

# - wires -
func _nearest_broken_module() -> BaseModule:
	var best: BaseModule = null
	var bd := INF
	for m in BaseManager.active_modules:
		if is_instance_valid(m) and m.is_broken:
			var d: float = m.get_center().distance_to(global_position)
			if d <= m.interact_radius() and d < bd:
				bd = d
				best = m
	return best

func _broken_module_in_reach() -> bool:
	return _nearest_broken_module() != null

func _try_interact() -> void:
	# E also repairs broken modules (hold). Don't grab wires while you're trying to fix something.
	if current_wire == null and _broken_module_in_reach():
		return

	if current_wire != null:
		var receiver: Node2D = _find_nearby_receiver(current_wire)
		if receiver != null and _reactor_full(current_wire, receiver):
			var pct := BaseManager.current_power_draw / maxf(BaseManager.total_power, 1.0) * 100.0
			if pct >= 99.5:
				_flash_hint("Reactor is already at 100% power!", C_RED)
			else:
				_flash_hint("Not enough power left for that!", C_RED)
			_sq_vel.x += 3.0 * (1.0 if randf() > 0.5 else -1.0)
			shake(0.15)
			return
		if receiver != null:
			receiver.accept_wire(current_wire)
			current_wire.plug_in(receiver)
			current_wire = null
			var rp: Vector2 = receiver.get_receiver_position() if receiver.has_method("get_receiver_position") else receiver.global_position
			Fx.burst(get_parent(), rp, Color(1.2, 3.0, 3.6, 1.0), 14, 40.0, 140.0, 0.45, 0.04, 0.09, true)
			Ring.spawn(get_parent(), rp, Color(0.4, 1.3, 1.6), 44.0, 0.35)
			_pop(0.14)
			shake(0.12)
		else:
			var refusing := _wrong_receiver_near(current_wire)
			if refusing != null:
				_deny_wire(refusing)
				return
			current_wire.drop(global_position)
			current_wire = null
			_pop(0.08)
		return

	var dropped_wire: Node2D = _find_closest_dropped_wire()
	if dropped_wire != null:
		current_wire = dropped_wire
		current_wire.pick_up(global_position)
		_grab_fx()
		return

	var plugged_wire: Node2D = _find_closest_plugged_wire()
	if plugged_wire != null:
		if is_instance_valid(plugged_wire.plugged_receiver) and plugged_wire.plugged_receiver.has_method("remove_wire"):
			plugged_wire.plugged_receiver.remove_wire(plugged_wire)
		current_wire = plugged_wire
		current_wire.pick_up(global_position)
		_grab_fx()
		return

	var source: Node2D = _find_closest_wire_source()
	if source != null:
		var new_wire: Node2D = source.spawn_wire()
		if new_wire != null:
			current_wire = new_wire
			current_wire.pick_up(global_position)
			_grab_fx()

func _grab_fx() -> void:
	_pop(-0.14)
	Fx.burst(get_parent(), global_position + facing_vec * 20.0, Color(1.4, 1.4, 1.6, 0.9), 8, 30.0, 90.0, 0.3, 0.03, 0.06, true)

func _get_all_wires() -> Array[Node]:
	return get_tree().get_nodes_in_group("wires")

func _find_closest_dropped_wire() -> Node2D:
	var closest_wire: Node2D = null
	var min_dist: float = pickup_range
	for node in _get_all_wires():
		if node is Node2D and node.has_method("pick_up") and not node.is_held and not node.is_plugged:
			var dist: float = global_position.distance_to(node.hand_pos)
			if dist <= min_dist:
				min_dist = dist
				closest_wire = node
	return closest_wire

func _find_closest_plugged_wire() -> Node2D:
	var closest_wire: Node2D = null
	var min_dist: float = pickup_range
	for node in _get_all_wires():
		if node is Node2D and node.has_method("pick_up") and not node.is_held and node.is_plugged:
			var dist: float = global_position.distance_to(node.hand_pos)
			if dist <= min_dist:
				min_dist = dist
				closest_wire = node
	return closest_wire

func _find_closest_wire_source() -> Node2D:
	var closest_source: Node2D = null
	var min_dist: float = grab_range
	for node in get_tree().get_nodes_in_group("wire_sources"):
		if node is Node2D and node.has_method("spawn_wire") and node.has_method("can_spawn_wire"):
			if not node.can_spawn_wire():
				continue
			var dist: float = global_position.distance_to(node.global_position)
			if dist <= min_dist:
				min_dist = dist
				closest_source = node
	return closest_source

func _find_nearby_receiver(w: Node2D = null) -> Node2D:
	var closest_receiver: Node2D = null
	var min_dist: float = plug_range
	for node in get_tree().get_nodes_in_group("wire_receivers"):
		if node is Node2D and node.has_method("can_accept_wire") and node.can_accept_wire(w):
			var target_pos: Vector2 = node.get_receiver_position() if node.has_method("get_receiver_position") else node.global_position
			var dist: float = global_position.distance_to(target_pos)
			if dist <= min_dist:
				min_dist = dist
				closest_receiver = node
	if closest_receiver != null:
		return closest_receiver

	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = plug_range
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 1
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query, 16)
	for hit in hits:
		var area: Object = hit.get("collider")
		if area is Area2D and area.name == "InteractArea":
			var module: Node = area.get_parent()
			if module is BaseModule:
				for child in module.get_children():
					if child is Node2D and child.is_in_group("wire_receivers") and child.can_accept_wire(w):
						var target_pos: Vector2 = child.get_receiver_position()
						var dist: float = global_position.distance_to(target_pos)
						if dist < min_dist:
							min_dist = dist
							closest_receiver = child
	return closest_receiver

# - effect helpers -
func _has_buildables() -> bool:
	for item in GameManager.catalog:
		if item.has("scene_path") and str(item["scene_path"]) != "" and GameManager.get_item_count(item["id"]) > 0:
			return true
	return false

func _ghost_reach() -> float:
	return minf(build_radius, _ghost_zone - 40.0)

func _reactor_full(w: Node2D, r: Node2D) -> bool:
	var src: Variant = w.get("source_module")
	if not (src is BaseModule) or (src as BaseModule).module_name != "Reactor":
		return false
	if BaseManager.total_power <= 0.0:
		return false
	var tm: Variant = r.get("target_module")
	var need: float = (tm as BaseModule).power_draw if tm is BaseModule else 0.0
	return BaseManager.current_power_draw + need > BaseManager.total_power + 0.01

func _wrong_receiver_near(w: Node2D) -> Node2D:
	for node in get_tree().get_nodes_in_group("wire_receivers"):
		if node is Node2D and node.has_method("accepts_wire") and not node.accepts_wire(w):
			var rp: Vector2 = node.get_receiver_position() if node.has_method("get_receiver_position") else node.global_position
			if global_position.distance_to(rp) <= plug_range:
				return node
	return null

func _deny_wire(r: Node2D) -> void:
	var names := ""
	if "accepted_sources" in r:
		names = " or ".join(r.accepted_sources)
	if names != "":
		_flash_hint("Only %s wires fit here!" % names, C_AMBER)
	else:
		_flash_hint("That wire doesn't fit here!", C_AMBER)
	_sq_vel.x += 3.0 * (1.0 if randf() > 0.5 else -1.0)
	shake(0.15)

# ----- corner key hints + glowing "you can do something here" markers -----
func _make_hint_panel() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.16, 0.82)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_hint_panel.add_theme_stylebox_override("panel", sb)
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_panel.offset_left = 20
	_hint_panel.offset_right = 20
	_hint_panel.offset_top = -20
	_hint_panel.offset_bottom = -20
	_hint_panel.visible = false
	_hint_box = VBoxContainer.new()
	_hint_box.add_theme_constant_override("separation", 6)
	_hint_panel.add_child(_hint_box)
	_hud.add_child(_hint_panel)

func _set_hint_rows(rows: Array) -> void:
	if _hint_box == null:
		return
	var key := ""
	for r in rows:
		key += str(r[0]) + "|" + str(r[1]) + ";"
	if key == _hint_key_cache:
		return
	_hint_key_cache = key
	for c in _hint_box.get_children():
		c.queue_free()
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var chip := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.98, 0.86, 0.4)
		cs.set_corner_radius_all(7)
		cs.content_margin_left = 9
		cs.content_margin_right = 9
		cs.content_margin_top = 2
		cs.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", cs)
		var kl := _lbl(15, Color(0.18, 0.12, 0.0))
		(kl.label_settings as LabelSettings).outline_size = 0
		kl.text = str(r[0])
		chip.add_child(kl)
		var tl := _lbl(17, Color(0.94, 0.96, 1.0))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tl.text = str(r[1])
		row.add_child(chip)
		row.add_child(tl)
		_hint_box.add_child(row)

func _compute_hint_rows() -> Array:
	var rows: Array = []
	if is_build_mode:
		rows.append(["E or CLICK", "Place it"])
		if build_options.size() > 1:
			rows.append(["TAB or SCROLL", "Pick another"])
		rows.append(["CLICK a plug", "Turn it"])
		rows.append(["SPACE", "Stop building"])
		return rows
	rows.append(["WASD", "Walk"])
	var e_text := "Grab a wire"
	match _hint_kind:
		"plug":
			e_text = "Plug the wire in"
		"drop":
			e_text = "Drop the wire"
		"fix":
			e_text = "Hold to fix it"
		"grab":
			e_text = "Grab the wire"
	rows.append(["E", e_text])
	if _has_buildables() and not is_outside:
		rows.append(["SPACE", "Build stuff"])
	return rows

func _update_hints() -> void:
	if not is_active:
		return
	_hint_marks.clear()
	_hint_kind = ""
	if not is_build_mode:
		if current_wire != null and is_instance_valid(current_wire):
			var r: Node2D = _find_nearby_receiver(current_wire)
			if r != null:
				_hint_kind = "plug"
				var rp: Vector2 = r.get_receiver_position() if r.has_method("get_receiver_position") else r.global_position
				_hint_marks.append({"pos": rp, "col": C_GREEN, "text": "E  plug in"})
			else:
				_hint_kind = "drop"
				var bad := _wrong_receiver_near(current_wire)
				if bad != null:
					var bp: Vector2 = bad.get_receiver_position() if bad.has_method("get_receiver_position") else bad.global_position
					_hint_marks.append({"pos": bp, "col": C_RED, "text": "doesn't fit"})
		else:
			var broken := _nearest_broken_module()
			if broken != null:
				_hint_kind = "fix"
				_hint_marks.append({"pos": broken.get_center(), "col": C_AMBER, "text": "hold E  fix"})
			else:
				var dw := _find_closest_dropped_wire()
				if dw != null:
					_hint_kind = "grab"
					_hint_marks.append({"pos": dw.hand_pos, "col": C_CYAN, "text": "E  grab"})
				else:
					var pw := _find_closest_plugged_wire()
					if pw != null:
						_hint_kind = "grab"
						_hint_marks.append({"pos": pw.hand_pos, "col": C_CYAN, "text": "E  unplug"})
					else:
						var src := _find_closest_wire_source()
						if src != null:
							_hint_kind = "grab"
							_hint_marks.append({"pos": src.global_position, "col": C_CYAN, "text": "E  grab wire"})
	_set_hint_rows(_compute_hint_rows())

## Drawn by the Hints node (world space, always on top): the build circle in build mode.
func _overlay_draw(c: Node2D) -> void:
	if not is_build_mode or not is_instance_valid(ghost_module):
		return
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var col := Color(0.45, 1.0, 0.6) if can_place else Color(1.0, 0.4, 0.35)
	var rx := _reactor_node()
	if rx != null:
		c.draw_circle(rx.get_center(), reactor_block_radius, Color(1.0, 0.3, 0.25, 0.07))
		c.draw_arc(rx.get_center(), reactor_block_radius, 0.0, TAU, 96, Color(1.0, 0.35, 0.3, 0.55 + 0.2 * pulse), 3.0, true)
	var ex := _exit_rect()
	if ex.size != Vector2.ZERO:
		var eg := ex.grow(exit_block_margin)
		c.draw_rect(eg, Color(1.0, 0.3, 0.25, 0.07))
		c.draw_rect(eg, Color(1.0, 0.35, 0.3, 0.55 + 0.2 * pulse), false, 3.0)
	c.draw_arc(global_position, _ghost_reach(), 0.0, TAU, 96, Color(1, 1, 1, 0.12 + 0.06 * pulse), 2.0, true)
	var ctr := _ghost_origin + _ghost_center_off
	c.draw_circle(ctr, _ghost_zone, Color(col.r, col.g, col.b, 0.05))
	var n := 40
	for i in n:
		if i % 2 == 0:
			var a := TAU * i / n + _t * 0.2
			c.draw_arc(ctr, _ghost_zone, a, a + TAU / n * 0.8, 6, Color(col.r, col.g, col.b, 0.8), 3.0, true)
	var f := ThemeDB.fallback_font
	var msg := "Stay inside the circle while it builds"
	var w := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	c.draw_string(f, ctr + Vector2(-w * 0.5, -_ghost_zone - 14.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(col.r, col.g, col.b, 0.95))

class Hints extends Node2D:
	var p: Node
	var t := 0.0
	func _ready() -> void:
		top_level = true
		global_position = Vector2.ZERO
		z_as_relative = false
		z_index = 300
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		if p == null or not is_instance_valid(p):
			return
		p.call("_overlay_draw", self)
		var marks: Array = p.get("_hint_marks")
		var f := ThemeDB.fallback_font
		for m in marks:
			var pos: Vector2 = m["pos"]
			var col: Color = m["col"]
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			draw_arc(pos, 30.0 + 4.0 * pulse, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.35 + 0.35 * pulse), 3.0, true)
			var tag := str(m["text"])
			var w := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var bp := pos + Vector2(0, -48.0 - 4.0 * pulse)
			draw_rect(Rect2(bp.x - w * 0.5 - 9.0, bp.y - 18.0, w + 18.0, 26.0), Color(col.r * 0.9 + 0.1, col.g * 0.9 + 0.1, col.b * 0.9 + 0.1, 0.95))
			draw_string(f, Vector2(bp.x - w * 0.5, bp.y), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.08, 0.06, 0.02))

class Fx:
	static var _soft: GradientTexture2D = null
	static func tex() -> GradientTexture2D:
		if _soft == null:
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			g.add_point(0.35, Color(1, 1, 1, 0.55))
			_soft = GradientTexture2D.new()
			_soft.gradient = g
			_soft.fill = GradientTexture2D.FILL_RADIAL
			_soft.fill_from = Vector2(0.5, 0.5)
			_soft.fill_to = Vector2(1.0, 0.5)
			_soft.width = 64
			_soft.height = 64
		return _soft

	## fire-and-forget one-shot particle burst (frees itself)
	static func burst(parent: Node, pos: Vector2, col: Color, amount: int, v_min: float, v_max: float, life: float, s_min: float, s_max: float, additive: bool = false, grav: Vector2 = Vector2.ZERO) -> void:
		if parent == null or not parent.is_inside_tree():
			return
		var p := CPUParticles2D.new()
		p.texture = tex()
		p.one_shot = true
		p.explosiveness = 0.95
		p.amount = amount
		p.lifetime = life
		p.spread = 180.0
		p.initial_velocity_min = v_min
		p.initial_velocity_max = v_max
		p.gravity = grav
		p.scale_amount_min = s_min
		p.scale_amount_max = s_max
		p.color = col
		p.local_coords = false
		p.z_index = 70
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = g
		if additive:
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			p.material = m
		parent.add_child(p)
		p.global_position = pos
		p.emitting = true
		parent.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)

class Ring extends Node2D:
	var r := 4.0
	var a := 1.0
	var w := 4.0
	var col := Color(0.4, 1.3, 1.6)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 56, Color(col.r, col.g, col.b, a), w, true)
	static func spawn(parent: Node, pos: Vector2, color: Color, max_r: float, dur: float) -> void:
		if parent == null or not parent.is_inside_tree():
			return
		var ring := Ring.new()
		ring.col = color
		ring.z_index = 80
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ring.material = m
		parent.add_child(ring)
		ring.global_position = pos
		var tw := ring.create_tween().set_parallel(true)
		tw.tween_property(ring, "r", max_r, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ring, "a", 0.0, dur)
		tw.tween_property(ring, "w", 1.0, dur)
		tw.chain().tween_callback(ring.queue_free)

## Lives next to a module while it's being built: smoke + sparks while you're in range,
## a nice drawn progress bar, and a pop + flash when it finishes.
class ConstructionFX extends Node2D:
	var target: BaseModule
	var player: Node2D
	var half := Vector2(64, 64)
	var center := Vector2.ZERO
	var font: Font
	var smoke: CPUParticles2D
	var sparks: CPUParticles2D
	var shown := 0.0
	var near := true
	var t := 0.0
	var bg_style: StyleBoxFlat
	var fill_style: StyleBoxFlat

	func setup(m: Node, p: Node2D, center_off: Vector2, half_size: Vector2, f: Font) -> void:
		target = m
		player = p
		center = center_off
		half = half_size
		font = f
		z_index = 90
		global_position = m.global_position + center

		bg_style = StyleBoxFlat.new()
		bg_style.bg_color = Color(0.04, 0.06, 0.09, 0.92)
		bg_style.border_color = Color(0.3, 0.85, 1.0, 0.8)
		bg_style.set_border_width_all(1)
		bg_style.set_corner_radius_all(4)
		bg_style.shadow_color = Color(0.3, 0.85, 1.0, 0.25)
		bg_style.shadow_size = 8
		fill_style = StyleBoxFlat.new()
		fill_style.set_corner_radius_all(3)

		smoke = CPUParticles2D.new()
		smoke.texture = Fx.tex()
		smoke.amount = 26
		smoke.lifetime = 2.2
		smoke.local_coords = false
		smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		smoke.emission_rect_extents = Vector2(half.x * 0.8, half.y * 0.5)
		smoke.direction = Vector2(0, -1)
		smoke.spread = 25.0
		smoke.initial_velocity_min = 14.0
		smoke.initial_velocity_max = 34.0
		smoke.gravity = Vector2(0, -6)
		smoke.scale_amount_min = 0.5
		smoke.scale_amount_max = 0.9
		var cv := Curve.new()
		cv.add_point(Vector2(0, 0.4))
		cv.add_point(Vector2(1, 1.7))
		smoke.scale_amount_curve = cv
		smoke.color = Color(0.72, 0.75, 0.82, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.2, Color(1, 1, 1, 1))
		smoke.color_ramp = g
		smoke.emitting = false
		add_child(smoke)

		sparks = CPUParticles2D.new()
		sparks.texture = Fx.tex()
		sparks.amount = 14
		sparks.lifetime = 0.55
		sparks.local_coords = false
		sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		sparks.emission_rect_extents = half * 0.9
		sparks.direction = Vector2(0, -1)
		sparks.spread = 180.0
		sparks.initial_velocity_min = 40.0
		sparks.initial_velocity_max = 120.0
		sparks.gravity = Vector2(0, 220)
		sparks.scale_amount_min = 0.03
		sparks.scale_amount_max = 0.07
		sparks.color = Color(1.8, 1.2, 0.5, 1.0)
		var g2 := Gradient.new()
		g2.set_color(0, Color(1, 1, 1, 1))
		g2.set_color(1, Color(1, 1, 1, 0))
		sparks.color_ramp = g2
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sparks.material = mat
		sparks.emitting = false
		add_child(sparks)

	func _process(delta: float) -> void:
		if not is_instance_valid(target):
			queue_free()
			return
		t += delta
		global_position = target.global_position + center
		if not target.is_constructing:
			_finish()
			return
		near = is_instance_valid(player) and target.get_center().distance_to(player.global_position) <= target.interact_radius()
		smoke.emitting = near
		sparks.emitting = near
		shown = lerpf(shown, clampf(target.build_progress / 100.0, 0.0, 1.0), 1.0 - exp(-16.0 * delta))
		# our own bar replaces the default one; the module "materialises" as it builds
		if target.progress_bar != null:
			target.progress_bar.visible = false
		queue_redraw()

	func _finish() -> void:
		var par := get_parent()
		if is_instance_valid(target):
			target.modulate = Color(2.2, 2.2, 2.4, 1.0)
			target.create_tween().tween_property(target, "modulate", Color.WHITE, 0.45)
		Fx.burst(par, global_position, Color(0.8, 0.85, 0.95, 0.6), 26, 60.0, 200.0, 0.9, 0.3, 0.8)
		Fx.burst(par, global_position, Color(0.5, 1.6, 2.0, 1.0), 30, 100.0, 280.0, 0.7, 0.04, 0.1, true)
		Ring.spawn(par, global_position, Color(0.4, 1.4, 1.8), maxf(half.x, half.y) * 1.8, 0.6)
		if is_instance_valid(player):
			player.call("shake", 0.45)
			player.call("_pop", 0.16)
		queue_free()

	func _draw() -> void:
		var zone := target.interact_radius() if is_instance_valid(target) else 250.0
		zone *= 1.0 - pow(1.0 - clampf(t * 4.0, 0.0, 1.0), 3.0)
		var pulse := 0.5 + 0.5 * sin(t * 5.0)
		var ring_col := Color(0.45, 1.0, 0.6, 0.7) if near else Color(1.0, 0.35, 0.3, 0.6 + 0.35 * pulse)
		draw_circle(Vector2.ZERO, zone, Color(ring_col.r, ring_col.g, ring_col.b, 0.05 if near else 0.10))
		var n := 40
		for i in n:
			if i % 2 == 0:
				var a := TAU * i / n + t * 0.2
				draw_arc(Vector2.ZERO, zone, a, a + TAU / n * 0.8, 6, ring_col, 3.0 if near else 5.0, true)
		var w := clampf(half.x * 1.6, 110.0, 220.0)
		var h := 14.0
		var pos := Vector2(-w * 0.5, -half.y - 36.0)
		draw_style_box(bg_style, Rect2(pos - Vector2(3, 3), Vector2(w + 6, h + 6)))
		var col := Color(0.4, 1.15, 0.55) if near else Color(1.1, 0.3, 0.25)
		fill_style.bg_color = col
		var fw := w * shown
		if fw > 1.0:
			draw_style_box(fill_style, Rect2(pos, Vector2(maxf(fw, 6.0), h)))
			var bx := pos.x + fposmod(t * 120.0, maxf(fw, 1.0))
			draw_rect(Rect2(bx, pos.y, minf(14.0, pos.x + fw - bx), h), Color(1, 1, 1, 0.3))
			draw_rect(Rect2(pos.x + fw - 2.0, pos.y, 2.0, h), Color(1, 1, 1, 0.9))
		var label := "Building...  %d%%" % int(shown * 100.0) if near else "Come back inside the circle!"
		draw_string(font, pos + Vector2(-60, -10), label, HORIZONTAL_ALIGNMENT_CENTER, w + 120, 17, Color(col.r, col.g, col.b, 1.0))

