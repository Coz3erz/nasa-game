extends Control

@export_group("Scene Transition")
@export_file("*.tscn") var target_scene: String = "res://scenes/main scenes/game.tscn"
@export var fade_out_duration: float = 1.5

@export_group("Timing")
@export var start_delay: float = 3.0

@export_group("Audio (Optional Overrides - Auto-Synth Used If Empty)")
@export var crash_sfx: AudioStream
@export var typing_sfx: AudioStream
@export var crash_volume_db: float = -2.0
@export var typing_volume_db: float = -9.0

@export_group("Terminal Styling")
@export var char_delay: float = 0.032
@export var line_pause: float = 0.55
@export var terminal_color: Color = Color(0.42, 1.0, 0.55)

var log_lines: Array[String] = [
	">> [FLIGHT_RECORDER // ARES_LANDER_04 // LOG_DUMP_884.LOG]",
	">> [00:00:02.14] CRITICAL ALERT: X-CLASS CORONAL MASS EJECTION IMPACT",
	">> [00:00:03.89] AVIONICS FAILURE... GUIDANCE OFFLINE... HULL BREACH",
	">> [00:00:08.41] HARD IMPACT DETECTED // ELEVATION: -7,152m",
	"",
	"THE SOLAR FLARE CAUSED YOUR SHIP TO CRASH IN HELLAS PLANITIA,",
	"THE MOST DANGEROUS BASIN ON MARS.",
	"",
	">> EMERGENCY BEACON TRANSMITTING...",
	">> EXTRACTION TEAM ETA: 5 SOLS.",
	"",
	"SURVIVE FOR 5 DAYS UNTIL HELP ARRIVES."
]

var bg_rect: ColorRect
var flash_rect: ColorRect
var log_label: Label
var prompt_label: Label
var skip_warn_label: Label
var crash_player: AudioStreamPlayer
var typing_player: AudioStreamPlayer
var font: SystemFont

var full_displayed_text: String = ""
var is_typing: bool = false
var skip_armed_timer: float = 0.0
var skip_cooldown: float = 0.0
var ready_to_continue: bool = false
var transitioning_out: bool = false
var time_elapsed: float = 0.0
var shake_strength: float = 0.0
var base_label_pos: Vector2 = Vector2(72, 64)
var is_waiting_for_start: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	font = SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "monospace"])

	bg_rect = ColorRect.new()
	bg_rect.color = Color.BLACK
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg_rect)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(1.0, 0.25, 0.1, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash_rect)

	log_label = Label.new()
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_color = terminal_color
	ls.font_size = 24
	ls.line_spacing = 8.0
	log_label.label_settings = ls
	log_label.position = base_label_pos
	log_label.size = get_viewport_rect().size - Vector2(144, 180)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(log_label)

	prompt_label = Label.new()
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pls := LabelSettings.new()
	pls.font = font
	pls.font_color = terminal_color.lightened(0.25)
	pls.font_size = 22
	prompt_label.label_settings = pls
	prompt_label.text = ">> [PRESS ANY BUTTON TO CONTINUE]"
	prompt_label.position = Vector2(72, get_viewport_rect().size.y - 80)
	prompt_label.visible = false
	add_child(prompt_label)

	skip_warn_label = Label.new()
	skip_warn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swls := LabelSettings.new()
	swls.font = font
	swls.font_color = Color(1.0, 0.78, 0.28)
	swls.font_size = 15
	skip_warn_label.label_settings = swls
	skip_warn_label.text = "[ PRESS ANY BUTTON AGAIN TO SKIP ]"
	skip_warn_label.modulate.a = 0.0
	add_child(skip_warn_label)

	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()

	_setup_audio()
	
	is_waiting_for_start = true
	_wait_and_start_crash()

func _wait_and_start_crash() -> void:
	var time_remaining = start_delay
	while time_remaining > 0.0 and is_waiting_for_start and is_inside_tree():
		await get_tree().process_frame
		time_remaining -= get_process_delta_time()
	
	if is_waiting_for_start and is_inside_tree():
		is_waiting_for_start = false
		_run_crash_sequence()

func _on_viewport_resized() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	log_label.size = vp_size - Vector2(144, 180)
	prompt_label.position = Vector2(72, vp_size.y - 80)
	if skip_warn_label != null:
		skip_warn_label.position = vp_size - skip_warn_label.size - Vector2(36, 28)

func _input(event: InputEvent) -> void:
	if transitioning_out or skip_cooldown > 0.0:
		return

	var pressed: bool = false
	if event is InputEventKey and event.pressed and not event.echo:
		pressed = true
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			pressed = true
	elif event is InputEventJoypadButton and event.pressed:
		pressed = true

	if not pressed:
		return

	get_viewport().set_input_as_handled()

	if is_waiting_for_start:
		is_waiting_for_start = false
		_run_crash_sequence()
		return

	if ready_to_continue:
		_proceed_to_target_scene()
		return

	if skip_armed_timer > 0.0:
		_proceed_to_target_scene()
	else:
		skip_armed_timer = 3.5
		skip_cooldown = 0.18
		if typing_player != null:
			typing_player.pitch_scale = 0.8
			typing_player.play()

func _proceed_to_target_scene() -> void:
	if transitioning_out:
		return
	transitioning_out = true
	is_typing = false
	skip_armed_timer = 0.0

	if typing_player != null:
		typing_player.pitch_scale = 1.35
		typing_player.play()

	if crash_player != null and crash_player.playing:
		var tw := create_tween()
		tw.tween_property(crash_player, "volume_db", -60.0, fade_out_duration * 0.8)

	var trans = get_node_or_null("/root/Transition")
	if trans != null:
		while "transitioning" in trans and trans.transitioning:
			if not is_inside_tree():
				return
			await get_tree().process_frame
		trans.change_scene(target_scene, fade_out_duration)
	else:
		get_tree().change_scene_to_file(target_scene)

func _process(delta: float) -> void:
	time_elapsed += delta
	if skip_cooldown > 0.0:
		skip_cooldown = maxf(0.0, skip_cooldown - delta)

	if shake_strength > 0.0:
		shake_strength = maxf(0.0, shake_strength - delta * 28.0)
		var offset := Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
		log_label.position = base_label_pos + offset
	else:
		log_label.position = base_label_pos

	var cursor: String = "█" if int(time_elapsed * 3.0) % 2 == 0 else " "
	log_label.text = full_displayed_text + cursor

	if ready_to_continue and prompt_label != null:
		prompt_label.modulate.a = 0.55 + 0.45 * sin(time_elapsed * 5.0)

	if skip_warn_label != null:
		var vp_size: Vector2 = get_viewport_rect().size
		skip_warn_label.position = vp_size - skip_warn_label.size - Vector2(36, 28)
		if skip_armed_timer > 0.0 and not ready_to_continue and not transitioning_out:
			skip_armed_timer = maxf(0.0, skip_armed_timer - delta)
			var pulse_a: float = 0.7 + 0.3 * sin(time_elapsed * 8.0) if skip_armed_timer > 0.5 else (skip_armed_timer / 0.5) * 0.8
			skip_warn_label.modulate.a = lerpf(skip_warn_label.modulate.a, pulse_a, delta * 14.0)
		else:
			skip_warn_label.modulate.a = lerpf(skip_warn_label.modulate.a, 0.0, delta * 10.0)

func _setup_audio() -> void:
	crash_player = AudioStreamPlayer.new()
	crash_player.volume_db = crash_volume_db
	crash_player.stream = crash_sfx if crash_sfx != null else _generate_crash_wav()
	add_child(crash_player)

	typing_player = AudioStreamPlayer.new()
	typing_player.volume_db = typing_volume_db
	typing_player.stream = typing_sfx if typing_sfx != null else _generate_type_click_wav()
	add_child(typing_player)

func _run_crash_sequence() -> void:
	skip_cooldown = 0.18
	crash_player.play()
	shake_strength = 22.0
	flash_rect.color = Color(1.0, 0.3, 0.1, 0.55)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 1.4)

	await get_tree().create_timer(1.4).timeout
	if not is_inside_tree() or transitioning_out:
		return

	is_typing = true
	for line_idx in range(log_lines.size()):
		if transitioning_out or not is_inside_tree():
			return
		var line: String = log_lines[line_idx]
		if line == "":
			full_displayed_text += "\n"
			await get_tree().create_timer(line_pause * 0.6).timeout
			continue

		for i in range(line.length()):
			if transitioning_out or not is_inside_tree():
				return
			var ch: String = line.substr(i, 1)
			full_displayed_text += ch
			if ch != " ":
				typing_player.pitch_scale = randf_range(0.92, 1.12)
				typing_player.play()
			await get_tree().create_timer(char_delay).timeout

		if transitioning_out or not is_inside_tree():
			return

		full_displayed_text += "\n"
		if line_idx == 3:
			crash_player.pitch_scale = 0.75
			crash_player.volume_db = crash_volume_db - 4.0
			crash_player.play()
			shake_strength = 14.0

		await get_tree().create_timer(line_pause).timeout

	if not transitioning_out and is_inside_tree():
		is_typing = false
		ready_to_continue = true
		skip_armed_timer = 0.0
		prompt_label.visible = true

func _generate_crash_wav() -> AudioStreamWAV:
	var mix_rate: int = 22050
	var duration: float = 2.4
	var samples: int = int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	var low_pass: float = 0.0
	var sub_phase: float = 0.0

	for i in range(samples):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 2.2)
		var impact_punch: float = exp(-t * 18.0)

		sub_phase += TAU * lerpf(95.0, 28.0, clampf(t / 0.8, 0.0, 1.0)) / float(mix_rate)
		var sub_boom: float = sin(sub_phase) * impact_punch * 0.9

		var raw_noise: float = randf_range(-1.0, 1.0)
		low_pass = low_pass + 0.14 * (raw_noise - low_pass)
		var metal_crunch: float = sin(t * 420.0 + raw_noise * 3.5) * exp(-t * 6.5) * 0.35

		var sample: float = clampf((low_pass * 1.3 * env) + sub_boom + metal_crunch, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav

func _generate_type_click_wav() -> AudioStreamWAV:
	var mix_rate: int = 22050
	var duration: float = 0.028
	var samples: int = int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in range(samples):
		var t: float = float(i) / float(mix_rate)
		var env: float = exp(-t * 170.0)
		var tone: float = sin(t * TAU * 1450.0) * 0.65 + sin(t * TAU * 2900.0) * 0.35
		var click: float = (tone + randf_range(-0.35, 0.35)) * env
		var pcm: int = int(clampf(click, -1.0, 1.0) * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav
