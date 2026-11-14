extends Node

enum Phase { INTRO, BUILD, SURVIVE, DEBRIEF }
var current_phase: Phase = Phase.BUILD
var current_sol: int = 1
var mass_budget: float = 2000.0
var tutorial_step: int = 0

func _ready() -> void:
	print("GameManager Ready")

func advance_tutorial() -> void:
	tutorial_step += 1
	EventBus.tutorial_step_advanced.emit(tutorial_step)
