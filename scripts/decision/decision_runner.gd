class_name DecisionRunner
extends RefCounted

## Runtime controller that executes a DecisionData event against RunState.
## Evaluates choice requirements, resolves outcomes deterministically, applies effects in order,
## transitions to follow-up decisions, and prevents invalid selections, duplicate execution,
## and circular decision loops.

signal decision_changed(decision: DecisionData)
signal outcome_applied(outcome: OutcomeData)
signal decision_finished(pending_encounter: EncounterData)

const MAX_DECISION_STEPS := 16

var current_decision: DecisionData = null
var run_state: RunState = null
var is_finished: bool = false
var last_outcome_description: String = ""
var pending_encounter: EncounterData = null
var step_count: int = 0

var _visited_decisions: Array[DecisionData] = []
var _is_executing_choice: bool = false


func start(decision: DecisionData, state: RunState) -> bool:
	run_state = state
	current_decision = decision
	is_finished = false
	last_outcome_description = ""
	pending_encounter = null
	step_count = 0
	_visited_decisions.clear()
	_is_executing_choice = false

	if current_decision == null or not current_decision.is_valid() or run_state == null:
		push_error("DecisionRunner.start called with invalid DecisionData or RunState.")
		is_finished = true
		decision_finished.emit(null)
		return false

	_visited_decisions.append(current_decision)
	if current_decision.choices.is_empty():
		is_finished = true
		decision_finished.emit(null)
		return true

	decision_changed.emit(current_decision)
	return true


## Returns metadata for each choice in the active decision, including availability and requirement hints.
func get_choice_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if current_decision == null or is_finished:
		return result

	for index: int in range(current_decision.choices.size()):
		var choice: ChoiceData = current_decision.choices[index]
		if choice == null:
			continue
		var available: bool = choice.is_available(run_state)
		var unmet_reasons: Array[String] = []
		for req: ConditionData in choice.requirements:
			if req != null and not req.is_met(run_state):
				var desc: String = req.describe()
				if not desc.is_empty():
					unmet_reasons.append(desc)
		var display_text: String = choice.text
		if not unmet_reasons.is_empty():
			display_text = "%s (%s)" % [choice.text, ", ".join(unmet_reasons)]
		result.append({
			"index": index,
			"text": display_text,
			"available": available,
		})
	return result


func can_choose(choice_index: int) -> bool:
	if is_finished or _is_executing_choice or current_decision == null or run_state == null:
		return false
	if choice_index < 0 or choice_index >= current_decision.choices.size():
		return false
	var choice: ChoiceData = current_decision.choices[choice_index]
	return choice != null and choice.is_available(run_state)


## Validates and executes the player's selected choice index.
func choose(choice_index: int) -> bool:
	if not can_choose(choice_index):
		return false

	_is_executing_choice = true
	var choice: ChoiceData = current_decision.choices[choice_index]
	var outcome: OutcomeData = choice.resolve_outcome(run_state)
	if outcome == null:
		_is_executing_choice = false
		return false

	step_count += 1
	last_outcome_description = outcome.result_description

	var context := {"pending_encounter": pending_encounter}
	for effect: EffectData in outcome.effects:
		if effect != null:
			effect.apply(run_state, context)
	if context.get("pending_encounter") is EncounterData:
		pending_encounter = context["pending_encounter"] as EncounterData

	outcome_applied.emit(outcome)

	# If player died from an effect or an encounter was triggered, finish immediately.
	if run_state.current_health <= 0 or pending_encounter != null:
		is_finished = true
		_is_executing_choice = false
		decision_finished.emit(pending_encounter)
		return true

	var follow_up: DecisionData = outcome.next_decision
	if follow_up == null:
		is_finished = true
		_is_executing_choice = false
		decision_finished.emit(pending_encounter)
		return true

	# Guard against circular decision references or excessive depth
	if not follow_up.is_valid() or _visited_decisions.has(follow_up) or step_count >= MAX_DECISION_STEPS:
		push_error("DecisionRunner: Circular or invalid follow-up DecisionData detected ('%s'); ending event safely." % (follow_up.content_id if follow_up != null else "null"))
		is_finished = true
		_is_executing_choice = false
		decision_finished.emit(pending_encounter)
		return true

	current_decision = follow_up
	_visited_decisions.append(current_decision)
	_is_executing_choice = false

	if current_decision.choices.is_empty():
		is_finished = true
		decision_finished.emit(pending_encounter)
	else:
		decision_changed.emit(current_decision)
	return true
