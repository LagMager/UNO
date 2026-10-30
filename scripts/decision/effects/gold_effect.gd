class_name GoldEffect
extends EffectData

## Grants (positive amount) or spends (negative amount) gold in RunState.

@export var amount: int = 0


func _init(p_amount: int = 0) -> void:
	amount = p_amount


func apply(run_state: RunState, _context: Dictionary) -> void:
	if run_state == null or amount == 0:
		return
	run_state.modify_gold(amount)
