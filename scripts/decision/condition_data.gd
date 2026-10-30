class_name ConditionData
extends Resource

## Base resource for reusable conditions evaluated against RunState.
## Subclasses implement specific checks (gold, health, owned cards).


func is_met(_run_state: RunState) -> bool:
	return true


func describe() -> String:
	return ""
