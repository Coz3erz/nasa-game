extends Node2D

@onready var build_camera: Camera2D = $BuildCamera
@onready var player: CharacterBody2D = $Player
@onready var rover: Node2D = $Rover

var shop_layer: CanvasLayer
var mass_label: Label
var count_labels: Dictionary = {}

func _ready() -> void:
	GameManager.current_phase = GameManager.Phase.BUILD
	build_camera.enabled = true
	if rover != null:
		rover.visible = false
	_build_shop_ui()

func _build_shop_ui() -> void:
	shop_layer = CanvasLayer.new()
	shop_layer.layer = 10
	add_child(shop_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_layer.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	shop_layer.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_vbox)

	var header := HBoxContainer.new()
	main_vbox.add_child(header)

	var title := Label.new()
	title.text = "ARES PAYLOAD MANIFEST // SOL " + str(GameManager.current_sol)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	mass_label = Label.new()
	mass_label.add_theme_font_size_override("font_size", 28)
	mass_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	header.add_child(mass_label)

	var cards_grid := HBoxContainer.new()
	cards_grid.add_theme_constant_override("separation", 24)
	cards_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(cards_grid)

	for item in GameManager.catalog:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards_grid.add_child(card)

		var card_margin := MarginContainer.new()
		card_margin.add_theme_constant_override("margin_left", 20)
		card_margin.add_theme_constant_override("margin_right", 20)
		card_margin.add_theme_constant_override("margin_top", 20)
		card_margin.add_theme_constant_override("margin_bottom", 20)
		card.add_child(card_margin)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 12)
		card_margin.add_child(vbox)

		var name_lbl := Label.new()
		name_lbl.text = item["id"].to_upper()
		name_lbl.add_theme_font_size_override("font_size", 24)
		name_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
		vbox.add_child(name_lbl)

		var stats_lbl := Label.new()
		stats_lbl.text = "MASS: %d kg   |   POWER DRAW: %d kW" % [int(item["mass"]), int(item["power"])]
		stats_lbl.add_theme_font_size_override("font_size", 16)
		stats_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		vbox.add_child(stats_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = item["desc"]
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		vbox.add_child(desc_lbl)

		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 12)
		vbox.add_child(btn_row)

		var minus_btn := Button.new()
		minus_btn.text = " - "
		minus_btn.custom_minimum_size = Vector2(48, 44)
		minus_btn.pressed.connect(_on_refund_item.bind(item))
		btn_row.add_child(minus_btn)

		var qty_lbl := Label.new()
		qty_lbl.text = "MANIFEST: 0"
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qty_lbl.add_theme_font_size_override("font_size", 20)
		btn_row.add_child(qty_lbl)
		count_labels[item["id"]] = qty_lbl

		var plus_btn := Button.new()
		plus_btn.text = " + BUY "
		plus_btn.custom_minimum_size = Vector2(90, 44)
		plus_btn.pressed.connect(_on_buy_item.bind(item))
		btn_row.add_child(plus_btn)

	var launch_btn := Button.new()
	launch_btn.text = "CONFIRM MANIFEST & DEPLOY ROVER >>"
	launch_btn.custom_minimum_size = Vector2(0, 64)
	launch_btn.add_theme_font_size_override("font_size", 24)
	launch_btn.pressed.connect(_on_confirm_delivery)
	main_vbox.add_child(launch_btn)

	_refresh_shop_ui()

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
	mass_label.text = "REMAINING MASS BUDGET: %d kg" % int(GameManager.mass_budget)
	for item_id in count_labels.keys():
		count_labels[item_id].text = "MANIFEST: %d" % GameManager.get_item_count(item_id)

func _on_confirm_delivery() -> void:
	if shop_layer != null:
		shop_layer.queue_free()
		shop_layer = null
	_start_rover_transition()

func _start_rover_transition() -> void:
	GameManager.current_phase = GameManager.Phase.ROVER

	if rover != null:
		rover.visible = true
		rover.position = Vector2(1100, 560)
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(rover, "position", Vector2(420, 560), 2.2)
		await tw.finished
		await get_tree().create_timer(0.8).timeout

	build_camera.enabled = false
	if player != null and player.has_method("enable_player"):
		player.enable_player()

	GameManager.current_phase = GameManager.Phase.SURVIVE

	if rover != null:
		var tw_out := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw_out.tween_property(rover, "position", Vector2(1200, 560), 2.0)
		await tw_out.finished
		rover.visible = false
