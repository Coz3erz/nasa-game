class_name SaveFlags
## Tiny save file for "has the player finished X" flags.
const PATH := "user://flags.cfg"

static func get_flag(key: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return false
	return bool(cfg.get_value("flags", key, false))

static func set_flag(key: String, value: bool = true) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("flags", key, value)
	cfg.save(PATH)
