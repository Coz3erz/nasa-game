extends CanvasLayer

var overlay: ColorRect
var transitioning: bool = false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate.a = 0.0
	add_child(overlay)

func fade_to_black(duration: float = 0.8) -> void:
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, duration)
	await tw.finished

func fade_from_black(duration: float = 0.8) -> void:
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, duration)
	await tw.finished
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func change_scene(path: String, duration: float = 0.8) -> void:
	if transitioning:
		return
	transitioning = true
	await fade_to_black(duration)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await fade_from_black(duration)
	transitioning = false
