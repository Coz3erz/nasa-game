extends Node2D

@export var rope_segments: int = 24
@export var damping: float = 0.85
@export var max_length: float = 320.0
@export var stretch_limit: float = 110.0
@export var pull_strength: float = 14.0
@export var solver_iterations: int = 18
@export var collision_radius: float = 6.0

var is_held: bool = false
var is_plugged: bool = false
var is_dropped: bool = false

var source_node: Node2D = null
var source_module: BaseModule = null
var plugged_receiver: Node2D = null
var target_module: BaseModule = null

var wire_color: Color = Color(0.85, 0.15, 0.15)
var current_stretch_ratio: float = 0.0

var wire: Line2D
var shadow: Line2D

var socket_pos: Vector2 = Vector2.ZERO
var hand_pos: Vector2 = Vector2.ZERO

var rope_points: Array[Vector2] = []
var old_rope_points: Array[Vector2] = []
var ignored_rids: Array[RID] = []

var collision_shape: CircleShape2D
var shape_query: PhysicsShapeQueryParameters2D

var plug_body_style: StyleBoxFlat
var plug_boot_style: StyleBoxFlat
var plug_shadow_style: StyleBoxFlat

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 2
	add_to_group("wires")

	wire = $Line2D
	shadow = $Line2DShadow

	wire.width = 12.0
	wire.joint_mode = Line2D.LINE_JOINT_ROUND
	wire.begin_cap_mode = Line2D.LINE_CAP_ROUND
	wire.end_cap_mode = Line2D.LINE_CAP_ROUND
	wire.antialiased = true
	wire.default_color = wire_color
	wire.show_behind_parent = true

	shadow.width = 16.0
	shadow.joint_mode = Line2D.LINE_JOINT_ROUND
	shadow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	shadow.end_cap_mode = Line2D.LINE_CAP_ROUND
	shadow.antialiased = true
	shadow.default_color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(4, 6)
	shadow.show_behind_parent = true
	shadow.z_index = -1

	collision_shape = CircleShape2D.new()
	collision_shape.radius = collision_radius

	shape_query = PhysicsShapeQueryParameters2D.new()
	shape_query.shape = collision_shape
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false
	shape_query.collision_mask = 1

	plug_body_style = StyleBoxFlat.new()
	plug_body_style.bg_color = Color(0.22, 0.24, 0.28)
	plug_body_style.border_color = Color(0.1, 0.11, 0.13)
	plug_body_style.set_border_width_all(2)
	plug_body_style.set_corner_radius_all(5)

	plug_boot_style = StyleBoxFlat.new()
	plug_boot_style.bg_color = Color(0.14, 0.15, 0.18)
	plug_boot_style.set_corner_radius_all(3)

	plug_shadow_style = StyleBoxFlat.new()
	plug_shadow_style.bg_color = Color(0, 0, 0, 0.45)
	plug_shadow_style.set_corner_radius_all(5)

func register_ignored_rid(rid: RID) -> void:
	if rid.is_valid() and not ignored_rids.has(rid):
		ignored_rids.append(rid)

func setup(start_pos: Vector2, custom_color: Color = Color(0.85, 0.15, 0.15), origin_source: Node2D = null) -> void:
	socket_pos = start_pos
	hand_pos = start_pos
	wire_color = custom_color
	source_node = origin_source
	if origin_source != null and origin_source.get_parent() is BaseModule:
		source_module = origin_source.get_parent() as BaseModule

	is_held = false
	is_plugged = false
	is_dropped = true
	plugged_receiver = null
	target_module = null

	if wire != null:
		wire.default_color = wire_color

	rope_points.clear()
	old_rope_points.clear()

	for i in range(rope_segments + 1):
		rope_points.append(start_pos)
		old_rope_points.append(start_pos)

func pick_up(player_pos: Vector2) -> void:
	is_held = true
	is_plugged = false
	is_dropped = false
	plugged_receiver = null
	target_module = null
	hand_pos = player_pos
	if wire != null:
		wire.default_color = wire_color

func drop(drop_pos: Vector2) -> void:
	is_held = false
	is_plugged = false
	is_dropped = true
	plugged_receiver = null
	target_module = null
	hand_pos = drop_pos
	if wire != null:
		wire.default_color = wire_color

func plug_in(receiver_node: Node2D) -> void:
	is_held = false
	is_plugged = true
	is_dropped = false
	plugged_receiver = receiver_node
	if receiver_node.get_parent() is BaseModule:
		target_module = receiver_node.get_parent() as BaseModule
	elif "target_module" in receiver_node:
		target_module = receiver_node.target_module

	if receiver_node.has_method("get_rid"):
		register_ignored_rid(receiver_node.call("get_rid"))
	if receiver_node.has_method("get_receiver_position"):
		hand_pos = receiver_node.get_receiver_position()
	else:
		hand_pos = receiver_node.global_position
	if wire != null:
		wire.default_color = wire_color

func get_total_rope_length() -> float:
	if rope_points.size() < 2:
		return 0.0
	var total: float = 0.0
	for i in range(rope_segments):
		total += rope_points[i].distance_to(rope_points[i + 1])
	return total

func apply_tension_to_player(player: CharacterBody2D, delta: float) -> bool:
	if rope_points.size() < 2:
		return false

	var total_len: float = get_total_rope_length()
	if total_len <= max_length:
		current_stretch_ratio = 0.0
		return false

	var over_stretch: float = total_len - max_length
	current_stretch_ratio = clampf(over_stretch / stretch_limit, 0.0, 1.0)

	var anchor_pt: Vector2 = rope_points[max(0, rope_segments - 2)]
	var pull_dir: Vector2 = (anchor_pt - player.global_position).normalized()

	player.velocity += pull_dir * (over_stretch * pull_strength)
	player.global_position += pull_dir * (over_stretch * 0.35 * delta * 60.0)

	if over_stretch > stretch_limit * 1.15:
		return true

	return false

func _process(delta: float) -> void:
	if is_instance_valid(source_node):
		socket_pos = source_node.global_position

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null and get_tree().current_scene != null:
		player = get_tree().current_scene.get_node_or_null("Player") as Node2D
	if player != null and player.has_method("get_rid"):
		register_ignored_rid(player.call("get_rid"))

	if is_held and player != null:
		hand_pos = player.global_position
	elif is_plugged and is_instance_valid(plugged_receiver):
		if plugged_receiver.has_method("get_receiver_position"):
			hand_pos = plugged_receiver.get_receiver_position()
		else:
			hand_pos = plugged_receiver.global_position

	_simulate_rope(delta)
	queue_redraw()

func _simulate_rope(_delta: float) -> void:
	if rope_points.is_empty():
		return

	var last_idx: int = rope_segments
	var end_locked: bool = is_held or is_plugged
	var rest_seg_len: float = max_length / float(rope_segments)

	for i in range(1, last_idx + 1):
		if i == last_idx and end_locked:
			continue
		var vel: Vector2 = (rope_points[i] - old_rope_points[i]) * damping
		old_rope_points[i] = rope_points[i]
		rope_points[i] += vel

	rope_points[0] = socket_pos
	if end_locked:
		rope_points[last_idx] = hand_pos
		old_rope_points[last_idx] = hand_pos

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	shape_query.exclude = ignored_rids

	for iter in range(solver_iterations):
		for i in range(rope_segments):
			var delta_vec: Vector2 = rope_points[i + 1] - rope_points[i]
			var d: float = delta_vec.length()
			if d < 0.0001:
				continue

			var stiffness: float = 0.88 if d > rest_seg_len else 0.65
			var correction: Vector2 = (delta_vec / d) * (d - rest_seg_len) * stiffness

			if i == 0:
				rope_points[i + 1] -= correction
			elif i == last_idx - 1 and end_locked:
				rope_points[i] += correction
			else:
				rope_points[i] += correction * 0.5
				rope_points[i + 1] -= correction * 0.5

		rope_points[0] = socket_pos
		if end_locked:
			rope_points[last_idx] = hand_pos

		if iter % 2 == 0 or iter == solver_iterations - 1:
			_solve_collisions(space_state, end_locked)

	if is_dropped:
		hand_pos = rope_points[last_idx]
		current_stretch_ratio = 0.0
	else:
		var total_len: float = get_total_rope_length()
		current_stretch_ratio = clampf((total_len - max_length) / stretch_limit, 0.0, 1.0)

	wire.width = lerpf(12.0, 7.5, current_stretch_ratio)
	shadow.width = lerpf(16.0, 10.5, current_stretch_ratio)

	var packed: PackedVector2Array = PackedVector2Array(rope_points)
	wire.points = packed
	shadow.points = packed

func _solve_collisions(space_state: PhysicsDirectSpaceState2D, end_locked: bool) -> void:
	var last_idx: int = rope_segments
	var max_point_idx: int = last_idx if end_locked else last_idx + 1

	for i in range(1, max_point_idx):
		shape_query.transform = Transform2D(0.0, rope_points[i])
		var contacts: Array[Vector2] = space_state.collide_shape(shape_query, 4)
		if not contacts.is_empty():
			var push: Vector2 = Vector2.ZERO
			var count: float = 0.0
			for c in range(0, contacts.size(), 2):
				push += (contacts[c + 1] - contacts[c])
				count += 1.0
			if count > 0.0:
				var displacement: Vector2 = push / count
				rope_points[i] += displacement
				old_rope_points[i] = old_rope_points[i].lerp(rope_points[i], 0.6)

	for i in range(1, last_idx - 1):
		var mid: Vector2 = (rope_points[i] + rope_points[i + 1]) * 0.5
		shape_query.transform = Transform2D(0.0, mid)
		var contacts: Array[Vector2] = space_state.collide_shape(shape_query, 2)
		if not contacts.is_empty():
			var push: Vector2 = contacts[1] - contacts[0]
			rope_points[i] += push * 0.5
			rope_points[i + 1] += push * 0.5
			old_rope_points[i] = old_rope_points[i].lerp(rope_points[i], 0.5)
			old_rope_points[i + 1] = old_rope_points[i + 1].lerp(rope_points[i + 1], 0.5)

func _draw() -> void:
	if rope_points.size() < 2:
		return

	var end_pt: Vector2 = rope_points[rope_segments]
	var prev_pt: Vector2 = rope_points[rope_segments - 1]
	var dir: Vector2 = end_pt - prev_pt
	var angle: float = dir.angle() if dir.length_squared() > 0.01 else 0.0

	var shadow_offset: Vector2 = Vector2(4, 6).rotated(-angle)
	draw_set_transform(end_pt, angle, Vector2.ONE)

	draw_style_box(plug_shadow_style, Rect2(Vector2(-10, -8) + shadow_offset, Vector2(20, 16)))

	if not is_plugged:
		var prong_col: Color = Color(0.78, 0.82, 0.86)
		draw_rect(Rect2(8, -5, 6, 3), prong_col)
		draw_circle(Vector2(14, -3.5), 1.5, prong_col)
		draw_rect(Rect2(8, 2, 6, 3), prong_col)
		draw_circle(Vector2(14, 3.5), 1.5, prong_col)

	draw_style_box(plug_boot_style, Rect2(-14, -5, 7, 10))
	draw_style_box(plug_body_style, Rect2(-9, -8, 18, 16))
	draw_line(Vector2(-3, -4), Vector2(-3, 4), wire_color, 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
