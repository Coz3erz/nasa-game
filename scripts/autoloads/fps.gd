extends CanvasLayer

var _lbl := Label.new()

func _ready() -> void:
	layer = 100
	add_child(_lbl)
	visible = false

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_F3:
		visible = not visible

func _process(_d: float) -> void:
	if visible:
		_lbl.text = "%d fps" % Engine.get_frames_per_second()
