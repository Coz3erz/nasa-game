# CHANGELOG (2026-11-15): Asset-optional connection SFX, active-machine loop, accelerating oxygen alarm and continuous title/options music.
extends Node

@export_group("Module audio overrides")
@export var plug_sfx: AudioStream
@export var unplug_sfx: AudioStream
@export var machine_loop: AudioStream
@export var oxygen_alarm_loop: AudioStream
@export_group("Title audio")
@export var title_music: AudioStream

const ORIGINAL_TITLE_TRACK := "res://sounds/music/cozy-music-complete-lite/ogg/late-night-study.ogg"
var music: AudioStreamPlayer
var hum: AudioStreamPlayer
var alarm: AudioStreamPlayer
var _plug: AudioStream
var _unplug: AudioStream
var _flare: AudioStream

func _ready() -> void:
	music = _player("Music", -12.0)
	hum = _player("SFX", -27.0)
	alarm = _player("SFX", -13.0)
	_plug = plug_sfx if plug_sfx != null else load("res://sounds/sfx/plug.wav")
	_unplug = unplug_sfx if unplug_sfx != null else load("res://sounds/sfx/unplug.wav")
	_flare = load("res://sounds/sfx/solar_flare.wav")
	hum.stream = _loop(machine_loop if machine_loop != null else load("res://sounds/sfx/machine_hum.wav"))
	alarm.stream = _loop(oxygen_alarm_loop if oxygen_alarm_loop != null else load("res://sounds/sfx/oxygen_alarm.wav"))
	if title_music != null:
		music.stream = _loop(title_music)
	elif ResourceLoader.exists(ORIGINAL_TITLE_TRACK):
		music.stream = _loop(load(ORIGINAL_TITLE_TRACK))
	else:
		music.stream = _loop(load("res://sounds/music/menu_fallback.wav"))

func _player(bus_name: String, db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name if AudioServer.get_bus_index(bus_name) >= 0 else "Master"
	player.volume_db = db
	add_child(player)
	return player

func _loop(source: AudioStream) -> AudioStream:
	if source == null:
		return null
	var stream := source.duplicate() as AudioStream
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	elif "loop" in stream:
		stream.loop = true
	return stream

func set_menu_music(enabled: bool) -> void:
	if enabled and not music.playing:
		music.play()
	elif not enabled:
		music.stop()

func _one_shot(stream: AudioStream, db: float = -10.0) -> void:
	if stream == null:
		return
	var player := _player("SFX", db)
	player.stream = stream
	player.finished.connect(player.queue_free)
	player.play()

func play_plug() -> void:
	_one_shot(_plug)

func play_unplug() -> void:
	_one_shot(_unplug)

func play_flare(override_stream: AudioStream = null, db: float = -8.0) -> void:
	_one_shot(override_stream if override_stream != null else _flare, db)

func alarm_pitch(oxygen: float) -> float:
	if oxygen >= 15.0:
		return lerpf(1.0, 1.5, clampf((30.0 - oxygen) / 15.0, 0.0, 1.0))
	return lerpf(1.5, 2.0, clampf((15.0 - oxygen) / 10.0, 0.0, 1.0))

func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	var gameplay := scene != null and scene.scene_file_path in ["res://scenes/main scenes/game.tscn", "res://scenes/main scenes/tutorial.tscn"]
	var active := false
	if gameplay:
		for module in BaseManager.active_modules:
			if is_instance_valid(module) and module.is_powered and not module.is_broken and not module.is_constructing:
				active = true
				break
	if active and not hum.playing:
		hum.play()
	elif not active:
		hum.stop()
	var critical := gameplay and GameManager.current_phase == GameManager.Phase.SURVIVE and BaseManager.oxygen_level < 30.0 and not BaseManager.day_failed_sent
	if critical:
		alarm.pitch_scale = alarm_pitch(BaseManager.oxygen_level)
		if not alarm.playing:
			alarm.play()
	else:
		alarm.stop()
