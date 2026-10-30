class_name MinHealthCondition
extends ConditionData

## Condition requiring the player to have at least `minimum_health` HP.

@export var minimum_health: int = 2


func _init(p_minimum_health: int = 2) -> void:
	minimum_health = p_minimum_health


func is_met(run_state: RunState) -> bool:
	if run_state == null:
		return false
	return run_state.current_health >= minimum_health


func describe() -> String:
	return "Requires %d HP" % minimum_health
