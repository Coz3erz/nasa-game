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
	settings = default_settings.duplicate(true)
	load_settings()
	load_player_input_map()
	apply_settings()
	get_tree().node_added.connect(_on_node_added)

func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_index("Music") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")

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
		if act_str.begins_with("ui_"):
			continue
		_default_input_map[act_str] = InputMap.action_get_events(action).duplicate()

func _on_node_added(node: Node) -> void:
	if node is AudioStreamPlayer:
		var p := node as AudioStreamPlayer
		if p.bus == &"Master":
			var nm := p.name.to_lower()
			if nm.contains("music") or nm.contains("ambient") or nm.contains("audio_player"):
				p.bus = &"Music"
			else:
				p.bus = &"SFX"
	elif node is CPUParticles2D:
		(node as CPUParticles2D).visible = bool(settings.get("particles", true))
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

	var vsync_on: bool = bool(settings.get("vsync", true))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)

	var fps: int = int(settings.get("max_fps", 0))
	Engine.max_fps = fps

	var w_mode: String = str(settings.get("window_mode", "Windowed"))
	match w_mode:
		"Fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"Borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res_str: String = str(settings.get("resolution", "1920x1080"))
			var parts := res_str.split("x")
			if parts.size() == 2:
				var target_size := Vector2i(int(parts[0]), int(parts[1]))
				if target_size.x > 0 and target_size.y > 0:
					DisplayServer.window_set_size(target_size)

	var msaa_str: String = str(settings.get("msaa", "Off"))
	var vp := get_viewport()
	if vp != null:
		match msaa_str:
			"2x": vp.msaa_2d = Viewport.MSAA_2X
			"4x": vp.msaa_2d = Viewport.MSAA_4X
			"8x": vp.msaa_2d = Viewport.MSAA_8X
			_: vp.msaa_2d = Viewport.MSAA_DISABLED

func _apply_graphics_and_gameplay() -> void:
	var particles_on: bool = bool(settings.get("particles", true))
	var glow_on: bool = bool(settings.get("glow", true))
	var root := get_tree().root
	if root != null:
		_apply_recursive(root, particles_on, glow_on)

func _apply_recursive(n: Node, particles_on: bool, glow_on: bool) -> void:
	if n is CPUParticles2D:
		(n as CPUParticles2D).visible = particles_on
	elif n is WorldEnvironment:
		var we := n as WorldEnvironment
		if we.environment != null:
			we.environment.glow_enabled = glow_on
	elif n is AudioStreamPlayer:
		var p := n as AudioStreamPlayer
		if p.bus == &"Master":
			var nm := p.name.to_lower()
			if nm.contains("music") or nm.contains("ambient") or nm.contains("audio_player"):
				p.bus = &"Music"
			else:
				p.bus = &"SFX"
	for c in n.get_children():
		_apply_recursive(c, particles_on, glow_on)

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
		if act_str.begins_with("ui_"):
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
