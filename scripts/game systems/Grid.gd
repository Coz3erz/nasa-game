extends Node2D

const CELL_SIZE: int = 64
const GRID_WIDTH: int = 10
const GRID_HEIGHT: int = 10

@export var reactor_scene: PackedScene
@export var life_support_scene: PackedScene
@export var thermal_scene: PackedScene

var occupied_cells: Dictionary = {}
var active_scene_to_place: PackedScene
var show_lines: bool = true

func _ready() -> void:
	active_scene_to_place = life_support_scene
	
	if reactor_scene:
		var reactor = reactor_scene.instantiate()
		reactor.position = Vector2(4 * CELL_SIZE, 4 * CELL_SIZE)
		get_parent().call_deferred("add_child", reactor)
		
		var size = reactor.grid_size
		for x in range(size.x):
			for y in range(size.y):
				occupied_cells[Vector2i(4 + x, 4 + y)] = reactor

func _draw() -> void:
	if not show_lines:
		return
	for x in range(GRID_WIDTH):
		for y in range(GRID_HEIGHT):
			var rect = Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			draw_rect(rect, Color(0.15, 0.15, 0.15), false, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			active_scene_to_place = life_support_scene
			print("Selected Life Support")
		elif event.keycode == KEY_2:
			active_scene_to_place = thermal_scene
			print("Selected Thermal")
		elif event.keycode == KEY_ENTER:
			_start_survive_phase()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_phase == GameManager.Phase.BUILD:
			_attempt_placement()

func _start_survive_phase() -> void:
	GameManager.current_phase = GameManager.Phase.SURVIVE
	show_lines = false
	queue_redraw()
	print("SURVIVE PHASE STARTED")
	
	var player = get_parent().get_node_or_null("Player")
	if player:
		player.enable_player()
	else:
		print("ERROR: Could not find Player node.")

func _attempt_placement() -> void:
	var local_mouse_pos: Vector2 = get_local_mouse_position()
	
	var grid_x: int = int(local_mouse_pos.x / CELL_SIZE)
	var grid_y: int = int(local_mouse_pos.y / CELL_SIZE)
	
	if active_scene_to_place == null:
		return
		
	var temp_module = active_scene_to_place.instantiate()
	var size = temp_module.grid_size
	
	if grid_x < 0 or grid_x + size.x > GRID_WIDTH or grid_y < 0 or grid_y + size.y > GRID_HEIGHT:
		temp_module.queue_free()
		print("Cannot place here. Out of bounds.")
		return
		
	for x in range(size.x):
		for y in range(size.y):
			if occupied_cells.has(Vector2i(grid_x + x, grid_y + y)):
				temp_module.queue_free()
				print("Cannot place here. Space is occupied.")
				return
				
	var snap_pos := Vector2(grid_x * CELL_SIZE, grid_y * CELL_SIZE)
	
	temp_module.position = snap_pos
	add_child(temp_module)
	
	for x in range(size.x):
		for y in range(size.y):
			occupied_cells[Vector2i(grid_x + x, grid_y + y)] = temp_module
			
	GameManager.mass_budget -= temp_module.mass_cost
	print("Placed ", temp_module.module_name, "! Remaining Mass: ", GameManager.mass_budget)
