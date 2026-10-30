class_name MinGoldCondition
extends ConditionData

## Condition requiring the player to have at least `required_gold` gold.

@export var required_gold: int = 10


func _init(p_required_gold: int = 10) -> void:
	required_gold = p_required_gold


func is_met(run_state: RunState) -> bool:
	if run_state == null:
		return false
	return run_state.gold >= required_gold


func describe() -> String:
	return "Requires %d Gold" % required_gold
