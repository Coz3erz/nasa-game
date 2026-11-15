# CHANGELOG (2026-11-15): Scene-owned one-shot timers avoid orphaned SceneTreeTimer coroutine references when a cutscene is skipped.
class_name SceneDelay
extends RefCounted

static func timer(owner: Node, seconds: float, always: bool = false) -> Timer:
	var clock := Timer.new()
	clock.one_shot = true
	clock.wait_time = maxf(0.001, seconds)
	clock.process_mode = Node.PROCESS_MODE_ALWAYS if always else Node.PROCESS_MODE_PAUSABLE
	owner.add_child(clock)
	clock.timeout.connect(clock.queue_free)
	clock.start()
	return clock
