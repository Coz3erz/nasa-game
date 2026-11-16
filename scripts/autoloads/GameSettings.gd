extends Node

signal quality_changed

const SAVE_PATH := "user://settings.cfg"

var dirty: bool = false

var default_settings: Dictionary = {
	"particles": true,
	"glow": true,
	"screen_shake": true,
	"low_detail": false,
	"ultra_performance": false,
	"mobile_quality": "Auto",
	"baseline_optimizations": true,
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
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
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
	settings = default_settings.duplicate(true)
	load_settings()
	load_player_input_map()
	apply_settings()
	get_tree().node_added.connect(_on_node_added)
	get_tree().tree_changed.connect(invalidate_group_cache)

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
	if node is CPUParticles2D or node is GPUParticles2D or node is WorldEnvironment or node is Light2D:
		# Factories often assign material/environment/emission AFTER add_child().
		_apply_visual_node.call_deferred(node)

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
		_brightness_rect.visible = not ultra_enabled() and not is_equal_approx(b_val, 1.0)

	# The ONLY owner of frame pacing. Quality and device checks never change this.
	Engine.max_fps = maxi(0, int(settings.get("max_fps", 0)))
	var vsync_on: bool = bool(settings.get("vsync", true))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)
	if InputSupport.desktop_window_controls():
		var w_mode: String = str(settings.get("window_mode", "Windowed"))
		var fullscreen := w_mode in ["Fullscreen", "Borderless"]
		var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target_mode:
			DisplayServer.window_set_mode(target_mode)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, w_mode == "Borderless")

	var msaa_str: String = "Off" if reduced_detail() else str(settings.get("msaa", "Off"))
	var vp := get_viewport()
	if vp != null:
		match msaa_str:
			"2x": vp.msaa_2d = Viewport.MSAA_2X
			"4x": vp.msaa_2d = Viewport.MSAA_4X
			"8x": vp.msaa_2d = Viewport.MSAA_8X
			_: vp.msaa_2d = Viewport.MSAA_DISABLED

var _quality_key: Array = []
var _group_cache: Dictionary = {}
var _hdr_preference := false

func baseline_enabled() -> bool:
	return bool(settings.get("baseline_optimizations", true))

func ultra_enabled() -> bool:
	return bool(settings.get("ultra_performance", false))

func reduced_detail() -> bool:
	return ultra_enabled() or bool(settings.get("low_detail", false))

func mobile_quality() -> bool:
	var preference: Variant = settings.get("mobile_quality", "Auto")
	# Accept boolean values from code/integration tools as well as the Options selector.
	if preference is bool:
		return preference or InputSupport.is_mobile_device()
	match str(preference):
		"On": return true
		"Off": return false
	return InputSupport.is_mobile_device()

func particles_enabled() -> bool:
	return bool(settings.get("particles", true)) and not reduced_detail()

func glow_enabled() -> bool:
	return bool(settings.get("glow", true)) and not reduced_detail()

func particle_scale() -> float:
	return 0.25 if mobile_quality() else 1.0

func set_hdr_preference(enabled: bool) -> void:
	_hdr_preference = enabled and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	get_viewport().use_hdr_2d = _hdr_preference and not reduced_detail()

func invalidate_group_cache() -> void:
	_group_cache.clear()

func group_nodes(group: StringName) -> Array[Node]:
	if not baseline_enabled():
		return get_tree().get_nodes_in_group(group)
	if not _group_cache.has(group):
		_group_cache[group] = get_tree().get_nodes_in_group(group)
	return _group_cache[group]

func _apply_graphics_and_gameplay() -> void:
	var key: Array = [reduced_detail(), ultra_enabled(), particles_enabled(), glow_enabled(), mobile_quality(), baseline_enabled()]
	if key == _quality_key:
		return # Audio/brightness/FPS edits do not traverse the scene tree.
	_quality_key = key
	invalidate_group_cache()
	get_viewport().use_hdr_2d = _hdr_preference and not reduced_detail()
	_apply_recursive(get_tree().root)
	quality_changed.emit()

func _apply_recursive(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	_apply_visual_node(node)
	for child in node.get_children():
		_apply_recursive(child)

func _apply_visual_node(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is CPUParticles2D or node is GPUParticles2D:
		_apply_particle(node, particles_enabled())
	elif node is WorldEnvironment:
		var env := (node as WorldEnvironment).environment
		if env == null:
			return
		# Keep the original resource intact: disabling then enabling is lossless.
		if not env.has_meta("crashfall_defaults"):
			var original := {}
			for prop in ["glow_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled", "fog_enabled", "volumetric_fog_enabled", "adjustment_enabled", "tonemap_mode"]:
				original[prop] = env.get(prop)
			env.set_meta("crashfall_defaults", original)
		var defaults: Dictionary = env.get_meta("crashfall_defaults")
		for prop in defaults:
			if prop == "glow_enabled":
				env.set(prop, defaults[prop] and glow_enabled())
			elif ultra_enabled():
				env.set(prop, Environment.TONE_MAPPER_LINEAR if prop == "tonemap_mode" else false)
			else:
				env.set(prop, defaults[prop])
	elif node is Light2D:
		var light := node as Light2D
		if not light.has_meta("quality_shadow"):
			light.set_meta("quality_shadow", light.shadow_enabled)
		light.shadow_enabled = bool(light.get_meta("quality_shadow")) and not reduced_detail() and not mobile_quality()

func reset_settings_to_default() -> void:
	settings = default_settings.duplicate(true)
	apply_settings()
	dirty = false

func reset_inputs_to_default() -> void:
	InputSupport.invalidate_labels()
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
	InputSupport.invalidate_labels()
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
	if not particle.has_meta("quality_amount"):
		particle.set_meta("quality_amount", particle.amount)
	var count := maxi(1, int(float(particle.get_meta("quality_amount")) * particle_scale()))
	if particle.amount != count:
		particle.amount = count
	if not enabled:
		if not particle.has_meta("settings_emitting"):
			particle.set_meta("settings_emitting", particle.emitting)
			particle.set_meta("settings_visible", particle.visible)
			particle.set_meta("settings_process_mode", particle.process_mode)
		particle.visible = false
		particle.emitting = false
		particle.process_mode = Node.PROCESS_MODE_DISABLED
	elif particle.has_meta("settings_emitting"):
		particle.visible = bool(particle.get_meta("settings_visible"))
		particle.process_mode = int(particle.get_meta("settings_process_mode"))
		# Never replay an old one-shot burst when quality is restored.
		particle.emitting = bool(particle.get_meta("settings_emitting")) and not particle.one_shot
		for key in ["settings_emitting", "settings_visible", "settings_process_mode"]:
			particle.remove_meta(key)
