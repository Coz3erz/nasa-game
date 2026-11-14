extends StaticBody2D
class_name BaseModule

## How far past the edge of a module you can stand and still build / fix it.
const ZONE_PAD := 90.0

@export var module_name: String = "Module"
@export var mass_cost: float = 1000.0
@export var power_draw: float = 30.0
@export var can_accept_wires: bool = true
@export var build_time: float = 10.0
@export var fix_time: float = 4.0
@export var proximity_distance: float = 120.0   # kept so old scenes still load; real range is interact_radius()

var is_powered: bool = false
var is_broken: bool = false
var is_constructing: bool = false
var build_progress: float = 0.0
var fix_progress: float = 0.0
var connected_wires: Array = []
var base_visual_color: Color = Color.WHITE
var flash_time: float = 0.0

var progress_bar: ProgressBar = null
var visual_rect: ColorRect = null
var _was_powered := false

func _ready() -> void:
	visual_rect = get_node_or_null("Visual")
	if visual_rect != null:
		base_visual_color = visual_rect.color
		visual_rect.visible = false
	var old_sprite := get_node_or_null("Sprite2D") as CanvasItem
	if old_sprite != null:
		old_sprite.visible = false
	var art := ModuleArt.new()
	art.name = "ModuleArt"
	add_child(art)
	move_child(art, 0)
	proximity_distance = interact_radius()
	if not has_meta("is_ghost"):
		add_to_group("modules")

	if not is_constructing:
		if get_node_or_null("/root/BaseManager") != null:
			if not BaseManager.active_modules.has(self):
				BaseManager.active_modules.append(self)
			BaseManager.calculate_power()

# ---- footprint helpers (everything is measured from the CENTRE of the module) ----
func _half_size() -> Vector2:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		return (col.shape as RectangleShape2D).size * 0.5
	return Vector2(48, 48)

func get_center() -> Vector2:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		return col.global_position
	return global_position

func interact_radius() -> float:
	return _half_size().length() + ZONE_PAD

func get_footprint() -> Rect2:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or not (col.shape is RectangleShape2D):
		return Rect2(global_position - Vector2(48, 48), Vector2(96, 96))
	var h := (col.shape as RectangleShape2D).size * 0.5
	var xf := col.global_transform
	var r := Rect2(xf * Vector2(-h.x, -h.y), Vector2.ZERO)
	r = r.expand(xf * Vector2(h.x, -h.y))
	r = r.expand(xf * Vector2(h.x, h.y))
	r = r.expand(xf * Vector2(-h.x, h.y))
	return r

func _make_bar(col: Color) -> void:
	progress_bar = ProgressBar.new()
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.size = Vector2(100, 20)
	progress_bar.show_percentage = false
	progress_bar.modulate = col
	add_child(progress_bar)
	progress_bar.position = to_local(get_center()) + Vector2(-50, -_half_size().y - 40)

func start_construction() -> void:
	is_constructing = true
	build_progress = 0.0
	can_accept_wires = false
	modulate.a = 0.5
	_make_bar(Color.GREEN)

func _physics_process(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return

	var dist := get_center().distance_to(player.global_position)
	var in_range := dist <= interact_radius()

	if is_constructing:
		if in_range:
			build_progress += (100.0 / build_time) * delta
			if progress_bar != null:
				progress_bar.value = build_progress
				progress_bar.modulate = Color.GREEN
			if build_progress >= 100.0:
				_finish_build()
		elif progress_bar != null:
			progress_bar.modulate = Color.RED

	elif is_broken:
		if Input.is_action_pressed("interact") and in_range:
			fix_progress += (100.0 / fix_time) * delta
			progress_bar.value = fix_progress
			progress_bar.modulate = Color.ORANGE
			if fix_progress >= 100.0:
				_finish_fix()
		else:
			if fix_progress > 0.0:
				fix_progress = 0.0
				progress_bar.value = 0

func _finish_build() -> void:
	is_constructing = false
	can_accept_wires = true
	modulate.a = 1.0

	if progress_bar != null:
		progress_bar.queue_free()
		progress_bar = null

	if get_node_or_null("/root/BaseManager") != null:
		if not BaseManager.active_modules.has(self):
			BaseManager.active_modules.append(self)
		BaseManager.calculate_power()

func break_module() -> void:
	if is_constructing or is_broken: return
	if module_name == "Reactor": return

	is_broken = true
	is_powered = false
	fix_progress = 0.0

	if progress_bar == null:
		_make_bar(Color.RED)

	progress_bar.visible = true
	progress_bar.value = 0
	progress_bar.modulate = Color.RED

	var wires_to_drop: Array = connected_wires.duplicate()
	connected_wires.clear()
	for w in wires_to_drop:
		if is_instance_valid(w):
			if is_instance_valid(w.plugged_receiver) and w.plugged_receiver.has_method("remove_wire"):
				w.plugged_receiver.remove_wire(w)
			if w.has_method("drop"):
				w.drop(w.hand_pos)

	if get_node_or_null("/root/BaseManager") != null:
		BaseManager.calculate_power()
	if get_node_or_null("/root/EventBus") != null:
		EventBus.module_broken.emit(module_name)

func _finish_fix() -> void:
	is_broken = false
	fix_progress = 0.0

	if progress_bar != null:
		progress_bar.visible = false
	modulate = Color(2.0, 2.0, 2.0, 1.0)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.5)

	if get_node_or_null("/root/BaseManager") != null:
		BaseManager.calculate_power()

func has_valid_power_source() -> bool:
	if module_name == "Reactor":
		return not is_broken
	if is_broken or is_constructing:
		return false
	for w in connected_wires:
		if is_instance_valid(w) and "source_module" in w and is_instance_valid(w.source_module):
			var src: BaseModule = w.source_module
			if src.module_name == "Reactor" and not src.is_broken and BaseManager.reactor_energy > 0.0:
				return true
	return false

func accept_wire(wire_node: Node2D) -> void:
	if not can_accept_wires or is_broken or is_constructing:
		return
	if not connected_wires.has(wire_node):
		connected_wires.append(wire_node)
	if get_node_or_null("/root/BaseManager") != null:
		BaseManager.calculate_power()

func remove_wire(wire_node: Node2D) -> void:
	connected_wires.erase(wire_node)
	if connected_wires.is_empty():
		is_powered = false
	if get_node_or_null("/root/BaseManager") != null:
		BaseManager.calculate_power()

func _process(delta: float) -> void:
	if is_constructing: return
	if is_powered and not _was_powered and module_name != "Reactor" and not has_meta("is_ghost"):
		modulate = Color(1.8, 1.8, 2.0, 1.0)
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.5)
	_was_powered = is_powered
	if visual_rect == null: return

	flash_time += delta

	if is_broken:
		var pulse: float = 0.5 + 0.5 * sin(flash_time * 10.0)
		visual_rect.color = base_visual_color.darkened(0.65).lerp(Color(1.0, 0.1, 0.1), pulse)
	elif is_powered or module_name == "Reactor":
		var glow: float = 0.06 * sin(flash_time * 4.0)
		visual_rect.color = base_visual_color.lightened(glow)
	else:
		visual_rect.color = base_visual_color.darkened(0.55)
