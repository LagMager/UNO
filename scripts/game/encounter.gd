extends RefCounted

## A single experimental combat encounter. Values here are playtest parameters.

const EnemyAI = preload("res://scripts/game/enemy_ai.gd")
const EnemyProfiles = preload("res://scripts/game/enemy_profiles.gd")
const EnemyState = preload("res://scripts/game/enemy_state.gd")
const PlayerDeck = preload("res://scripts/game/player_deck.gd")

const COLORS: Array[Card.CardColor] = CardSystem.STANDARD_COLORS
const STARTING_HEALTH := 8
const STARTING_HAND_SIZE := 5
const ALL_OUT_DAMAGE := 3
const MAX_REPLAY_CHAIN := 8
const PHASE_PLAYER := "player"
const PHASE_ENEMY := "enemy"
const PHASE_FINISHED := "finished"

var draw_pile: Array[Card] = []
var discard_pile: Array[Card] = []
var player_hand: Array[Card] = []
var player_deck: PlayerDeck
var _enemy_state: EnemyState
var enemy_hand: Array[Card]:
	get: return _enemy_state.hand
	set(value): _enemy_state.hand = value
var active_color: Card.CardColor = Card.CardColor.RED
var player_health := STARTING_HEALTH
var enemy_health: int:
	get: return _enemy_state.health
	set(value): _enemy_state.health = value
var completed_rounds := 0
var phase: String = PHASE_PLAYER
var result := ""
var events: Array[String] = []
var enemy_id: String:
	get: return _enemy_state.id
	set(value): _enemy_state.id = value

var _player_actions := 1
var _skip_enemy_uno := false
var _skip_player_turn := false


func _init() -> void:
	_enemy_state = EnemyState.new("standard", STARTING_HEALTH)
	player_deck = PlayerDeck.new()
	new_game()


func start_encounter(id: String, starting_player_health: int = STARTING_HEALTH) -> bool:
	if not EnemyProfiles.is_valid(id):
		return false
	enemy_id = id
	new_game(starting_player_health)
	return true


func enemy_profile() -> Dictionary:
	return EnemyProfiles.get_profile(enemy_id)


func new_game(starting_player_health: int = STARTING_HEALTH) -> void:
	draw_pile.clear()
	discard_pile.clear()
	player_hand.clear()
	enemy_hand.clear()
	events.clear()
	player_health = clampi(starting_player_health, 1, STARTING_HEALTH)
	enemy_health = enemy_profile()["health"]
	completed_rounds = 0
	phase = PHASE_PLAYER
	result = ""
	_player_actions = 1
	_skip_enemy_uno = false
	_skip_player_turn = false

	draw_pile = player_deck.make_draw_pile()
	draw_pile.shuffle()
	_draw_to(player_hand, STARTING_HAND_SIZE)
	_draw_to(enemy_hand, STARTING_HAND_SIZE)

	# Start on a number so the first matching decision is easy to read.
	for index: int in range(draw_pile.size()):
		if draw_pile[index].kind == Card.Kind.NUMBER:
			var starter: Card = draw_pile[index]
			draw_pile.remove_at(index)
			discard_pile.append(starter)
			active_color = starter.color
			break
	_log("%s encounter started. Play a matching card or draw one." % enemy_profile()["name"])


func top_card() -> Card:
	return discard_pile.back() if not discard_pile.is_empty() else null


func card_label(card: Card) -> String:
	return card.get_label() if card != null else ""


func active_color_name() -> String:
	return Card.color_to_string(active_color)


func can_play(card: Card) -> bool:
	if card == null:
		return false
	return CardSystem.can_play_card(card, top_card(), active_color)


func play_player_card(index: int, wild_color: Card.CardColor = Card.CardColor.WILD) -> bool:
	if phase != PHASE_PLAYER or index < 0 or index >= player_hand.size():
		return false
	var card: Card = player_hand[index]
	if not can_play(card):
		return false
	if card.kind == Card.Kind.WILD and not COLORS.has(wild_color):
		return false
	if card.kind != Card.Kind.WILD and wild_color != Card.CardColor.WILD:
		return false

	player_hand.remove_at(index)
	_play_to_discard(card, wild_color)
	var damage: int = card.get_damage()
	var wild_suffix: String = " (%s)" % Card.color_to_string(wild_color) if card.kind == Card.Kind.WILD else ""
	_log("You played %s%s. Enemy takes %d damage." % [card_label(card), wild_suffix, damage])
	enemy_health -= damage
	if _check_outcome():
		return true

	if card.skips_next_uno:
		_skip_enemy_uno = true
		_log("Enemy UNO action will be skipped this round.")
	if card.extra_actions > 0:
		_player_actions += card.extra_actions
		_log("Replay gives you another card action.")

	if player_hand.is_empty():
		_log("Your hand is empty: All-Out Attack deals %d damage." % ALL_OUT_DAMAGE)
		enemy_health -= ALL_OUT_DAMAGE
		if _check_outcome():
			return true
		_draw_to(player_hand, STARTING_HAND_SIZE)
		_log("You receive a new hand of %d cards." % player_hand.size())

	_player_actions -= 1
	if _player_actions <= 0:
		_complete_round()
	return true


func draw_player_card() -> bool:
	if phase != PHASE_PLAYER:
		return false
	if _draw_to(player_hand, 1) == 0:
		_log("No card is available to draw; your turn ends.")
	else:
		_log("You drew one card and ended your turn.")
	_player_actions = 0
	_complete_round()
	return true


func _complete_round() -> void:
	# Public player actions are rejected until the entire enemy sequence resolves.
	phase = PHASE_ENEMY
	while phase != PHASE_FINISHED:
		if _skip_enemy_uno:
			_log("Enemy UNO action skipped.")
			_skip_enemy_uno = false
		else:
			_enemy_uno_action()
		if phase == PHASE_FINISHED:
			return

		completed_rounds += 1
		if completed_rounds % enemy_profile()["attack_interval"] == 0:
			var attack_damage: int = enemy_profile()["attack_damage"]
			player_health -= attack_damage
			_log("Scheduled enemy attack deals %d damage." % attack_damage, completed_rounds)
			if _check_outcome():
				return

		_player_actions = 1
		if _skip_player_turn:
			_skip_player_turn = false
			_log("Your next UNO action was skipped.")
			continue
		phase = PHASE_PLAYER
		return


func _enemy_uno_action() -> void:
	var actions := 1
	var played := 0
	while actions > 0 and played < MAX_REPLAY_CHAIN and phase != PHASE_FINISHED:
		var playable_index: int = EnemyAI.choose_card(enemy_hand, can_play, enemy_profile()["prioritize_actions"])
		if playable_index < -1 or playable_index >= enemy_hand.size():
			push_error("Enemy AI selected an invalid card index.")
			return
		if playable_index == -1:
			if _draw_to(enemy_hand, 1) > 0:
				_log("Enemy drew one card.")
			else:
				_log("Enemy could not draw.")
			return
		if not can_play(enemy_hand[playable_index]):
			push_error("Enemy AI selected a card that cannot be played.")
			return

		var card: Card = enemy_hand[playable_index]
		var chosen_color: Card.CardColor = Card.CardColor.WILD
		if card.kind == Card.Kind.WILD:
			var remaining_hand: Array[Card] = enemy_hand.duplicate()
			remaining_hand.remove_at(playable_index)
			chosen_color = EnemyAI.choose_wild_color(remaining_hand)
			if not COLORS.has(chosen_color):
				push_error("Enemy AI selected an invalid Wild color.")
				return
		enemy_hand.remove_at(playable_index)
		_play_to_discard(card, chosen_color)
		var wild_suffix: String = " (%s)" % Card.color_to_string(chosen_color) if card.kind == Card.Kind.WILD else ""
		_log("Enemy played %s%s." % [card_label(card), wild_suffix])
		actions -= 1
		played += 1
		actions += card.extra_actions
		if card.skips_next_uno:
			_skip_player_turn = true
			_log("Your next UNO action will be skipped.")

		if enemy_hand.is_empty():
			player_health -= ALL_OUT_DAMAGE
			_log("Enemy All-Out Attack deals %d damage." % ALL_OUT_DAMAGE)
			if _check_outcome():
				return
			_draw_to(enemy_hand, STARTING_HAND_SIZE)
			_log("Enemy receives a new hand.")
	if actions > 0 and played >= MAX_REPLAY_CHAIN:
		_log("Enemy Replay chain ended after %d cards." % MAX_REPLAY_CHAIN)


func _play_to_discard(card: Card, wild_color: Card.CardColor) -> void:
	discard_pile.append(card)
	active_color = wild_color if card.kind == Card.Kind.WILD else card.color


func _draw_to(hand: Array[Card], count: int) -> int:
	var drawn := 0
	for _attempt: int in range(count):
		if draw_pile.is_empty():
			_recycle_discard()
		if draw_pile.is_empty():
			break
		hand.append(draw_pile.pop_back())
		drawn += 1
	return drawn


func _recycle_discard() -> void:
	if discard_pile.size() <= 1:
		return
	var top: Card = discard_pile.pop_back()
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	discard_pile.append(top)
	draw_pile.shuffle()
	_log("Discard pile shuffled into the draw pile.")


func _check_outcome() -> bool:
	if phase == PHASE_FINISHED:
		return true
	if enemy_health <= 0:
		phase = PHASE_FINISHED
		result = "Victory"
		_log("VICTORY — Enemy defeated.")
		return true
	if player_health <= 0:
		phase = PHASE_FINISHED
		result = "Defeat"
		_log("DEFEAT — You were defeated.")
		return true
	return false


func _log(message: String, round_number: int = -1) -> void:
	var logged_round := completed_rounds + 1 if round_number == -1 else round_number
	events.push_front("Round %d: %s" % [logged_round, message])
	if events.size() > 10:
		events.resize(10)
