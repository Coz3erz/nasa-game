extends Node

const SAVE_PATH := "user://settings.cfg"

var dirty: bool = false

var default_settings: Dictionary = {
	"particles": true,
	"glow": true,
	"screen_shake": true,
	"low_detail": false,
	"master_volume": 100,
	"sfx_volume": 100,
	"music_volume": 100,
	"resolution": "1920x1080",
	"vsync": true,
	"max_fps": 0,
	"msaa": "Off",
	"window_mode": "Windowed",
	"brightness": 100
}

var settings: Dictionary = {}
var _default_input_map: Dictionary = {}

var _brightness_layer: CanvasLayer
var _brightness_rect: ColorRect
var _brightness_mat: ShaderMaterial

const BRIGHTNESS_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float brightness = 1.0;

void fragment() {
	vec4 col = texture(screen_tex, SCREEN_UV);
	vec3 adj = col.rgb * brightness;
	if (brightness > 1.0) {
		adj += vec3((brightness - 1.0) * 0.12);
	}
	COLOR = vec4(clamp(adj, 0.0, 1.0), col.a);
}
"""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_cache_default_inputs()
	_setup_brightness_overlay()
	if InputSupport.has_touch():
		default_settings["low_detail"] = true
	settings = default_settings.duplicate(true)
	load_settings()
	# Auto-cap FPS on native mobile — uncapped drains battery and triggers
	# thermal throttling, which paradoxically makes the game stutter MORE.
	if InputSupport.is_native_mobile() and int(settings.get("max_fps", 0)) == 0:
		settings["max_fps"] = 60
	load_player_input_map()
	apply_settings()
	get_tree().node_added.connect(_on_node_added)

func _ensure_audio_buses() -> void:
	for bus_name in ["SFX", "Music", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "SFX" if bus_name == "Ambient" else "Master")

func _setup_brightness_overlay() -> void:
	_brightness_layer = CanvasLayer.new()
	_brightness_layer.layer = 120
	add_child(_brightness_layer)

	_brightness_rect = ColorRect.new()
	_brightness_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_brightness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BRIGHTNESS_SHADER
	_brightness_mat = ShaderMaterial.new()
	_brightness_mat.shader = sh
	_brightness_rect.material = _brightness_mat
	_brightness_layer.add_child(_brightness_rect)

func _cache_default_inputs() -> void:
	for action in InputMap.get_actions():
		var act_str := str(action)
		if act_str.begins_with("ui_") and act_str not in ["ui_left", "ui_right", "ui_up", "ui_down"]:
			continue
		_default_input_map[act_str] = InputMap.action_get_events(action).duplicate()

func _on_node_added(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		var p: Node = node
		if p.bus == &"Master":
			var nm := p.name.to_lower()
			if nm.contains("music") or nm.contains("ambient") or nm.contains("audio_player"):
				p.bus = &"Music"
			else:
				p.bus = &"SFX"
	elif node is CPUParticles2D or node is GPUParticles2D:
		_apply_particle(node, bool(settings.get("particles", true)))
	elif node is WorldEnvironment:
		var we := node as WorldEnvironment
		if we.environment != null:
			we.environment.glow_enabled = bool(settings.get("glow", true))

func apply_settings() -> void:
	_apply_audio()
	_apply_display()
	_apply_graphics_and_gameplay()

func _apply_audio() -> void:
	_set_bus_percent("Master", float(settings.get("master_volume", 100)))
	_set_bus_percent("SFX", float(settings.get("sfx_volume", 100)))
	_set_bus_percent("Music", float(settings.get("music_volume", 100)))

func _set_bus_percent(bus_name: String, pct: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped := clampf(pct, 0.0, 100.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.5)
	if clamped > 0.5:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamped / 100.0))

func _apply_display() -> void:
	var b_val: float = clampf(float(settings.get("brightness", 100)) / 100.0, 0.15, 2.0)
	if _brightness_mat != null:
		_brightness_mat.set_shader_parameter("brightness", b_val)
		_brightness_rect.visible = not is_equal_approx(b_val, 1.0)

	if InputSupport.desktop_window_controls():
		var vsync_on: bool = bool(settings.get("vsync", true))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = int(settings.get("max_fps", 0))
		var w_mode: String = str(settings.get("window_mode", "Windowed"))
		var fullscreen := w_mode in ["Fullscreen", "Borderless"]
		var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target_mode:
			DisplayServer.window_set_mode(target_mode)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, w_mode == "Borderless")
	else:
		# Web/mobile: no window control, but FPS cap still applies.
		Engine.max_fps = int(settings.get("max_fps", 0))

	var msaa_str: String = str(settings.get("msaa", "Off"))
	var vp := get_viewport()
	if vp != null:
		match msaa_str:
			"2x": vp.msaa_2d = Viewport.MSAA_2X
			"4x": vp.msaa_2d = Viewport.MSAA_4X
			"8x": vp.msaa_2d = Viewport.MSAA_8X
			_: vp.msaa_2d = Viewport.MSAA_DISABLED

func _apply_graphics_and_gameplay() -> void:
	var ld := bool(settings.get("low_detail", false))
	var particles_on := bool(settings.get("particles", true))
	var glow_on := bool(settings.get("glow", true))
	# Low detail hard-overrides the two most expensive visual features.
	# This is what actually fixes mobile framerate.
	if ld:
		glow_on = false
		particles_on = false
	var root := get_tree().root
	if root != null:
		_apply_recursive(root, particles_on, glow_on)

func _apply_recursive(node: Node, particles_on: bool, glow_on: bool) -> void:
	# Guard: node may be freed mid-walk (options slider drag → apply_settings
	# fires many times per second during scene teardown).
	if node == null:
		return
	if not is_instance_valid(node):
		return
	if not node.is_inside_tree():
		return

	# Audio players — apply bus volume from settings, guarded
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		var bus_name := ""
		if node.get("bus") != null:
			bus_name = str(node.get("bus"))
		if bus_name == "SFX" or bus_name == "Ambient":
			var v := float(settings.get("sfx_volume", 100)) / 100.0
			if node.get("volume_db") != null:
				node.set("volume_db", linear_to_db(maxf(v, 0.0001)))
		elif bus_name == "Music":
			var v := float(settings.get("music_volume", 100)) / 100.0
			if node.get("volume_db") != null:
				node.set("volume_db", linear_to_db(maxf(v, 0.0001)))

	# Particles — visibility from the "particles" setting
	if node is CPUParticles2D or node is GPUParticles2D:
		_apply_particle(node, particles_on)

	# WorldEnvironment — glow toggle + full zero-out when off
	if node is WorldEnvironment:
		var we := node as WorldEnvironment
		if we.environment != null:
			we.environment.glow_enabled = glow_on
			if not glow_on:
				we.environment.glow_intensity = 0.0
				we.environment.glow_bloom = 0.0

	# Recurse — snapshot children so a child freed mid-iteration can't null-deref
	var children := node.get_children()
	for i in range(children.size()):
		var child = children[i]
		if child != null and is_instance_valid(child):
			_apply_recursive(child, particles_on, glow_on)

func reset_settings_to_default() -> void:
	settings = default_settings.duplicate(true)
	apply_settings()
	dirty = false

func reset_inputs_to_default() -> void:
	for act_str in _default_input_map.keys():
		if InputMap.has_action(act_str):
			InputMap.action_erase_events(act_str)
			for ev in _default_input_map[act_str]:
				InputMap.action_add_event(act_str, ev)
	dirty = false

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SAVE_PATH)
	dirty = false

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.has_section("settings"):
		for k in default_settings.keys():
			if cfg.has_section_key("settings", k):
				settings[k] = cfg.get_value("settings", k, default_settings[k])
	dirty = false

func save_player_input_map() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	if cfg.has_section("inputs"):
		cfg.erase_section("inputs")
	for action in InputMap.get_actions():
		var act_str := str(action)
		if act_str.begins_with("ui_") and act_str not in ["ui_left", "ui_right", "ui_up", "ui_down"]:
			continue
		var serialized: Array = []
		for ev in InputMap.action_get_events(action):
			serialized.append(var_to_str(ev))
		cfg.set_value("inputs", act_str, serialized)
	cfg.save(SAVE_PATH)

func load_player_input_map() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section("inputs"):
		return
	for act_str in cfg.get_section_keys("inputs"):
		if not InputMap.has_action(act_str):
			InputMap.add_action(act_str)
		InputMap.action_erase_events(act_str)
		var arr: Array = cfg.get_value("inputs", act_str, [])
		for s in arr:
			var ev = str_to_var(str(s))
			if ev is InputEvent:
				InputMap.action_add_event(act_str, ev)

func _apply_particle(particle: Node, enabled: bool) -> void:
	particle.visible = enabled
	if not enabled:
		if not particle.has_meta("settings_emitting"):
			particle.set_meta("settings_emitting", particle.emitting)
		particle.emitting = false
	elif particle.has_meta("settings_emitting"):
		particle.emitting = bool(particle.get_meta("settings_emitting"))
		particle.remove_meta("settings_emitting")
