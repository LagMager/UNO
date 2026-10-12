extends RefCounted

## A single experimental combat encounter. Values here are playtest parameters.

const COLORS: Array[String] = ["Red", "Yellow", "Green", "Blue"]
const STARTING_HEALTH := 8
const STARTING_HAND_SIZE := 5
const ALL_OUT_DAMAGE := 3
const PLAYER_CARD_DAMAGE := 1
const ENEMY_ATTACK_DAMAGE := 1
const ENEMY_ATTACK_INTERVAL := 2
const MAX_REPLAY_CHAIN := 8

var draw_pile: Array[Dictionary] = []
var discard_pile: Array[Dictionary] = []
var player_hand: Array[Dictionary] = []
var enemy_hand: Array[Dictionary] = []
var active_color := ""
var player_health := STARTING_HEALTH
var enemy_health := STARTING_HEALTH
var completed_rounds := 0
var phase := "player"
var result := ""
var events: Array[String] = []

var _player_actions := 1
var _skip_enemy_uno := false
var _skip_player_turn := false


func _init() -> void:
	new_game()


func new_game() -> void:
	draw_pile.clear()
	discard_pile.clear()
	player_hand.clear()
	enemy_hand.clear()
	events.clear()
	player_health = STARTING_HEALTH
	enemy_health = STARTING_HEALTH
	completed_rounds = 0
	phase = "player"
	result = ""
	_player_actions = 1
	_skip_enemy_uno = false
	_skip_player_turn = false

	for color in COLORS:
		for number in range(10):
			draw_pile.append(_card(color, "number", number))
		for copy in range(2):
			draw_pile.append(_card(color, "replay"))
			draw_pile.append(_card(color, "skip"))
	for copy in range(4):
		draw_pile.append(_card("Wild", "wild"))
	draw_pile.shuffle()
	_draw_to(player_hand, STARTING_HAND_SIZE)
	_draw_to(enemy_hand, STARTING_HAND_SIZE)

	# Start on a number so the first matching decision is easy to read.
	for index in range(draw_pile.size()):
		if draw_pile[index]["kind"] == "number":
			var starter: Dictionary = draw_pile[index]
			draw_pile.remove_at(index)
			discard_pile.append(starter)
			active_color = starter["color"]
			break
	_log("Encounter started. Play a matching card or draw one.")


func top_card() -> Dictionary:
	return discard_pile.back()


func card_label(card: Dictionary) -> String:
	if card["kind"] == "number":
		return "%s %d" % [card["color"], card["number"]]
	if card["kind"] == "wild":
		return "Wild"
	return "%s %s" % [card["color"], card["kind"].capitalize()]


func can_play(card: Dictionary) -> bool:
	if card["kind"] == "wild":
		return true
	var top: Dictionary = top_card()
	if card["color"] == active_color:
		return true
	if card["kind"] == "number" and top["kind"] == "number":
		return card["number"] == top["number"]
	return card["kind"] == top["kind"] and card["kind"] != "number"


func play_player_card(index: int, wild_color: String = "") -> bool:
	if phase != "player" or index < 0 or index >= player_hand.size():
		return false
	var card: Dictionary = player_hand[index]
	if not can_play(card):
		return false
	if card["kind"] == "wild" and not COLORS.has(wild_color):
		return false

	player_hand.remove_at(index)
	_play_to_discard(card, wild_color)
	_log("You played %s. Enemy takes %d damage." % [card_label(card), PLAYER_CARD_DAMAGE])
	enemy_health -= PLAYER_CARD_DAMAGE
	if _check_outcome():
		return true

	if card["kind"] == "skip":
		_skip_enemy_uno = true
		_log("Enemy UNO action will be skipped this round.")
	elif card["kind"] == "replay":
		_player_actions += 1
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
	if phase != "player":
		return false
	if _draw_to(player_hand, 1) == 0:
		_log("No card is available to draw.")
	else:
		_log("You drew one card and ended your turn.")
	_player_actions = 0
	_complete_round()
	return true


func _complete_round() -> void:
	while phase != "finished":
		if _skip_enemy_uno:
			_log("Enemy UNO action skipped.")
			_skip_enemy_uno = false
		else:
			_enemy_uno_action()
		if phase == "finished":
			return

		completed_rounds += 1
		if completed_rounds % ENEMY_ATTACK_INTERVAL == 0:
			player_health -= ENEMY_ATTACK_DAMAGE
			_log("Scheduled enemy attack deals %d damage." % ENEMY_ATTACK_DAMAGE)
			if _check_outcome():
				return

		_player_actions = 1
		if _skip_player_turn:
			_skip_player_turn = false
			_log("Your UNO action is skipped this round.")
			continue
		phase = "player"
		return


func _enemy_uno_action() -> void:
	var actions := 1
	var played := 0
	while actions > 0 and played < MAX_REPLAY_CHAIN and phase != "finished":
		var playable_index := -1
		for index in range(enemy_hand.size()):
			if can_play(enemy_hand[index]):
				playable_index = index
				break
		if playable_index == -1:
			if _draw_to(enemy_hand, 1) > 0:
				_log("Enemy drew one card.")
			else:
				_log("Enemy could not draw.")
			return

		var card: Dictionary = enemy_hand[playable_index]
		enemy_hand.remove_at(playable_index)
		var chosen_color := ""
		if card["kind"] == "wild":
			chosen_color = _enemy_color_choice()
		_play_to_discard(card, chosen_color)
		_log("Enemy played %s%s." % [card_label(card), " (" + chosen_color + ")" if chosen_color != "" else ""])
		actions -= 1
		played += 1
		if card["kind"] == "replay":
			actions += 1
		elif card["kind"] == "skip":
			_skip_player_turn = true

		if enemy_hand.is_empty():
			player_health -= ALL_OUT_DAMAGE
			_log("Enemy All-Out Attack deals %d damage." % ALL_OUT_DAMAGE)
			if _check_outcome():
				return
			_draw_to(enemy_hand, STARTING_HAND_SIZE)
			_log("Enemy receives a new hand.")


func _play_to_discard(card: Dictionary, wild_color: String) -> void:
	discard_pile.append(card)
	active_color = wild_color if card["kind"] == "wild" else card["color"]


func _draw_to(hand: Array[Dictionary], count: int) -> int:
	var drawn := 0
	for attempt in range(count):
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
	var top: Dictionary = discard_pile.pop_back()
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	discard_pile.append(top)
	draw_pile.shuffle()
	_log("Discard pile shuffled into the draw pile.")


func _enemy_color_choice() -> String:
	var best_color := COLORS[0]
	var best_count := -1
	for color in COLORS:
		var count := 0
		for card in enemy_hand:
			if card["color"] == color:
				count += 1
		if count > best_count:
			best_count = count
			best_color = color
	return best_color


func _check_outcome() -> bool:
	if enemy_health <= 0:
		phase = "finished"
		result = "Victory"
		_log("Enemy defeated.")
		return true
	if player_health <= 0:
		phase = "finished"
		result = "Defeat"
		_log("You were defeated.")
		return true
	return false


func _log(message: String) -> void:
	events.push_front(message)
	if events.size() > 10:
		events.resize(10)


func _card(color: String, kind: String, number: int = -1) -> Dictionary:
	return {"color": color, "kind": kind, "number": number}
