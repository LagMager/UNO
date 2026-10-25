extends SceneTree

const Encounter = preload("res://scripts/game/encounter.gd")
const Cards = preload("res://scripts/game/card_catalog.gd")

var failures := 0


func _initialize() -> void:
	_test_catalog()
	_test_round_progression()
	_test_replay_and_skip()
	_test_all_out_attacks()
	_test_wild_and_terminal_states()
	_test_restart()
	if failures == 0:
		print("Encounter tests passed.")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _setup() -> RefCounted:
	var game = Encounter.new()
	game.draw_pile.clear()
	game.discard_pile.clear()
	game.player_hand.clear()
	game.enemy_hand.clear()
	game.events.clear()
	game.discard_pile.append(Cards.make_card("Red", "number", 1))
	game.active_color = "Red"
	return game


func _test_catalog() -> void:
	var deck := Cards.make_deck()
	_check(deck.size() == 60, "Catalog should build the original 60-card deck.")
	_check(Cards.label(Cards.make_card("Red", "replay")) == "Red Replay", "Card label changed.")
	_check(Cards.damage(Cards.make_card("Wild", "wild")) == 1, "Wild damage changed.")


func _test_round_progression() -> void:
	var game = _setup()
	game.player_hand.append(Cards.make_card("Red", "number", 2))
	game.player_hand.append(Cards.make_card("Blue", "number", 9))
	game.enemy_hand.append(Cards.make_card("Blue", "number", 3))
	_check(not game.play_player_card(0, "Blue"), "A color choice on a non-Wild card should be rejected.")
	_check(game.play_player_card(0), "Valid card should play.")
	_check(game.phase == "player" and game.completed_rounds == 1, "One player and enemy sequence should complete one round.")
	_check(game.player_health == 8 and game.enemy_health == 7, "Ordinary card damage changed.")
	var event_count: int = game.events.size()
	_check(not game.play_player_card(-1) and not game.play_player_card(99), "Invalid indices should be rejected.")
	_check(game.events.size() == event_count, "Rejected input should not change the log.")
	game.phase = "enemy"
	_check(not game.draw_player_card() and not game.play_player_card(0), "Player actions should be rejected during enemy resolution.")


func _test_replay_and_skip() -> void:
	var game = _setup()
	game.player_hand.append(Cards.make_card("Red", "replay"))
	game.player_hand.append(Cards.make_card("Red", "skip"))
	game.player_hand.append(Cards.make_card("Blue", "number", 9))
	game.enemy_hand.append(Cards.make_card("Red", "skip"))
	game.enemy_hand.append(Cards.make_card("Blue", "number", 3))
	_check(game.play_player_card(0), "Replay should play.")
	_check(game.completed_rounds == 0 and game.phase == "player", "Replay should leave one player action.")
	_check(game.play_player_card(0), "Skip should play after Replay.")
	_check(game.completed_rounds == 1 and game.enemy_hand.size() == 2, "Player Skip should omit enemy UNO action.")
	_check(game.draw_player_card(), "Drawing should end the next turn.")
	_check(game.completed_rounds == 3 and game.player_health == 7, "Enemy Skip should advance through the skipped player round and scheduled attack.")
	_check(game.phase == "player", "Turn should return to player after skipped action.")


func _test_all_out_attacks() -> void:
	var game = _setup()
	game.player_hand.append(Cards.make_card("Red", "number", 2))
	game.enemy_hand.append(Cards.make_card("Blue", "number", 3))
	for number in range(5):
		game.draw_pile.append(Cards.make_card("Green", "number", number))
	_check(game.play_player_card(0), "Last player card should play.")
	_check(game.enemy_health == 4 and game.player_hand.size() == 5, "Player All-Out Attack should deal 3 extra damage and refill.")
	_check(game.events.any(func(event: String) -> bool: return event.contains("All-Out Attack")), "All-Out Attack should appear in the log.")

	game = _setup()
	game.enemy_hand.append(Cards.make_card("Red", "number", 2))
	_check(game.draw_player_card(), "Player should be able to end turn with a draw attempt.")
	_check(game.player_health == 5 and game.enemy_hand.size() == 1, "Enemy All-Out Attack should deal 3 damage and refill from discard.")


func _test_wild_and_terminal_states() -> void:
	var game = _setup()
	game.player_hand.append(Cards.make_card("Wild", "wild"))
	game.player_hand.append(Cards.make_card("Blue", "number", 9))
	game.enemy_hand.append(Cards.make_card("Blue", "number", 3))
	_check(not game.play_player_card(0, "Purple"), "Unknown Wild color should be rejected.")
	_check(game.player_hand.size() == 2 and game.active_color == "Red", "Invalid Wild color changed state.")
	game.enemy_health = 1
	_check(game.play_player_card(0, "Blue"), "Valid Wild should play.")
	_check(game.phase == "finished" and game.result == "Victory", "Lethal card should finish encounter before enemy action.")
	_check(game.completed_rounds == 0 and not game.draw_player_card(), "Finished encounter should reject further turns.")
	_check(game.events[0].contains("VICTORY") and game.events[1].contains("Wild (Blue)"), "Victory and Wild choice should be visible in log.")

	game = _setup()
	game.player_health = 1
	game.completed_rounds = 1
	game.enemy_hand.append(Cards.make_card("Blue", "number", 3))
	_check(game.draw_player_card(), "Drawing with an empty pile should still end the turn.")
	_check(game.phase == "finished" and game.result == "Defeat", "Scheduled attack should resolve defeat.")
	_check(game.completed_rounds == 2 and game.events[0].contains("DEFEAT"), "Defeat should have the correct round and result log.")


func _test_restart() -> void:
	var game = _setup()
	game.phase = "finished"
	game.result = "Defeat"
	game.new_game()
	_check(game.phase == "player" and game.result == "" and game.completed_rounds == 0, "Restart should reset turn state.")
	_check(game.player_hand.size() == 5 and game.enemy_hand.size() == 5 and game.top_card()["kind"] == "number", "Restart should deal valid hands and starter.")
