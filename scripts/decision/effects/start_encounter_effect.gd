class_name StartEncounterEffect
extends EffectData

## Requests a transition into a combat encounter when the decision finishes.

@export var encounter_data: EncounterData = null


func _init(p_encounter_data: EncounterData = null) -> void:
	encounter_data = p_encounter_data


func apply(_run_state: RunState, context: Dictionary) -> void:
	if encounter_data == null or not encounter_data.is_valid():
		push_error("StartEncounterEffect has missing or invalid EncounterData.")
		return
	context["pending_encounter"] = encounter_data
