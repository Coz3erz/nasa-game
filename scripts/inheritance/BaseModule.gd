# CHANGELOG (2026-11-15): Use transformed collision/art centre for build exclusion, interaction and tutorial spotlight.
extends StaticBody2D
class_name BaseModule

const ZONE_PAD: float = 110.0

@export var module_name: String = "Module"
@export var mass_cost: float = 1000.0
@export var power_draw: float = 30.0
@export var can_accept_wires: bool = true
@export var build_time: float = 10.0
@export var fix_time: float = 4.0

var is_powered: bool = false
var is_broken: bool = false
var is_constructing: bool = false
var build_progress: float = 0.0
var fix_progress: float = 0.0
var progress_bar: ProgressBar = null

var connected_wires: Array = []
var base_visual_color: Color = Color.WHITE
var flash_time: float = 0.0
var _spark_timer: float = 0.0
var _repair_bar: Node2D = null

@onready var visual_rect: ColorRect = get_node_or_null("Visual")

func _ready() -> void:
	var old_sprite := get_node_or_null("Sprite2D") as CanvasItem
	if old_sprite != null:
		old_sprite.visible = false
	if visual_rect != null:
		visual_rect.visible = false
	var art := ModuleArt.new()
	art.name = "ModuleArt"
	add_child(art)
	move_child(art, 0)
	if visual_rect != null:
		base_visual_color = visual_rect.color
	if has_meta("is_ghost") and bool(get_meta("is_ghost")):
		return
	add_to_group("modules")
	face_reactor.call_deferred()
	if not is_constructing and get_node_or_null("/root/BaseManager") != null:
		if not BaseManager.active_modules.has(self):
			BaseManager.active_modules.append(self)
		BaseManager.calculate_power()
	visible = true
	_update_visual_state(0.0)

func get_center() -> Vector2:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		return to_global(col.position)
	return global_position

func get_half_size() -> Vector2:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		return (col.shape as RectangleShape2D).size * 0.5
	return Vector2(64, 64)

func get_footprint() -> Rect2:
	var half := get_half_size()
	return Rect2(get_center() - half, half * 2.0)

func interact_radius() -> float:
	return get_half_size().length() + ZONE_PAD

func start_construction() -> void:
	is_constructing = true
	visible = true   # stays visible: ModuleArt draws the blueprint scaffold while building
	is_powered = false
	build_progress = 0.0
	if visual_rect != null:
		visual_rect.modulate.a = 0.4

	if progress_bar == null:
		progress_bar = ProgressBar.new()
		progress_bar.max_value = 100.0
		progress_bar.value = 0.0
		progress_bar.size = Vector2(90, 14)
		progress_bar.position = Vector2(get_half_size().x - 45.0, -24.0)
		add_child(progress_bar)

func _finish_build() -> void:
	is_constructing = false
	visible = true
	build_progress = 100.0
	if visual_rect != null:
		visual_rect.modulate.a = 1.0
	if progress_bar != null:
		progress_bar.queue_free()
		progress_bar = null
	if get_node_or_null("/root/BaseManager") != null:
		if not BaseManager.active_modules.has(self):
			BaseManager.active_modules.append(self)
		BaseManager.calculate_power()
	EventBus.module_built.emit(self)

func _process(delta: float) -> void:
	if has_meta("is_ghost") and bool(get_meta("is_ghost")):
		return

	_update_visual_state(delta)

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if is_constructing:
		if player != null and get_center().distance_to(player.global_position) <= interact_radius():
			build_progress = minf(100.0, build_progress + (100.0 / maxf(build_time, 0.1)) * delta)
			if progress_bar != null:
				progress_bar.value = build_progress
			if build_progress >= 100.0:
				_finish_build()
		return

	if is_broken:
		_tick_sparks(delta)
		if _repair_bar == null or not is_instance_valid(_repair_bar):
			_repair_bar = RepairBar.new()
			_repair_bar.set("host", self)
			add_child(_repair_bar)
	if is_broken and player != null:
		var in_reach := get_center().distance_to(player.global_position) <= interact_radius()
		var holding_e := Input.is_action_pressed("interact") or Input.is_physical_key_pressed(KEY_E)
		if in_reach and holding_e:
			fix_progress = minf(100.0, fix_progress + (100.0 / maxf(fix_time, 0.1)) * delta)
			if fix_progress >= 100.0:
				repair_module()
		else:
			fix_progress = maxf(0.0, fix_progress - 40.0 * delta)

func get_connected_solar_count() -> int:
	if is_broken or is_constructing:
		return 0
	var solar_panels: Array[BaseModule] = []
	for w in connected_wires:
		if is_instance_valid(w) and "source_module" in w and is_instance_valid(w.source_module):
			var src: BaseModule = w.source_module
			if src.module_name == "Solar Panel" and not src.is_broken and not src.is_constructing:
				if not solar_panels.has(src):
					solar_panels.append(src)
	return solar_panels.size()

func is_fed_by_solar() -> bool:
	return get_connected_solar_count() > 0

func is_fed_by_reactor() -> bool:
	if is_broken or is_constructing:
		return false
	for w in connected_wires:
		if is_instance_valid(w) and "source_module" in w and is_instance_valid(w.source_module):
			var src: BaseModule = w.source_module
			if src.module_name == "Reactor" and src.is_powered and not src.is_broken and not src.is_constructing:
				return true
	return false

func has_failure_immunity() -> bool:
	if module_name == "Reactor" or module_name == "Solar Panel":
		return true
	return is_fed_by_solar()

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

func break_module() -> void:
	if has_failure_immunity() or is_broken or is_constructing:
		return
	is_broken = true
	is_powered = false
	fix_progress = 0.0

	if get_node_or_null("/root/BaseManager") != null:
		BaseManager.calculate_power()
	if get_node_or_null("/root/EventBus") != null:
		EventBus.module_broken.emit(module_name)

func repair_module() -> void:
	if not is_broken:
		return
	is_broken = false
	fix_progress = 0.0
	if get_node_or_null("/root/BaseManager") != null:
		BaseManager.calculate_power()

func _update_visual_state(delta: float) -> void:
	if visual_rect == null:
		return
	flash_time += delta
	if is_broken:
		var pulse: float = 0.5 + 0.5 * sin(flash_time * 10.0)
		visual_rect.color = base_visual_color.darkened(0.65).lerp(Color(1.0, 0.1, 0.1), pulse)
	elif is_powered:
		var glow: float = 0.06 * sin(flash_time * 4.0)
		visual_rect.color = base_visual_color.lightened(glow)
	else:
		visual_rect.color = base_visual_color.darkened(0.55)

func face_reactor() -> void:
	if module_name == "Reactor":
		return
	var reactor: BaseModule = null
	for m in get_tree().get_nodes_in_group("modules"):
		if m is BaseModule and (m as BaseModule).module_name == "Reactor":
			reactor = m as BaseModule
			break
	if reactor == null:
		return
	var d := reactor.get_center() - get_center()
	var s := 0
	if absf(d.x) > absf(d.y):
		s = 0 if d.x > 0.0 else 2
	else:
		s = 1 if d.y > 0.0 else 3
	var dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	var dir: Vector2 = dirs[s]
	var half := get_half_size()
	var edge := half.x if dir.x != 0.0 else half.y
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var ctr := col.position if col != null else half
	var target_rot := float(s) * PI * 0.5
	if module_name == "Solar Panel":
		var art := get_node_or_null("ModuleArt") as Node2D
		if art != null:
			# Rotate the art about its center; preserve its original collision footprint.
			art.rotation = target_rot
			art.scale = Vector2.ONE if s % 2 == 0 else Vector2(half.y / half.x, half.x / half.y)
			art.position = ctr - art.transform.basis_xform(ctr)
	# Solar outputs use the same edge-facing rule as module receivers.
	for c in get_children():
		if c is WireReceiver or (module_name == "Solar Panel" and c.has_method("spawn_wire")):
			var r := c as Node2D
			var rot := r.rotation + angle_difference(r.rotation, target_rot)
			var tw := create_tween().set_parallel(true)
			tw.tween_property(r, "position", ctr + dir * edge, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(r, "rotation", rot, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Real sparks: little bright particles that fly OUT of the module, arc and fall.
func _tick_sparks(delta: float) -> void:
	if not GameSettings.particles_enabled():
		return
	_spark_timer -= delta
	if _spark_timer > 0.0:
		return
	_spark_timer = randf_range(0.25, 0.9)
	var fp := get_footprint()
	var pos := Vector2(randf_range(fp.position.x, fp.end.x), randf_range(fp.position.y, fp.end.y))
	var big := randf() < 0.25
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 22 if big else 10
	p.lifetime = 0.8
	p.local_coords = false
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 380.0 if big else 260.0
	p.gravity = Vector2(0, 700)
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.11
	p.color = Color(3.0, 2.0, 0.7, 1.0)
	p.z_index = 80
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	p.color_ramp = g
	var tex := GradientTexture2D.new()
	var tg := Gradient.new()
	tg.set_color(0, Color(1, 1, 1, 1))
	tg.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = tg
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	p.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	get_parent().add_child(p)
	p.global_position = pos
	p.emitting = true
	SceneDelay.timer(self, 1.4).timeout.connect(p.queue_free)

## Progress bar above a broken module (fills while you hold E).
class RepairBar extends Node2D:
	var host: BaseModule
	var shown := 0.0
	var vis := 0.0
	var t := 0.0
	func _ready() -> void:
		top_level = true
		z_as_relative = false
		z_index = 250
	func _process(d: float) -> void:
		if host == null or not is_instance_valid(host) or not host.is_broken:
			queue_free()
			return
		t += d
		shown = lerpf(shown, host.fix_progress / 100.0, 1.0 - exp(-14.0 * d))
		vis = lerpf(vis, 1.0, 1.0 - exp(-8.0 * d))
		global_position = host.get_center() + Vector2(0.0, -host.get_half_size().length() - 34.0)
		global_rotation = 0.0
		queue_redraw()
	func _draw() -> void:
		if host == null or not is_instance_valid(host):
			return
		var w := 150.0
		var h := 16.0
		var a := vis
		var holding := host.fix_progress > 0.5
		draw_rect(Rect2(-w * 0.5 - 4.0, -h * 0.5 - 4.0, w + 8.0, h + 8.0), Color(0.04, 0.05, 0.09, 0.9 * a))
		var col := Color(1.0, 0.45, 0.2).lerp(Color(0.4, 1.0, 0.55), shown)
		draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color(0.15, 0.17, 0.25, a))
		if shown > 0.005:
			draw_rect(Rect2(-w * 0.5, -h * 0.5, w * shown, h), Color(col.r, col.g, col.b, a))
			draw_rect(Rect2(-w * 0.5 + w * shown - 2.0, -h * 0.5, 2.0, h), Color(1, 1, 1, a))
		var f := ThemeDB.fallback_font
		var txt := "Fixing...  %d%%" % int(shown * 100.0) if holding else "Hold E to fix"
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var pulse := 1.0 if holding else 0.65 + 0.35 * sin(t * 6.0)
		draw_string(f, Vector2(-tw * 0.5, -h * 0.5 - 10.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 0.95, 0.8, a * pulse))
