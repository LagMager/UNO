class_name OutcomeData
extends Resource

## Represents one possible outcome of a ChoiceData.
## Outcomes are evaluated in order; the first OutcomeData whose conditions all pass is selected.

@export_multiline var result_description: String = ""
@export var conditions: Array[ConditionData] = []
@export var effects: Array[EffectData] = []
@export var next_decision: DecisionData = null


func _init(
	p_result_description: String = "",
	p_effects: Array[EffectData] = [],
	p_next_decision: DecisionData = null,
	p_conditions: Array[ConditionData] = []
) -> void:
	result_description = p_result_description
	effects = p_effects.duplicate()
	next_decision = p_next_decision
	conditions = p_conditions.duplicate()


func are_conditions_met(run_state: RunState) -> bool:
	for cond: ConditionData in conditions:
		if cond != null and not cond.is_met(run_state):
			return false
	return true
