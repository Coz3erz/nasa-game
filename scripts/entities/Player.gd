extends CharacterBody2D

@export var speed: float = 300.0
@export var rope_segments: int = 20
@export var damping: float = 0.85
@export var snap_speed: float = 3000.0
@export var min_segment_length: float = 15.0
@export var solver_iterations: int = 15
@export var grab_range: float = 150.0
@export var plug_range: float = 40.0
@export var reactor_half_size: float = 64.0
@export var shadow_offset: Vector2 = Vector2(4.0, 6.0)
@export var max_stretch_distance: float = 600.0

var is_holding_wire: bool = false
var is_plugged_in: bool = false
var is_snapping_back: bool = false

var current_wire: Line2D = null
var wire_shadow: Line2D = null
var reactor_node: Node2D = null

var rope_points: Array[Vector2] = []
var old_rope_points: Array[Vector2] = []
var hand_pos: Vector2 = Vector2.ZERO
var socket_pos: Vector2 = Vector2.ZERO
var reactor_center: Vector2 = Vector2.ZERO

func _ready() -> void:
visible = false
set_physics_process(false)

func enable_player() -> void:
visible = true
set_physics_process(true)
position = Vector2(320, 600)
velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
var input_dir: Vector2 = Input.get_vector(“ui_left”, “ui_right”, “ui_up”, “ui_down”)
velocity = input_dir * speed
move_and_slide()

if not is_instance_valid(reactor_node):
	return

reactor_center = reactor_node.global_position + Vector2(reactor_half_size, reactor_half_size)

if is_holding_wire:
	hand_pos = global_position
	_update_socket()
	_simulate_rope()
elif is_snapping_back:
	hand_pos = hand_pos.move_toward(socket_pos, snap_speed * delta)
	_simulate_rope()
	if hand_pos.distance_to(socket_pos) < 5.0:
		_destroy_wire()
elif is_plugged_in:
	_simulate_rope()

func _update_socket() -> void:
var dir: Vector2 = hand_pos - reactor_center
if dir.length_squared() < 0.0001:
dir = Vector2.RIGHT
else:
dir = dir.normalized()
socket_pos = reactor_center + dir * reactor_half_size

func _simulate_rope() -> void:
if rope_points.is_empty() or current_wire == null or wire_shadow == null:
return

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
current_wire.points = packed
wire_shadow.points = packed

var stretch: float = clamp(dist / max_stretch_distance, 0.0, 1.0)
current_wire.width = lerp(12.0, 5.0, stretch)
wire_shadow.width = lerp(16.0, 7.0, stretch)

func _unhandled_input(event: InputEvent) -> void:
if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
_try_interact()

func _try_interact() -> void:
if is_plugged_in or is_snapping_back:
return

if not is_holding_wire:
	var reactor: Node2D = get_parent().get_node_or_null("Reactor")
	if reactor == null:
		return
	reactor_node = reactor
	reactor_center = reactor_node.global_position + Vector2(reactor_half_size, reactor_half_size)
	if global_position.distance_to(reactor_center) <= grab_range:
		_spawn_wire()
	return

var module: BaseModule = _find_module()
if module != null:
	_plug_into(module)
else:
	print("Missed! Snapping wire back.")
	is_holding_wire = false
	is_snapping_back = true

func _find_module() -> BaseModule:
var shape: CircleShape2D = CircleShape2D.new()
shape.radius = plug_range

var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
query.shape = shape
query.transform = Transform2D(0.0, global_position)
query.collide_with_areas = true
query.collide_with_bodies = false
query.collision_mask = 1

var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query, 8)
for hit in hits:
	var area = hit.collider
	if area is Area2D and area.name == "InteractArea":
		var module = area.get_parent()
		if module is BaseModule:
			return module
return null

func _plug_into(module: BaseModule) -> void:
module.is_powered = true
BaseManager.calculate_power()
print(“Plugged into “, module.module_name)

hand_pos = module.global_position
is_holding_wire = false
is_plugged_in = true

current_wire.default_color = Color(0.2, 1.0, 0.2)

func _spawn_wire() -> void:
is_holding_wire = true
is_snapping_back = false
is_plugged_in = false

hand_pos = global_position
_update_socket()

rope_points.clear()
old_rope_points.clear()
for i in range(rope_segments + 1):
	var t: float = float(i) / float(rope_segments)
	var pt: Vector2 = socket_pos.lerp(hand_pos, t)
	rope_points.append(pt)
	old_rope_points.append(pt)

wire_shadow = Line2D.new()
wire_shadow.width = 16.0
wire_shadow.default_color = Color(0, 0, 0, 0.45)
wire_shadow.z_index = -1
_stylize_line(wire_shadow)
wire_shadow.position = shadow_offset
get_parent().add_child(wire_shadow)

current_wire = Line2D.new()
current_wire.width = 12.0
current_wire.default_color = Color(0.8, 0.1, 0.1)
current_wire.z_index = 1
_stylize_line(current_wire)
current_wire.position = Vector2.ZERO
get_parent().add_child(current_wire)

_simulate_rope()
print("Grabbed wire!")

func _stylize_line(l: Line2D) -> void:
l.top_level = true
l.joint_mode = Line2D.LINE_JOINT_ROUND
l.begin_cap_mode = Line2D.LINE_CAP_ROUND
l.end_cap_mode = Line2D.LINE_CAP_ROUND
l.antialiased = true

func _destroy_wire() -> void:
is_snapping_back = false
if current_wire:
current_wire.queue_free()
if wire_shadow:
wire_shadow.queue_free()
current_wire = null
wire_shadow = null
rope_points.clear()
old_rope_points.clear()
