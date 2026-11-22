# Place this file at: res://scripts/game/reward_system.gd
class_name RewardSystem
extends RefCounted

## Handles post-encounter card reward generation and deck mutation (Slay the Spire / Balatro style).

const PlayerDeck = preload("res://scripts/game/player_deck.gd")

const DEFAULT_REWARD_COUNT: int = 3
const WEIGHT_COMMON: int = 55
const WEIGHT_UNCOMMON: int = 30
const WEIGHT_RARE: int = 15


## Generates `count` distinct, weighted random Card rewards for post-encounter selection.
static func generate_card_rewards(count: int = DEFAULT_REWARD_COUNT) -> Array[Card]:
	var rewards: Array[Card] = []
	var seen_labels: Array[String] = []
	var max_attempts: int = count * 12
	var attempts: int = 0

	while rewards.size() < count and attempts < max_attempts:
		attempts += 1
		var candidate: Card = _roll_weighted_card()
		var label_key: String = "%s_%d" % [candidate.get_label(), candidate.get_damage()]
		if not seen_labels.has(label_key):
			seen_labels.append(label_key)
			rewards.append(candidate)

	while rewards.size() < count:
		rewards.append(_roll_weighted_card())

	return rewards


## Safely validates and adds the chosen reward card into the player's persistent deck.
static func claim_reward(deck: RefCounted, chosen_card: Card) -> bool:
	if deck == null or chosen_card == null:
		return false
	if not CardSystem.is_valid_card(chosen_card):
		return false
	if deck.has_method("add_card"):
		return deck.add_card(chosen_card)
	return false


## Formats a short summary of a reward card's combat stats for UI display.
static func describe_card(card: Card) -> String:
	if card == null:
		return ""
	var parts: Array[String] = ["%d DMG" % card.get_damage()]
	if card.extra_actions > 0:
		parts.append("+%d Action" % card.extra_actions)
	if card.skips_next_uno:
		parts.append("Skips Enemy UNO")
	if card.kind == Card.Kind.WILD:
		parts.append("Any Color")
	if card.is_upgraded:
		parts.append("Upgraded")
	if card.modifier != "none":
		parts.append(card.modifier.capitalize())
	return " · ".join(parts)


static func _roll_weighted_card() -> Card:
	var total_weight: int = WEIGHT_COMMON + WEIGHT_UNCOMMON + WEIGHT_RARE
	var roll: int = randi() % total_weight
	var random_color: Card.CardColor = CardSystem.STANDARD_COLORS[randi() % CardSystem.STANDARD_COLORS.size()]

	if roll < WEIGHT_COMMON:
		# Common: Number card (0-9), small chance to roll upgraded or bonus damage
		var num: int = randi() % CardSystem.NUMBER_COUNT
		var card := Card.new(random_color, Card.Kind.NUMBER, num)
		if randf() < 0.25:
			card.upgrade()
		elif randf() < 0.20:
			card.bonus_damage = 1
		return card

	if roll < WEIGHT_COMMON + WEIGHT_UNCOMMON:
		# Uncommon: Action card (Replay or Skip), chance to be upgraded
		var action_kind: Card.Kind = Card.Kind.REPLAY if randf() < 0.5 else Card.Kind.SKIP
		var card := Card.new(random_color, action_kind)
		if randf() < 0.30:
			card.upgrade()
		return card

	# Rare: Wild card or heavily boosted action/number card
	if randf() < 0.65:
		var wild_card := Card.new(Card.CardColor.WILD, Card.Kind.WILD)
		if randf() < 0.40:
			wild_card.upgrade()
		return wild_card

	var rare_kind: Card.Kind = [Card.Kind.NUMBER, Card.Kind.REPLAY, Card.Kind.SKIP][randi() % 3]
	var rare_num: int = randi() % CardSystem.NUMBER_COUNT if rare_kind == Card.Kind.NUMBER else -1
	var rare_card := Card.new(random_color, rare_kind, rare_num)
	rare_card.upgrade()
	rare_card.bonus_damage = 1
	rare_card.modifier = "foil"
	return rare_card
