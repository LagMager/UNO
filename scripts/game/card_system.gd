# Place this file at: res://scripts/game/card_system.gd
class_name CardSystem
extends RefCounted

const NUMBER_COUNT: int = 10
const WILD_COUNT: int = 4

const STANDARD_COLORS: Array[Card.CardColor] = [
	Card.CardColor.RED,
	Card.CardColor.YELLOW,
	Card.CardColor.GREEN,
	Card.CardColor.BLUE,
]


static func make_starting_deck() -> Array[Card]:
	var deck: Array[Card] = []

	for card_color: Card.CardColor in STANDARD_COLORS:
		for num: int in range(NUMBER_COUNT):
			deck.append(Card.new(card_color, Card.Kind.NUMBER, num))

		# Two of each action card per color (matching the classic 60-card combat deck)
		for _copy: int in range(2):
			deck.append(Card.new(card_color, Card.Kind.REPLAY))
			deck.append(Card.new(card_color, Card.Kind.SKIP))

	for i: int in range(WILD_COUNT):
		deck.append(Card.new(Card.CardColor.WILD, Card.Kind.WILD))

	return deck


static func is_valid_card(card: Card) -> bool:
	if card == null or card.instance_id.is_empty():
		return false

	if card.kind == Card.Kind.WILD:
		return card.color == Card.CardColor.WILD and card.number == -1

	if not STANDARD_COLORS.has(card.color):
		return false

	if card.kind == Card.Kind.NUMBER:
		return card.number >= 0 and card.number < NUMBER_COUNT

	if card.kind == Card.Kind.REPLAY or card.kind == Card.Kind.SKIP:
		return card.number == -1

	return false


static func can_play_card(card: Card, top_card: Card, active_color: Card.CardColor = Card.CardColor.WILD) -> bool:
	if card == null or top_card == null:
		return false

	# Wild cards can always be played
	if card.kind == Card.Kind.WILD or card.color == Card.CardColor.WILD:
		return true

	# Determine effective active color on the discard pile
	var effective_color: Card.CardColor = active_color if active_color != Card.CardColor.WILD else top_card.color

	# Matching color (or top card is an unresolved Wild)
	if card.color == effective_color or effective_color == Card.CardColor.WILD:
		return true

	# Matching number on number cards
	if card.kind == Card.Kind.NUMBER and top_card.kind == Card.Kind.NUMBER:
		return card.number == top_card.number

	# Matching action kind (e.g., Replay on Replay, Skip on Skip)
	if card.kind != Card.Kind.NUMBER and card.kind == top_card.kind:
		return true

	return false


static func get_card_by_id(deck: Array[Card], target_id: String) -> Card:
	for card: Card in deck:
		if card != null and card.instance_id == target_id:
			return card
	return null
