extends SceneTree

## Saving and loading a map run (slots): progress, health, gold and the deck come back as they were.

const SaveGameScript = preload("res://scripts/run/save_game.gd")

var _failures := 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)


func _initialize() -> void:
	SaveGameScript.root = "user://test_saves/"      # never the player's runs
	for i: int in range(SaveGameScript.SLOTS):
		SaveGameScript.clear(i)
	SaveGameScript.slot = 1
	var a := RunController.new()
	a.start_new_run(1234)
	var state := a.run_state
	var first: String = state.get_reachable_node_ids()[0]
	state.current_node_id = first
	state.completed_node_ids.append(first)
	state.current_health = 5
	state.gold = 77
	state.player_deck.upgrade_first_unupgraded()
	var deck_before := state.player_deck.size()
	_check(SaveGameScript.save(state, "Limbo"), "Saving should succeed.")
	_check(SaveGameScript.exists(1) and not SaveGameScript.exists(0), "It should go to the slot in use.")
	_check(SaveGameScript.peek(1).get("circle", "") == "Limbo", "The paper should say the circle.")
	_check(SaveGameScript.pick_slot_for_new_run() == 0, "A new run takes the first empty slot.")
	SaveGameScript.slot = 0
	_check(SaveGameScript.exists(), "The save file should exist.")

	var b := RunController.new()
	_check(SaveGameScript.load_into(b, 1), "Loading should succeed.")
	_check(SaveGameScript.slot == 1, "After loading, the run keeps saving to its slot.")
	var s2 := b.run_state
	_check(s2.map_data.generation_seed == 1234, "The map should be rebuilt from its seed.")
	_check(s2.current_node_id == first, "The current node should come back.")
	_check(s2.completed_node_ids.has(first), "Completed nodes should come back.")
	_check(s2.current_health == 5, "Health should come back.")
	_check(s2.gold == 77, "Gold should come back.")
	_check(s2.player_deck.size() == deck_before, "The deck size should come back.")
	_check(s2.player_deck.cards()[0].is_upgraded, "Upgrades should come back.")
	_check(s2.active_interaction_node_id.is_empty(), "A loaded run starts on the map.")

	state.mark_run_defeat()
	_check(not SaveGameScript.save(state), "A finished run is not saved.")
	SaveGameScript.clear(1)
	_check(not SaveGameScript.exists(), "Clearing should remove the save.")
	if _failures == 0:
		print("Save game tests passed.")
	quit(1 if _failures > 0 else 0)
