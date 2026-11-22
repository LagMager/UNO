extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	_test_conditions_and_outcome_priority()
	_test_branching_decision_with_followup_and_effects()
	_test_cycle_protection_and_invalid_selections()
	await _test_decision_ui_and_combat_trigger_integration()

	if failures == 0:
		print("Milestone 5 decision framework tests passed.")
	quit(1 if failures > 0 else 0)


func _test_conditions_and_outcome_priority() -> void:
	var state := RunState.new(null, 8, 12)
	var gold_10 := MinGoldCondition.new(10)
	var gold_20 := MinGoldCondition.new(20)
	var hp_5 := MinHealthCondition.new(5)
	var hp_9 := MinHealthCondition.new(9)
	var has_wild := HasCardCondition.new(Card.CardColor.WILD, Card.Kind.WILD)

	_check(gold_10.is_met(state) and not gold_20.is_met(state), "MinGoldCondition should evaluate current gold accurately.")
	_check(hp_5.is_met(state) and not hp_9.is_met(state), "MinHealthCondition should evaluate current HP accurately.")
	_check(has_wild.is_met(state), "HasCardCondition should detect Wild card in starter deck.")

	# Outcome priority: when multiple outcomes satisfy conditions, the FIRST matching outcome wins.
	var rich_outcome := OutcomeData.new("Rich outcome", [GoldEffect.new(5)], null, [MinGoldCondition.new(20)])
	var mid_outcome := OutcomeData.new("Mid outcome", [GoldEffect.new(10)], null, [MinGoldCondition.new(10)])
	var fallback_outcome := OutcomeData.new("Fallback outcome", [GoldEffect.new(1)], null, [])
	var choice := ChoiceData.new("Test outcome resolution", [rich_outcome, mid_outcome, fallback_outcome])

	var resolved: OutcomeData = choice.resolve_outcome(state)
	_check(resolved == mid_outcome, "ChoiceData must deterministically select the first OutcomeData whose conditions are met.")


func _test_branching_decision_with_followup_and_effects() -> void:
	var state := RunState.new(null, 8, 25)
	state.modify_health(-3) # Current HP = 5, Gold = 25, Deck = 60

	var reward_card := Card.new(Card.CardColor.WILD, Card.Kind.WILD)
	reward_card.upgrade()

	var step_2 := DecisionData.new(
		"dec_step_2",
		"Sanctum Vault",
		"Inside the vault lies a restorative fountain and a gilded card.",
		[
			ChoiceData.new(
				"Drink from the fountain and claim the card (+2 HP, +1 Upgraded Wild)",
				[OutcomeData.new("You recover 2 HP and claim the +Wild card.", [
					HealthEffect.new(2),
					AddCardEffect.new(reward_card),
				])]
			),
			ChoiceData.new(
				"Take the gold pouch (+30 Gold)",
				[OutcomeData.new("You take 30 gold.", [GoldEffect.new(30)])]
			),
		]
	)

	var step_1 := DecisionData.new(
		"dec_step_1",
		"Sealed Gate",
		"A rune-locked gate blocks the vault.",
		[
			ChoiceData.new(
				"Bribe the guardian (Requires 50 Gold)",
				[OutcomeData.new("You pay 50 gold.", [GoldEffect.new(-50)], step_2)],
				[MinGoldCondition.new(50)]
			),
			ChoiceData.new(
				"Insert 15 Gold into the slot (Requires 15 Gold)",
				[OutcomeData.new("The gate unlocks and drains 1 HP.", [
					GoldEffect.new(-15),
					HealthEffect.new(-1),
				], step_2)],
				[MinGoldCondition.new(15)]
			),
		]
	)

	var runner := DecisionRunner.new()
	_check(runner.start(step_1, state), "DecisionRunner should start with valid DecisionData.")
	_check(runner.current_decision == step_1 and not runner.is_finished, "Runner should be on step_1.")

	var states: Array[Dictionary] = runner.get_choice_states()
	_check(states.size() == 2 and not bool(states[0]["available"]) and bool(states[1]["available"]), "Choice 0 (50 Gold) should be unavailable and Choice 1 (15 Gold) available.")

	# Attempt to choose unavailable option 0 -> must be rejected without mutating state
	_check(not runner.choose(0), "Choosing an unavailable choice must return false.")
	_check(state.gold == 25 and state.current_health == 5 and runner.current_decision == step_1, "Failed choice must not change state or decision.")

	# Choose valid option 1 -> applies -15 Gold, -1 HP, and transitions to step_2
	_check(runner.choose(1), "Choosing valid choice 1 should succeed.")
	_check(state.gold == 10 and state.current_health == 4, "Step 1 effects should apply in order (Gold 25->10, HP 5->4).")
	_check(runner.current_decision == step_2 and not runner.is_finished, "Runner should transition to follow-up decision step_2.")

	# Choose option 0 on step_2 -> applies +2 HP, adds +Wild card, and finishes event
	_check(runner.choose(0), "Choosing option 0 in follow-up decision should succeed.")
	_check(state.current_health == 6 and state.player_deck.size() == 61, "Step 2 effects should heal +2 HP (to 6) and add 1 card (to 61).")
	_check(runner.is_finished, "Decision without further follow-up should mark runner as finished.")
	_check(not runner.choose(0), "Finished runner must reject duplicate choices.")


func _test_cycle_protection_and_invalid_selections() -> void:
	var state := RunState.new(null, 8, 20)
	var cycle_a := DecisionData.new("cycle_a", "Loop A", "First node in loop.")
	var cycle_b := DecisionData.new("cycle_b", "Loop B", "Second node in loop.")
	cycle_a.choices = [ChoiceData.new("Go to B", [OutcomeData.new("To B", [], cycle_b)])]
	cycle_b.choices = [ChoiceData.new("Back to A", [OutcomeData.new("To A", [], cycle_a)])]

	var runner := DecisionRunner.new()
	_check(runner.start(cycle_a, state), "Cycle test should start.")
	_check(runner.choose(0), "Transition A -> B should succeed.")
	_check(runner.current_decision == cycle_b and not runner.is_finished, "Should now be at B.")
	_check(runner.choose(0), "Transition B -> A should be caught by cycle protection.")
	_check(runner.is_finished, "Circular decision reference must terminate the event safely instead of looping forever.")
	cycle_a.choices.clear()
	cycle_b.choices.clear()


func _test_decision_ui_and_combat_trigger_integration() -> void:
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/game/main.tscn")
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame

	var ambush_encounter := EncounterData.new("enc_ambush", "aggressor", EncounterData.Tier.NORMAL, "Ambush Stalker")
	var ambush_decision := DecisionData.new(
		"dec_ambush",
		"Suspicious Chest",
		"A chest sits in the center of the corridor.",
		[
			ChoiceData.new(
				"Pry open the chest (+10 Gold, triggers Ambush!)",
				[OutcomeData.new("It was a trap! An Ambush Stalker leaps out!", [
					GoldEffect.new(10),
					StartEncounterEffect.new(ambush_encounter),
				])]
			),
		]
	)

	var map := MapData.new(909, 2, "n_event", "n_boss")
	var n_event := MapNodeData.new("n_event", MapEnums.NodeType.DECISION, 0, 0, ambush_decision)
	var n_boss := MapNodeData.new("n_boss", MapEnums.NodeType.BOSS, 1, 0, EncounterData.new("boss_1", "standard", EncounterData.Tier.BOSS))
	n_event.add_connection("n_boss")
	map.add_node(n_event)
	map.add_node(n_boss)

	var state: RunState = ui.run_controller.start_run_with_map(map, 8, 20)
	ui.map_view.bind_run_state(state)
	await process_frame

	_check(ui.map_view.request_select_node("n_event"), "Selecting event node should open Decision UI.")
	await process_frame
	_check(ui.interaction_view.visible and ui.interaction_view.title_label.text == "Suspicious Chest", "NodeInteractionView should display active DecisionData.")

	# Click choice 0 in the UI -> gains 10 Gold and queues StartEncounterEffect
	_check(ui.interaction_view.select_option_index(0), "Selecting choice 0 in Decision UI should succeed.")
	_check(state.gold == 30 and ui.interaction_view.continue_button.visible, "Gold effect should apply and Continue button should appear.")

	# Click Continue -> transitions directly into CombatView for the triggered Ambush encounter!
	ui.interaction_view.finish_interaction()
	await process_frame
	_check(ui.combat_view.visible and ui.encounter.enemy_profile()["name"] == "Ambush Stalker", "StartEncounterEffect should transition into combat with the specified EncounterData.")

	ui.queue_free()
	await process_frame
