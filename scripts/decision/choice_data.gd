class_name ChoiceData
extends Resource

## Represents one player-selectable option in a DecisionData event.
## Outcome resolution is strictly deterministic: when selected, `outcomes` are evaluated
## in array order and the FIRST OutcomeData whose conditions are met is chosen.

@export var text: String = ""
@export var requirements: Array[ConditionData] = []
@export var outcomes: Array[OutcomeData] = []


func _init(
	p_text: String = "",
	p_outcomes: Array[OutcomeData] = [],
	p_requirements: Array[ConditionData] = []
) -> void:
	text = p_text
	outcomes = p_outcomes.duplicate()
	requirements = p_requirements.duplicate()


func are_requirements_met(run_state: RunState) -> bool:
	for req: ConditionData in requirements:
		if req != null and not req.is_met(run_state):
			return false
	return true


## Resolves the first OutcomeData in `outcomes` whose conditions are satisfied.
func resolve_outcome(run_state: RunState) -> OutcomeData:
	for outcome: OutcomeData in outcomes:
		if outcome != null and outcome.are_conditions_met(run_state):
			return outcome
	return null


func is_available(run_state: RunState) -> bool:
	if text.strip_edges().is_empty():
		return false
	if not are_requirements_met(run_state):
		return false
	return resolve_outcome(run_state) != null
