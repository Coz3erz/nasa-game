extends CharacterBody2D

@export var speed: float = 300.0
@export var rope_segments: int = 20
@export var damping: float = 0.85
@export var snap_speed: float = 3000.0
@export var spawn_speed: float = 2000.0
@export var min_segment_length: float = 15.0
@export var solver_iterations: int = 15
@export var grab_range: float = 200.0
@export var plug_range: float = 50.0

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D

var is_spawning: bool = false
var is_holding_wire: bool = false
var is_plugged_in: bool = false
var is_snapping_back: bool = false

var current_wire_data: Dictionary = {}
var reactor_node: Node2D = null
var wire_plug: Node2D = null

var rope_points: Array[Vector2] = []
var old_rope_points: Array[Vector2] = []
var hand_pos: Vector2 = Vector2.ZERO
var socket_pos: Vector2 = Vector2.ZERO
var reactor_center: Vector2 = Vector2.ZERO
var facing_dir: String = "down"

class CablePlug extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-20, -8, 20, 16), Color(0.13, 0.14, 0.17))
		draw_rect(Rect2(-20, -8, 20, 16), Color(0.38, 0.40, 0.46), false, 1.5)
		draw_rect(Rect2(-6, -8, 3, 16), Color(0.22, 0.24, 0.28))
		draw_rect(Rect2(0, -5, 10, 3), Color(0.88, 0.78, 0.32))
		draw_rect(Rect2(0, 2, 10, 3), Color(0.88, 0.78, 0.32))
		draw_circle(Vector2(-12, 0), 3.0, Color(0.2, 1.0, 0.3))

func _ready() -> void:
	visible = false
	set_physics_process(false)

func enable_player() -> void:
	visible = true
	set_physics_process(true)
	position = Vector2(320, 600)
	velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_dir * speed
	move_and_slide()
	_update_animation(input_dir)

	if not is_instance_valid(reactor_node):
		return

	if is_spawning:
		hand_pos = hand_pos.move_toward(global_position, spawn_speed * delta)
		_simulate_rope()
		if hand_pos.distance_to(global_position) < 5.0:
			is_spawning = false
			is_holding_wire = true
	elif is_holding_wire:
		hand_pos = global_position
		_simulate_rope()
	elif is_snapping_back:
		hand_pos = hand_pos.move_toward(socket_pos, snap_speed * delta)
		_simulate_rope()
		if hand_pos.distance_to(socket_pos) < 5.0:
			_cleanup_wire()
	elif is_plugged_in:
		pass 

func _update_animation(input_dir: Vector2) -> void:
	if input_dir.x < 0: 
		facing_dir = "left"
	elif input_dir.x > 0: 
		facing_dir = "right"
	elif input_dir.y < 0: facing_dir = "up"
	elif input_dir.y > 0: facing_dir = "down"

	var is_moving = input_dir != Vector2.ZERO
	var anim_prefix = "walk_" if is_moving else "idle_"
	var anim_name = anim_prefix + facing_dir

	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
	else:
		if facing_dir == "left" or facing_dir == "right":
			var fallback_name = anim_prefix + "down"
			if anim_player.has_animation(fallback_name):
				anim_player.play(fallback_name)
		elif anim_player.has_animation("idle"):
			anim_player.play("idle")

func _simulate_rope() -> void:
	if rope_points.is_empty() or current_wire_data.is_empty():
		return

	var wire: Line2D = current_wire_data["wire"]
	var shadow: Line2D = current_wire_data["shadow"]

	for i in range(1, rope_segments):
		var vel: Vector2 = (rope_points[i] - old_rope_points[i]) * damping
		old_rope_points[i] = rope_points[i]
		rope_points[i] += vel

	rope_points[0] = socket_pos
	rope_points[rope_segments] = hand_pos

	var dist: float = socket_pos.distance_to(hand_pos)
	var seg_length: float = max(min_segment_length, dist / float(rope_segments))

	for _iter in range(solver_iterations):
		for i in range(rope_segments):
			var delta_vec: Vector2 = rope_points[i + 1] - rope_points[i]
			var d: float = delta_vec.length()
			if d < 0.0001:
				continue
			var correction: Vector2 = delta_vec / d * (d - seg_length)
			if i == 0:
				rope_points[i + 1] -= correction
			elif i == rope_segments - 1:
				rope_points[i] += correction
			else:
				rope_points[i] += correction * 0.5
				rope_points[i + 1] -= correction * 0.5

	var packed: PackedVector2Array = PackedVector2Array(rope_points)
	wire.points = packed
	shadow.points = packed

	var stretch: float = clamp(dist / 600.0, 0.0, 1.0)
	wire.width = lerp(12.0, 5.0, stretch)
	shadow.width = lerp(16.0, 7.0, stretch)
	
	if wire_plug:
		wire_plug.position = hand_pos
		if is_spawning or is_holding_wire:
			var dir2 = (rope_points[rope_segments] - rope_points[rope_segments - 1])
			if dir2.length() > 0.001:
				wire_plug.rotation = dir2.angle()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_try_interact()

func _try_interact() -> void:
	if is_spawning or is_plugged_in or is_snapping_back:
		return

	if not is_holding_wire:
		reactor_node = get_parent().get_node_or_null("Reactor")
		if reactor_node and global_position.distance_to(reactor_node.global_position) <= grab_range:
			_spawn_wire()
	else:
		var module: BaseModule = _find_module()
		if module != null:
			_plug_into(module)
		else:
			is_holding_wire = false
			is_snapping_back = true
			if wire_plug: wire_plug.queue_free()

func _find_module() -> BaseModule:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = plug_range
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 1

	for hit in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var area = hit.collider
		if area is Area2D and area.name == "InteractArea":
			var module = area.get_parent()
			if module is BaseModule and module.can_accept_wires:
				return module
	return null

func _plug_into(module: BaseModule) -> void:
	module.accept_wire(current_wire_data)
	
	hand_pos = module.global_position
	is_holding_wire = false
	is_plugged_in = true
	current_wire_data["is_active"] = false
	
	current_wire_data["wire"].default_color = Color(0.2, 1.0, 0.2)
	if wire_plug: wire_plug.queue_free()

func _spawn_wire() -> void:
	is_spawning = true
	reactor_center = reactor_node.global_position + Vector2(64, 64)
	
	var dir = (global_position - reactor_center).normalized()
	if dir == Vector2.ZERO: dir = Vector2.RIGHT
	socket_pos = reactor_center + dir * 64.0
	hand_pos = socket_pos
	
	current_wire_data = reactor_node.request_new_wire(global_position)
	socket_pos = current_wire_data["socket_pos"]

	rope_points.clear()
	old_rope_points.clear()
	for i in range(rope_segments + 1):
		rope_points.append(socket_pos)
		old_rope_points.append(socket_pos)

	wire_plug = CablePlug.new()
	wire_plug.z_index = 3
	wire_plug.position = socket_pos
	get_parent().add_child(wire_plug)

	_simulate_rope()

func _cleanup_wire() -> void:
	is_snapping_back = false
	reactor_node.release_wire(current_wire_data)
	current_wire_data.clear()
	rope_points.clear()
	old_rope_points.clear()
	if wire_plug: 
		wire_plug.queue_free()
		wire_plug = null
