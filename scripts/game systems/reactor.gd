extends BaseModule

## The reactor only takes plugs from Solar Panels.
const ONLY_SOURCE := "Solar Panel"

func _ready() -> void:
	module_name = "Reactor"
	can_accept_wires = true
	is_powered = true
	super._ready()
	for c in get_children():
		if c is WireReceiver:
			var r := c as WireReceiver
			r.accepted_sources = PackedStringArray([ONLY_SOURCE])
			r.capacity = 4

## How many working solar panels are plugged into me.
func solar_count() -> int:
	var n := 0
	for w in connected_wires:
		if is_instance_valid(w) and "source_module" in w and is_instance_valid(w.source_module):
			var s: BaseModule = w.source_module
			if s.module_name == ONLY_SOURCE and not s.is_broken and not s.is_constructing:
				n += 1
	return n

func accept_wire(wire_node: Node2D) -> void:
	var before := connected_wires.size()
	super.accept_wire(wire_node)
	if connected_wires.size() > before:
		_plug_fx()

func _plug_fx() -> void:
	var host := get_parent()
	if host == null:
		return
	modulate = Color(1.8, 2.1, 2.3, 1.0)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.6)
	var lbl := Label.new()
	lbl.text = "+ Sun power!"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 7)
	lbl.top_level = true
	lbl.z_index = 400
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(lbl)
	lbl.global_position = get_center() + Vector2(-70, -110)
	var tw := lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 80.0, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.8)
	tw.chain().tween_callback(lbl.queue_free)
