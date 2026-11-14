extends Node2D

@onready var build_camera: Camera2D = $BuildCamera
@onready var player: CharacterBody2D = $Player
@onready var rover: Node2D = $Rover

const CARD_W := 250.0
const GAP := 14

var shop_layer: CanvasLayer
var mass_label: Label
var count_labels: Dictionary = {}
var plus_buttons: Dictionary = {}
var minus_buttons: Dictionary = {}
var scroll: ScrollContainer
var grid: GridContainer
var scroll_hint: Label

func _ready() -> void:
	GameManager.current_phase = GameManager.Phase.BUILD
	build_camera.enabled = true
	if rover != null:
		rover.visible = false
	_build_shop_ui()
	get_viewport().size_changed.connect(_fit_columns)

func _process(_delta: float) -> void:
	if scroll == null or not is_instance_valid(scroll) or scroll_hint == null:
		return
	var bar := scroll.get_v_scroll_bar()
	scroll_hint.visible = bar.max_value - bar.page > float(scroll.scroll_vertical) + 6.0

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _card_style(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.13, 0.16, 0.30, 1.0)
	s.border_color = accent
	s.set_border_width_all(3)
	s.set_corner_radius_all(16)
	return s

func _build_shop_ui() -> void:
	shop_layer = CanvasLayer.new()
	shop_layer.layer = 10
	add_child(shop_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.16, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_layer.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	shop_layer.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# --- top bar: title + how much weight is left (always visible) ---
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _label("Pick your gear", 30, Color(1.0, 0.92, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	mass_label = _label("", 22, Color(1.0, 0.85, 0.4))
	header.add_child(mass_label)

	# --- middle: cards inside a scroll area ---
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)
	scroll.resized.connect(_fit_columns)

	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	scroll.add_child(grid)

	for item in GameManager.catalog:
		_make_card(item)

	scroll_hint = _label("Scroll down for more", 16, Color(0.8, 0.9, 1.0, 0.8))
	scroll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll_hint.visible = false
	root.add_child(scroll_hint)

	# --- bottom: big go button (always visible) ---
	var go := Button.new()
	go.text = "Let's go!"
	go.custom_minimum_size = Vector2(0, 56)
	go.add_theme_font_size_override("font_size", 26)
	go.set_meta("polish_primary", true)
	go.pressed.connect(_on_confirm_delivery)
	root.add_child(go)

	_refresh_shop_ui()
	_fit_columns.call_deferred()

func _make_card(item: Dictionary) -> void:
	var accent: Color = item.get("color", Color(0.4, 0.85, 1.0))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(accent))
	grid.add_child(card)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pad.add_child(vb)

	vb.add_child(_label(str(item["id"]), 24, accent))

	var stats := "Weighs %d kg" % int(item["mass"])
	if float(item["power"]) > 0.0:
		stats += "  -  needs %d power" % int(item["power"])
	else:
		stats += "  -  needs no power"
	vb.add_child(_label(stats, 15, Color(0.82, 0.86, 0.95)))

	var desc := _label(str(item["desc"]), 17, Color(1, 1, 1))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(desc)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(52, 44)
	minus_btn.add_theme_font_size_override("font_size", 24)
	minus_btn.pressed.connect(_on_refund_item.bind(item))
	row.add_child(minus_btn)
	minus_buttons[item["id"]] = minus_btn

	var qty := _label("0", 24, Color(1, 1, 1))
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(qty)
	count_labels[item["id"]] = qty

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(52, 44)
	plus_btn.add_theme_font_size_override("font_size", 24)
	plus_btn.pressed.connect(_on_buy_item.bind(item))
	row.add_child(plus_btn)
	plus_buttons[item["id"]] = plus_btn

## As many cards per row as fit the window - and the scroll area handles the rest.
func _fit_columns() -> void:
	if grid == null or not is_instance_valid(grid) or scroll == null or not is_instance_valid(scroll):
		return
	var w := scroll.size.x - 12.0
	if w <= 50.0:
		w = get_viewport().get_visible_rect().size.x - 80.0
	grid.columns = maxi(1, int(w / (CARD_W + GAP)))

func _on_buy_item(item: Dictionary) -> void:
	var cost: float = item["mass"]
	if GameManager.mass_budget >= cost:
		GameManager.mass_budget -= cost
		GameManager.add_to_inventory(item["id"])
		_refresh_shop_ui()

func _on_refund_item(item: Dictionary) -> void:
	var item_id: String = item["id"]
	if GameManager.remove_from_inventory(item_id):
		GameManager.mass_budget += item["mass"]
		_refresh_shop_ui()

func _refresh_shop_ui() -> void:
	mass_label.text = "Weight left: %d kg" % int(GameManager.mass_budget)
	for item in GameManager.catalog:
		var id: String = item["id"]
		count_labels[id].text = "x%d" % GameManager.get_item_count(id)
		(plus_buttons[id] as Button).disabled = GameManager.mass_budget < float(item["mass"])
		(minus_buttons[id] as Button).disabled = GameManager.get_item_count(id) <= 0

func _on_confirm_delivery() -> void:
	if shop_layer != null:
		shop_layer.queue_free()
		shop_layer = null
	scroll = null
	scroll_hint = null
	_start_rover_transition()

func _start_rover_transition() -> void:
	GameManager.current_phase = GameManager.Phase.ROVER

	if rover != null:
		rover.visible = true
		rover.position = Vector2(1100, 560)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(rover, "position", Vector2(420, 560), 3.2)
		await tw.finished
		await get_tree().create_timer(1.2).timeout

	build_camera.enabled = false
	if player != null and player.has_method("enable_player"):
		player.enable_player()

	GameManager.current_phase = GameManager.Phase.SURVIVE

	if rover != null:
		var tw_out := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw_out.tween_property(rover, "position", Vector2(1200, 560), 2.8)
		await tw_out.finished
		rover.visible = false
