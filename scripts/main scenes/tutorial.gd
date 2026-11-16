# CHANGELOG (2026-11-16): Bottom-right objective for the "buy supplies" step
# only. Other objectives stay top-left. Also fixes a `returna` → `return` typo
# in `_record_event()` that could cause a parse error.
# CHANGELOG (2026-11-16, b): HUD lost its POWER bar (one row shorter), so the
# tutorial's HUD highlight (hud_area) height went from 0.34 to 0.30.
extends Node2D
## The opening briefing. It plays as the real first morning: story, the supply request screen,
## building, wiring, solar stacking, failures and both hazards, then drops into Day 1.
## Every box locks input until the player reads it. Important boxes darken the screen.
@export_group("Spotlight fallback")
@export var enable_tutorial_dim: bool = true
@export var enable_region_spotlights: bool = true
@export var commander_step_offsets: Dictionary = {0: Vector2(0, 1), 1: Vector2(1, 0), 2: Vector2(0, 1), 3: Vector2(-1, 0), 4: Vector2(0, -1), 5: Vector2(1, 0)}
var _shop_step := 0
var _objective_source := ""
var _objective_corner: String = "top_left"
var _pending_events: Array[String] = []

@export_group("Commander")
@export var commander_sprite: Texture2D          ## leave empty to auto-use the captain art
@export var commander_name: String = "COMMANDER"
const shop_top := Rect2(0.50, 0.04, 0.48, 0.10)
const shop_list := Rect2(0.02, 0.14, 0.39, 0.72)
const shop_info := Rect2(0.42, 0.14, 0.56, 0.72)
const shop_buttons := Rect2(0.0, 0.86, 0.5, 0.2)
const hud_area := Rect2(0.025, 0.045, 0.27, 0.25)

const GAME_SCENE := "res://scenes/main scenes/game.tscn"
const GameScript := preload("res://scripts/main scenes/game.gd")
const CAPTAIN_FRAMES := "res://sprites/space station tileset/godot/spriteframes/captain.tres"

signal _ev(kind: String)

var _tracked_module: BaseModule
var _saved_inventory: Dictionary
var _saved_pending: Dictionary
var _saved_phase: int
var _saved_mass: float
var _speaker_texture: Texture2D
var _shop_layer: CanvasLayer
var _shop: Control
var _objective_label: Label
var _done := false
var _cancelled := false
var _dialogue_poll: Timer

func _ready() -> void:
	print("shop_info=", shop_info, " shop_buttons=", shop_buttons, " shop_list=", shop_list)
	GameAudio.set_menu_music(false)
	set_meta("show_hud", false)
	_dialogue_poll = Timer.new()
	_dialogue_poll.wait_time = 0.03
	add_child(_dialogue_poll)
	_dialogue_poll.start()
	_saved_inventory = GameManager.inventory.duplicate(true)
	_saved_pending = GameManager.pending_delivery.duplicate(true)
	_saved_phase = GameManager.current_phase
	_saved_mass = GameManager.mass_budget
	GameManager.current_phase = GameManager.Phase.BUILD
	GameManager.mass_budget = GameManager.budget_for_day(1)
	for key in GameManager.inventory:
		GameManager.inventory[key] = 0
	for key in GameManager.pending_delivery:
		GameManager.pending_delivery[key] = 0
	var player := $Player as Node2D
	$BuildCamera.enabled = false
	player.enable_player()
	_speaker_texture = _find_portrait(player)
	_build_objective_label()
	EventBus.player_moved.connect(func(_p: Node2D) -> void: _record_event("moved"))
	EventBus.module_placed.connect(func(m: BaseModule) -> void: _record_event("placed:" + m.module_name))
	EventBus.module_built.connect(func(m: BaseModule) -> void: _record_event("built:" + m.module_name))
	EventBus.wire_connected.connect(_on_wire_connected)
	_run()

# ------------------------------------------------------------------ plumbing
func _find_portrait(player: Node2D) -> Texture2D:
	if commander_sprite != null:
		return commander_sprite
	if Dialogue.character_sprite != null:
		return Dialogue.character_sprite
	if ResourceLoader.exists(CAPTAIN_FRAMES):
		var sf := load(CAPTAIN_FRAMES) as SpriteFrames
		if sf != null:
			for anim in sf.get_animation_names():
				if sf.get_frame_count(anim) > 0:
					return sf.get_frame_texture(anim, 0)
	var sprite := player.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null and sprite.texture != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = sprite.texture
		var cell := sprite.texture.get_size() / Vector2(sprite.hframes, sprite.vframes)
		atlas.region = Rect2(Vector2(sprite.frame % sprite.hframes, floori(float(sprite.frame) / sprite.hframes)) * cell, cell)
		return atlas
	return null

func _build_objective_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(16, 16)
	var sb := GlassUI.panel(Color(0.03, 0.10, 0.16, 0.9), Color(0.55, 1.0, 0.78), 12, 10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	_objective_label = Label.new()
	_objective_label.add_theme_font_override("font", GameFont.get_font())
	_objective_label.add_theme_font_size_override("font_size", 18)
	_objective_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.9))
	panel.add_child(_objective_label)
	layer.add_child(panel)
	panel.visible = false
	_objective_label.set_meta("panel", panel)

func _objective(text: String, corner: String = "top_left") -> void:
	var panel: Control = _objective_label.get_meta("panel")
	panel.visible = text != ""
	_objective_source = text
	_objective_corner = corner
	_objective_label.text = InputSupport.expand(text)
	panel.reset_size()
	_position_objective_panel(corner)
	call_deferred("_position_objective_panel", corner)

func _position_objective_panel(corner: String) -> void:
	var panel: Control = _objective_label.get_meta("panel")
	if not is_instance_valid(panel) or not panel.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var sz := panel.size
	var margin := 16.0
	match corner:
		"bottom_right":
			panel.position = Vector2(vp.x - sz.x - margin, vp.y - sz.y - margin)
		"bottom_left":
			panel.position = Vector2(margin, vp.y - sz.y - margin)
		"top_right":
			panel.position = Vector2(vp.x - sz.x - margin, margin)
		_:
			panel.position = Vector2(margin, margin)

func _lock(locked: bool) -> void:
	($Player as Node).call("set_input_locked", locked)

func _record_event(kind: String) -> void:
	if kind == "moved" and _pending_events.has(kind):
		return
	_pending_events.append(kind)
	_ev.emit(kind)

func _wait(kind: String) -> void:
	while not _pending_events.has(kind) and not _cancelled:
		await _ev
		if _cancelled:
			return
	if not _cancelled:
		_pending_events.remove_at(_pending_events.find(kind))

func _on_wire_connected(wire: Node2D, receiver: Node2D) -> void:
	var src: Variant = wire.get("source_module")
	var dst := receiver.get_parent()
	if src is BaseModule and dst is BaseModule:
		_record_event("wire:%s>%s" % [(src as BaseModule).module_name, (dst as BaseModule).module_name])

func _say(text: String, dim: bool = false, anchor: Variant = null, spot: Variant = null) -> void:
	if _cancelled:
		return
	if anchor == null:
		anchor = Dialogue.SCREEN if dim else $Player
	_lock(true)
	Dialogue.show_dialogue(text, anchor, commander_name, _speaker_texture, true)
	Dialogue._set_dim(dim and enable_tutorial_dim, spot if enable_region_spotlights else null)
	while Dialogue._line_visible and not _cancelled:
		await _dialogue_poll.timeout
		if _cancelled:
			return
	Dialogue._set_dim(false, null)
	_lock(false)

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size

func _frac(r: Rect2) -> Rect2:
	var v := _vp()
	return Rect2(r.position.x * v.x, r.position.y * v.y, r.size.x * v.x, r.size.y * v.y)

func _give(item: String, count: int) -> void:
	GameManager.inventory[item] = GameManager.inventory.get(item, 0) + count

# ------------------------------------------------------------------ the briefing
func _run() -> void:
	await get_tree().process_frame
	if _cancelled:
		return
	await _chapter_story()
	if _cancelled:
		return
	await _chapter_crew()
	if _cancelled:
		return
	await _chapter_walk()
	if _cancelled:
		return
	await _chapter_supplies()
	if _cancelled:
		return
	await _chapter_build()
	if _cancelled:
		return
	await _chapter_reactor()
	if _cancelled:
		return
	await _chapter_solar()
	if _cancelled:
		return
	await _chapter_bars()
	if _cancelled:
		return
	await _chapter_failures()
	if _cancelled:
		return
	await _chapter_storm()
	if _cancelled:
		return
	await _chapter_flare()
	if _cancelled:
		return
	await _chapter_finish()
	if _cancelled:
		return

func _chapter_story() -> void:
	await _say("Can you hear me? Good. Stay where you are, you're safe now.", true)
	if _cancelled:
		return
	await _say("I'm the commander. I run the Mars teams from our main base, a few thousand kilometers from you.", true)
	if _cancelled:
		return
	await _say("The solar flare that hit your lander knocked out your guidance. You came down in Hellas Planitia, the deepest basin on Mars, about seven kilometers below the surrounding ground.", true)
	if _cancelled:
		return
	await _say("You survived the landing, and this base took less damage than we feared. It still needs a lot of work.", true)
	if _cancelled:
		return
	await _say("Rescue is five days out. Your job is to keep this base alive until then. Power, air, and heat.", true)
	if _cancelled:
		return
	await _say("I'm on Mars too, so there's no delay on this channel. Earth is different. A message to them takes between three and twenty-two minutes each way, so out here we solve our own problems.", true)
	if _cancelled:
		return

func _chapter_crew() -> void:
	await _say("You're not alone. Three of my crew have spent the last few months building outposts across this region. They know this planet.", true)
	if _cancelled:
		return
	await _say("They're hundreds of kilometers away, so they can't walk over. They drive supplies to you in a rover.", true)
	if _cancelled:
		return
	await _say("Every morning you tell them what you need. They load the rover and bring it to your base.", true)
	if _cancelled:
		return
	await _say("A rover can only carry so much weight, and it only makes one trip a day. Whatever isn't on it, you won't have until tomorrow.", true)
	if _cancelled:
		return

func _chapter_walk() -> void:
	await _say("First, get a feel for the base. Move around with {move}.")
	if _cancelled:
		return
	_objective("Walk around  ({move})")
	await _wait("moved")
	if _cancelled:
		return
	await SceneDelay.timer(self, 1.6, false).timeout
	if _cancelled:
		return
	_objective("")

func _chapter_supplies() -> void:
	await _say("Alright, now let me teach you the shop.", true)
	if _cancelled:
		return
	await Transition.fade_to_black(0.5)
	if _cancelled:
		return
	_shop_layer = CanvasLayer.new()
	_shop_layer.layer = 10
	add_child(_shop_layer)
	_shop = GameScript.MarsGearManifest.new()
	_shop.deploy_confirmed.connect(func() -> void: _record_event("sent"))
	_shop_layer.add_child(_shop)
	await get_tree().process_frame
	if _cancelled:
		return
	await Transition.fade_from_black(0.5)
	if _cancelled:
		return
	await _say_shop("This is the supply request. You'll see it every morning, before the rover leaves.", null)
	if _cancelled:
		return
	await _say_shop("Each row is a piece of equipment. Press + to put one on the rover, and - to take one off.", _frac(shop_list))
	if _cancelled:
		return
	await _say_shop("Everything has a weight. This is how much the rover can carry in total. Go over it and the crew can't take it.", _frac(shop_top))
	if _cancelled:
		return
	await _say_shop("Pick a row and this panel explains what it does, along with some of the real science behind it. Worth reading.", _frac(shop_info))
	if _cancelled:
		return
	await _say_shop("When you're ready, press SEND REQUEST and the crew loads up. CLEAR REQUEST empties the list if you change your mind.", _frac(shop_buttons))
	if _cancelled:
		return
	await _say_shop("For now you need one Oxygen Maker and two Solar Panels. Add those, then send the request.", _frac(shop_list))
	if _cancelled:
		return
	_shop.process_mode = Node.PROCESS_MODE_INHERIT
	_objective("Add 1 Oxygen Maker + 2 Solar Panels", "bottom_right")
	await _wait("sent")
	if _cancelled:
		return
	_objective("")
	_shop_layer.queue_free()
	_lock(true)
	var had_ls: int = GameManager.inventory.get("Life Support", 0)
	var had_sp: int = GameManager.inventory.get("Solar Panel", 0)
	for key in GameManager.inventory:
		GameManager.inventory[key] = 0
	_give("Life Support", 1)
	await _say("The rover's here. Your supplies are on the ground.", false)
	if _cancelled:
		return
	if had_ls < 1 or had_sp < 2:
		await _say("You were short on a couple of things, so I've added what you need for this first build.", false)
		if _cancelled:
			return

func _say_shop(text: String, spot: Variant) -> void:
	_shop.process_mode = Node.PROCESS_MODE_DISABLED
	Dialogue.preferred_screen_side = commander_step_offsets.get(_shop_step, Vector2.ZERO)
	_shop_step += 1
	await _say(text, true, Dialogue.SCREEN, spot)
	if _cancelled:
		return
	Dialogue.preferred_screen_side = Vector2.ZERO
	_shop.process_mode = Node.PROCESS_MODE_INHERIT

func _chapter_build() -> void:
	await _say("Press {build_mode} to enter build mode and aim with your mouse, right stick, or touch aim pad. Press {interact} to place the Oxygen Maker. Leave some space around the reactor, it needs clearance.")
	if _cancelled:
		return
	_objective("Place the Oxygen Maker  ({build_mode}, aim, {interact})")
	await _wait("placed:Life Support")
	if _cancelled:
		return
	_tracked_module = null
	for m in BaseManager.active_modules:
		if is_instance_valid(m) and m.module_name == "Life Support":
			_tracked_module = m
	_objective("Stay inside the ring until it's built")
	await _say("Building takes a moment. Stay inside the ring until it finishes, or the work stops.", false, _tracked_module if _tracked_module != null else $Player)
	if _cancelled:
		return
	await _wait("built:Life Support")
	if _cancelled:
		return
	_objective("")
	await _say("Done. See the sockets that appeared on it? That's where cables plug in.", false, _tracked_module)
	if _cancelled:
		return

func _chapter_reactor() -> void:
	var reactor := $Reactor as Node2D
	await _say("This is the reactor. Every machine in the base gets its power from here.", true, reactor, reactor)
	if _cancelled:
		return
	await _say("The reactor doesn't make power on its own. It collects it from solar panels and shares it out. No panels, no power.", true, reactor, reactor)
	if _cancelled:
		return
	await _say("Mars is about one and a half times farther from the Sun than Earth, so sunlight here is less than half as strong. Panels are the only practical option, and we need plenty of them.", true)
	if _cancelled:
		return
	await _say("To connect equipment, walk up to a reactor output and press {interact} to pick up its cable. Carry it to the socket and press {interact} again to plug it in.", false, reactor)
	if _cancelled:
		return
	_objective("Plug the reactor into the Oxygen Maker  ({interact} to grab and connect)")
	await _wait("wire:Reactor>Life Support")
	if _cancelled:
		return
	_objective("")
	await _say("Connected. It won't run yet, because nothing is feeding the reactor. Let's fix that.", false, _tracked_module)
	if _cancelled:
		return

func _chapter_solar() -> void:
	var reactor := $Reactor as Node2D
	_give("Solar Panel", 1)
	await _say("Here's your first Solar Panel. Open build mode and place it near the reactor.")
	if _cancelled:
		return
	_objective("Place the Solar Panel near the reactor")
	await _wait("placed:Solar Panel")
	if _cancelled:
		return
	await _wait("built:Solar Panel")
	if _cancelled:
		return
	_objective("Plug the panel's cable into the reactor")
	await _say("Now plug the panel into the reactor. Pick up the cable on the panel and connect it to the reactor.", false, reactor)
	if _cancelled:
		return
	await _wait("wire:Solar Panel>Reactor")
	if _cancelled:
		return
	_objective("")
	await _say("One panel gives the reactor 50 kilowatts of power. Every machine uses some of that. The Oxygen Maker takes 30, the heater 20, the storm shield 40, and the comms dish 15.", true, reactor, reactor)
	if _cancelled:
		return
	await _say("So one panel runs the Oxygen Maker and the heater, and that's all 50. Nothing left over.", true)
	if _cancelled:
		return
	await _say("But panels stack, and they stack fast. Two panels give 100 kilowatts. Three give 200.", true)
	if _cancelled:
		return
	_give("Solar Panel", 1)
	await _say("Here's your second panel. Place it and plug it into the reactor as well.")
	if _cancelled:
		return
	_objective("Place the second panel and plug it into the reactor")
	await _wait("placed:Solar Panel")
	if _cancelled:
		return
	await _wait("built:Solar Panel")
	if _cancelled:
		return
	await _wait("wire:Solar Panel>Reactor")
	if _cancelled:
		return
	_objective("")
	await _say("That's 100 kilowatts now, double what you had. A second panel is almost always worth its weight.", true, reactor, reactor)
	if _cancelled:
		return
	await _say("The reactor also keeps a reserve. The more power your equipment draws, the faster it drains. If it runs empty, everything shuts off, so don't run more than you need.", true)
	if _cancelled:
		return

func _chapter_bars() -> void:
	set_meta("show_hud", true)
	var v := _vp()
	await _say("These bars are what keep you alive. Air, warmth, and health.", true, Dialogue.SCREEN, _frac(hud_area))
	if _cancelled:
		return
	await _say("Air lasts about 48 seconds before your first Oxygen Maker is built, or 16 seconds after it is built but unpowered, on day one. Later days drain faster. The atmosphere here is 95 percent carbon dioxide, so the Oxygen Maker splits it apart with electricity. NASA's MOXIE experiment on the Perseverance rover did exactly that.", true)
	if _cancelled:
		return
	await _say("Warmth drains too. Nights here fall to around minus 60 degrees Celsius. Without the heater running, the base freezes.", true)
	if _cancelled:
		return
	await _say("If air or warmth hits zero, your health starts dropping, and if health hits zero, you're done for the day. Health never recovers on its own. Use a med kit to heal.", true)
	if _cancelled:
		return

func _chapter_failures() -> void:
	await _say("Now the part nobody likes. Mars dust is finer than flour, and it works its way into everything. Your equipment will act up now and then.", true)
	if _cancelled:
		return
	await _say("That's called a failure. A failed machine stops completely until it's repaired.", true)
	if _cancelled:
		return
	await _say("A bar shows up above it. Stand close and hold {interact} until the bar fills. It takes about four seconds.", false)
	if _cancelled:
		return
	await _say("Failures get more frequent every day, so keep an eye on your equipment.", true)
	if _cancelled:
		return
	await _say("There is one way to prevent them. Plug a machine directly into a solar panel, skipping the reactor, and it can never fail. It also uses no reactor power.", true)
	if _cancelled:
		return
	await _say("The catch is that the panel then feeds only that machine. Use it on whatever you can't afford to lose, like the Oxygen Maker.", true)
	if _cancelled:
		return

func _chapter_storm() -> void:
	await _say("Two hazards can hit this base. The first is a dust storm.", true)
	if _cancelled:
		return
	await _say("You can't stop one and you can't avoid one. When it hits, dust disconnects every cable, even direct solar links. You must reconnect them manually.", true)
	if _cancelled:
		return
	await _say("It also coats your solar panels. Their output drops by half the moment the storm starts, so you lose half your power.", true)
	if _cancelled:
		return
	await _say("And the storm itself hurts. You take 25 damage.", true)
	if _cancelled:
		return
	await _say("Here's what one looks like.", false)
	if _cancelled:
		return
	_lock(true)
	await Hazards.demo("storm")
	if _cancelled:
		return
	_lock(false)
	await _say("A real one lasts about thirty seconds. They can also cover the whole planet. A dust storm in 2018 buried the Opportunity rover's panels and ended its mission.", true)
	if _cancelled:
		return
	await _say("When one hits, check your health and reconnect your cables. Solar output stays halved for the whole storm; it does not stack every frame.", true)
	if _cancelled:
		return

func _chapter_flare() -> void:
	await _say("The second hazard is a solar flare. It's what brought your lander down.", true)
	if _cancelled:
		return
	await _say("Mars has no global magnetic field and a very thin atmosphere, so the charged particles from a flare reach the ground almost unblocked.", true)
	if _cancelled:
		return
	await _say("A flare does 15 damage, and every machine that's running fails.", true)
	if _cancelled:
		return
	await _say("The first defense is the storm shield. If it's powered when the flare hits, you take nothing and nothing fails. But it draws 40 kilowatts the whole time it runs.", true)
	if _cancelled:
		return
	await _say("The second is cheaper. Unplug your machines before the flare arrives. Equipment that's not connected to power can't be damaged by the surge.", true)
	if _cancelled:
		return
	await _say("How do you know a flare is coming? That's what the comms dish is for. While it's powered, it picks up a warning 15 seconds before impact.", true)
	if _cancelled:
		return
	await _say("Fifteen seconds isn't long. How well it works depends on where you're standing, how fast you move, and some luck.", true)
	if _cancelled:
		return
	await _say("Here's what a flare looks like.", false)
	if _cancelled:
		return
	_lock(true)
	await Hazards.demo("flare")
	if _cancelled:
		return
	_lock(false)
	await _say("No comms, no shield, and nothing unplugged? Then you take the full hit. Decide your plan before the rover leaves each morning.", true)
	if _cancelled:
		return

func _chapter_finish() -> void:
	await _say("One last item. Med kits. Use one anywhere on Mars to restore 45 health ({use_medkit}). They weigh almost nothing, so take a couple every day.", false)
	if _cancelled:
		return
	await _say("That's the essentials. Panels first, and stack them. Keep air and warmth running. Repair fast. Plan for hazards before the rover leaves.", true)
	if _cancelled:
		return
	await _say("Five days. I'll be on this channel the whole time. Good luck out there.", true)
	if _cancelled:
		return
	_done = true
	SaveFlags.set_flag("tutorial_done")
	_lock(true)
	_release_touch_fingers()
	Transition.change_scene(GAME_SCENE)

func _release_touch_fingers() -> void:
	var tc := get_tree().root.get_node_or_null("TouchControlsAutoload")
	if tc != null and tc.has_method("_release_all"):
		tc.call("_release_all")

func _exit_tree() -> void:
	_cancelled = true
	if is_instance_valid(_dialogue_poll):
		_dialogue_poll.timeout.emit()
	_ev.emit("__cancelled__")
	Dialogue.hide_dialogue()
	Hazards.clear()
	GameManager.inventory = _saved_inventory
	GameManager.pending_delivery = _saved_pending
	GameManager.current_phase = _saved_phase
	GameManager.mass_budget = _saved_mass
	for i in range(BaseManager.active_modules.size() - 1, -1, -1):
		var module: Node = BaseManager.active_modules[i]
		if not is_instance_valid(module) or is_ancestor_of(module):
			BaseManager.active_modules.remove_at(i)
	BaseManager.calculate_power()

func _process(_delta: float) -> void:
	if is_instance_valid(_objective_label) and _objective_source != "":
		_objective_label.text = InputSupport.expand(_objective_source)
		if _objective_corner != "top_left":
			_position_objective_panel(_objective_corner)
