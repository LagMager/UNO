extends SceneTree

const Encounter = preload("res://scripts/game/encounter.gd")
const EnemyAI = preload("res://scripts/game/enemy_ai.gd")
const EnemyProfiles = preload("res://scripts/game/enemy_profiles.gd")
const RewardSystem = preload("res://scripts/game/reward_system.gd")

var failures := 0


func _initialize() -> void:
	seed(42)
	_test_catalog()
	_test_player_deck()
	_test_reward_system()
	_test_enemy_profiles()
	_test_enemy_ai_and_state_contract()
	_test_event_order()
	_test_round_progression()
	_test_replay_and_skip()
	_test_all_out_attacks()
	_test_wild_and_terminal_states()
	_test_restart()
	_test_full_encounters()
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
	game.discard_pile.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 1))
	game.active_color = Card.CardColor.RED
	return game


func _test_catalog() -> void:
	var deck: Array[Card] = CardSystem.make_starting_deck()
	_check(deck.size() == 60, "CardSystem should build the 60-card starting deck.")
	var replay_card := Card.new(Card.CardColor.RED, Card.Kind.REPLAY)
	_check(replay_card.get_label() == "Red Replay", "Card label changed.")
	var wild_card := Card.new(Card.CardColor.WILD, Card.Kind.WILD)
	_check(wild_card.get_damage() == 1, "Wild damage changed.")
	replay_card.upgrade()
	_check(replay_card.get_label() == "+Red Replay" and replay_card.get_damage() == 3, "Upgraded card should have + prefix and +2 damage.")
	_check(CardSystem.get_card_by_id(deck, deck[0].instance_id) == deck[0], "get_card_by_id should locate card by instance_id.")


func _test_player_deck() -> void:
	var game = Encounter.new()
	_check(game.player_deck.size() == 60, "Player collection should start with the original card mix.")
	var invalid_card := Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 99)
	_check(not game.player_deck.add_card(invalid_card), "Invalid cards should not enter the collection.")
	var bonus := Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 9)
	_check(game.player_deck.add_card(bonus), "Valid card should be added to the collection.")
	bonus.color = Card.CardColor.BLUE
	_check(game.player_deck.cards().back().color == Card.CardColor.RED, "Adding a card should copy it.")
	var snapshot: Array[Card] = game.player_deck.cards()
	snapshot.back().color = Card.CardColor.GREEN
	_check(game.player_deck.cards().back().color == Card.CardColor.RED, "Reading the collection should not expose its cards.")
	_check(game.draw_pile.size() + game.player_hand.size() + game.enemy_hand.size() + game.discard_pile.size() == 60, "Editing the collection should not alter active combat piles.")
	_check(game.start_encounter("standard"), "Encounter should restart with the player collection.")
	_check(game.draw_pile.size() + game.player_hand.size() + game.enemy_hand.size() + game.discard_pile.size() == 61, "Next encounter should use the edited collection.")
	_check(game.player_deck.size() == 61, "Starting another encounter should preserve the collection.")
	game.player_deck.reset_to_starter()
	_check(game.player_deck.size() == 60, "A new run should restore the starter collection.")


func _test_reward_system() -> void:
	var game = Encounter.new()
	var rewards: Array[Card] = RewardSystem.generate_card_rewards(3)
	_check(rewards.size() == 3, "RewardSystem should generate 3 card choices.")
	for card: Card in rewards:
		_check(CardSystem.is_valid_card(card), "Generated reward card should be valid.")
	var chosen: Card = rewards[0]
	_check(RewardSystem.claim_reward(game.player_deck, chosen), "Claiming a valid reward should succeed.")
	_check(game.player_deck.size() == 61, "Claiming a reward should increase the player's deck size by 1.")


func _test_enemy_profiles() -> void:
	var game = _setup()
	_check(not game.start_encounter("missing"), "Unknown enemy should be rejected.")
	_check(game.enemy_id == "standard", "Invalid enemy should not change the encounter.")
	_check(game.start_encounter("trickster", 5), "Trickster encounter should start.")
	_check(game.player_health == 5 and game.enemy_id == "trickster", "Selected profile and carried health should be applied.")
	game.draw_pile.clear()
	game.discard_pile.clear()
	game.enemy_hand.clear()
	game.discard_pile.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 1))
	game.active_color = Card.CardColor.RED
	game.enemy_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 2))
	game.enemy_hand.append(Card.new(Card.CardColor.RED, Card.Kind.SKIP))
	_check(EnemyAI.choose_card(game.enemy_hand, game.can_play, game.enemy_profile()["prioritize_actions"]) == 1, "Trickster should prefer a playable action card.")
	game.enemy_id = "standard"
	_check(EnemyAI.choose_card(game.enemy_hand, game.can_play, game.enemy_profile()["prioritize_actions"]) == 0, "Standard enemy should keep first-match behavior.")

	game = _setup()
	game.enemy_id = "aggressor"
	game.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	_check(game.draw_player_card(), "Aggressor round should resolve.")
	_check(game.completed_rounds == 1 and game.player_health == 7, "Aggressor should attack after the first round.")


func _test_enemy_ai_and_state_contract() -> void:
	var game = _setup()
	_check(EnemyProfiles.is_valid("standard") and EnemyProfiles.is_valid("aggressor") and EnemyProfiles.is_valid("trickster"), "Built-in profiles should validate.")
	_check(not EnemyProfiles.is_valid("missing") and EnemyProfiles.get_profile("missing")["name"] == "Standard", "Unknown profile should retain the Standard read fallback.")
	var edited_profile: Dictionary = EnemyProfiles.get_profile("standard")
	edited_profile["attack_interval"] = 0
	_check(not EnemyProfiles.is_valid_profile(edited_profile), "Zero attack interval should be rejected.")
	edited_profile["attack_interval"] = -1
	_check(not EnemyProfiles.is_valid_profile(edited_profile), "Negative attack interval should be rejected.")
	_check(EnemyProfiles.get_profile("standard")["attack_interval"] == 2, "Reading a profile should not expose shared configuration.")
	game.enemy_health = 5
	game.enemy_id = "trickster"
	_check(game.enemy_health == 5 and game.enemy_profile()["name"] == "Trickster", "Public enemy state accessors should remain writable.")
	game.enemy_id = "missing"
	_check(game.enemy_profile()["name"] == "Standard", "Direct unknown enemy ID should retain Standard fallback.")
	game.enemy_id = "standard"
	var replacement_hand: Array[Card] = [Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 2)]
	game.enemy_hand = replacement_hand
	_check(game.enemy_hand.size() == 1 and game.enemy_hand[0].color == Card.CardColor.BLUE, "Public enemy hand assignment should remain writable.")
	_check(EnemyAI.choose_card(game.enemy_hand, game.can_play, false) == -1, "AI should report no playable card when none matches.")
	game.enemy_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 2))
	_check(EnemyAI.choose_card(game.enemy_hand, game.can_play, true) == 1, "AI should fall back to the first playable card when no action is playable.")
	game.enemy_hand.clear()
	game.enemy_hand.append(Card.new(Card.CardColor.YELLOW, Card.Kind.NUMBER, 1))
	game.enemy_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 2))
	_check(EnemyAI.choose_wild_color(game.enemy_hand) == Card.CardColor.RED, "Wild color ties should keep the first catalog color.")

	game = _setup()
	game.enemy_hand.append(Card.new(Card.CardColor.WILD, Card.Kind.WILD))
	game.enemy_hand.append(Card.new(Card.CardColor.GREEN, Card.Kind.NUMBER, 2))
	game.enemy_hand.append(Card.new(Card.CardColor.GREEN, Card.Kind.NUMBER, 3))
	game.enemy_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 4))
	_check(game.draw_player_card(), "Enemy Wild scenario should resolve.")
	_check(game.active_color == Card.CardColor.GREEN and game.events.any(func(event: String) -> bool: return event.contains("Enemy played Wild (Green)")), "Enemy Wild should choose from remaining cards and log the choice.")


func _test_event_order() -> void:
	var game = _setup()
	game.player_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 2))
	game.player_hand.append(Card.new(Card.CardColor.GREEN, Card.Kind.NUMBER, 9))
	game.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	game.draw_pile.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 5))
	_check(game.play_player_card(0), "Deterministic player card should play.")
	_check(game.events == [
		"Round 1: Enemy drew one card.",
		"Round 1: You played Red 2. Enemy takes 1 damage."
	], "Action log messages and newest-first order should remain unchanged.")


func _test_round_progression() -> void:
	var game = _setup()
	game.player_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 2))
	game.player_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 9))
	game.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	_check(not game.play_player_card(0, Card.CardColor.BLUE), "A color choice on a non-Wild card should be rejected.")
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
	game.player_hand.append(Card.new(Card.CardColor.RED, Card.Kind.REPLAY))
	game.player_hand.append(Card.new(Card.CardColor.RED, Card.Kind.SKIP))
	game.player_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 9))
	game.enemy_hand.append(Card.new(Card.CardColor.RED, Card.Kind.SKIP))
	game.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	_check(game.play_player_card(0), "Replay should play.")
	_check(game.completed_rounds == 0 and game.phase == "player", "Replay should leave one player action.")
	_check(game.play_player_card(0), "Skip should play after Replay.")
	_check(game.completed_rounds == 1 and game.enemy_hand.size() == 2, "Player Skip should omit enemy UNO action.")
	_check(game.draw_player_card(), "Drawing should end the next turn.")
	_check(game.completed_rounds == 3 and game.player_health == 7, "Enemy Skip should advance through the skipped player round and scheduled attack.")
	_check(game.phase == "player", "Turn should return to player after skipped action.")


func _test_all_out_attacks() -> void:
	var game = _setup()
	game.player_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 2))
	game.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	for number: int in range(5):
		game.draw_pile.append(Card.new(Card.CardColor.GREEN, Card.Kind.NUMBER, number))
	_check(game.play_player_card(0), "Last player card should play.")
	_check(game.enemy_health == 4 and game.player_hand.size() == 5, "Player All-Out Attack should deal 3 extra damage and refill.")
	_check(game.events.any(func(event: String) -> bool: return event.contains("All-Out Attack")), "All-Out Attack should appear in the log.")

	game = _setup()
	game.enemy_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 2))
	_check(game.draw_player_card(), "Player should be able to end turn with a draw attempt.")
	_check(game.player_health == 5 and game.enemy_hand.size() == 1, "Enemy All-Out Attack should deal 3 damage and refill from discard.")


func _test_wild_and_terminal_states() -> void:
	var game = _setup()
	game.player_hand.append(Card.new(Card.CardColor.WILD, Card.Kind.WILD))
	game.player_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 9))
	game.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	_check(not game.play_player_card(0, Card.CardColor.WILD), "Wild without a chosen standard color should be rejected.")
	_check(game.player_hand.size() == 2 and game.active_color == Card.CardColor.RED, "Invalid Wild color changed state.")
	game.enemy_health = 1
	_check(game.play_player_card(0, Card.CardColor.BLUE), "Valid Wild should play.")
	_check(game.phase == "finished" and game.result == "Victory", "Lethal card should finish encounter before enemy action.")
	_check(game.completed_rounds == 0 and not game.draw_player_card(), "Finished encounter should reject further turns.")
	_check(game.events[0].contains("VICTORY") and game.events[1].contains("Wild (Blue)"), "Victory and Wild choice should be visible in log.")

	game = _setup()
	game.player_health = 1
	game.completed_rounds = 1
	game.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	_check(game.draw_player_card(), "Drawing with an empty pile should still end the turn.")
	_check(game.phase == "finished" and game.result == "Defeat", "Scheduled attack should resolve defeat.")
	_check(game.completed_rounds == 2 and game.events[0].contains("DEFEAT"), "Defeat should have the correct round and result log.")


func _test_restart() -> void:
	var game = _setup()
	game.phase = "finished"
	game.result = "Defeat"
	game.new_game()
	_check(game.phase == "player" and game.result == "" and game.completed_rounds == 0, "Restart should reset turn state.")
	_check(game.player_hand.size() == 5 and game.enemy_hand.size() == 5 and game.top_card().kind == Card.Kind.NUMBER, "Restart should deal valid hands and starter.")


func _test_full_encounters() -> void:
	for id in EnemyProfiles.ORDER:
		for _trial: int in range(10):
			var game = Encounter.new()
			_check(game.start_encounter(id), "Simulation profile should start.")
			for _action: int in range(100):
				if game.phase == "finished":
					break
				_check(game.phase == "player", "Simulation should return control to the player or finish.")
				var playable_index := -1
				for index: int in range(game.player_hand.size()):
					if game.can_play(game.player_hand[index]):
						playable_index = index
						break
				if playable_index == -1:
					_check(game.draw_player_card(), "Simulation draw should be valid.")
				elif game.player_hand[playable_index].kind == Card.Kind.WILD:
					_check(game.play_player_card(playable_index, Card.CardColor.RED), "Simulation Wild should be valid.")
				else:
					_check(game.play_player_card(playable_index), "Simulation card should be valid.")
			_check(game.phase == "finished" and game.result in ["Victory", "Defeat"], "Simulation should reach exactly one terminal outcome.")
