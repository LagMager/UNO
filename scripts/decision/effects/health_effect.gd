class_name HealthEffect
extends EffectData

## Heals (positive amount) or damages (negative amount) the player in RunState.

@export var amount: int = 0


func _init(p_amount: int = 0) -> void:
	amount = p_amount


func apply(run_state: RunState, _context: Dictionary) -> void:
	if run_state == null or amount == 0:
		return
	run_state.modify_health(amount)
