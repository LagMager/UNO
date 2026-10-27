extends RefCounted

## Cards owned by the player across encounters. Combat uses a copy so drawing,
## playing, and recycling never change the collection itself.

var _cards: Array[Card] = []


func _init() -> void:
	reset_to_starter()


func reset_to_starter() -> void:
	_cards = CardSystem.make_starting_deck()


func size() -> int:
	return _cards.size()


func cards() -> Array[Card]:
	var copy: Array[Card] = []
	for card: Card in _cards:
		if card != null:
			copy.append(card.clone())
	return copy


func add_card(card: Card) -> bool:
	if not CardSystem.is_valid_card(card):
		return false
	_cards.append(card.clone())
	return true


func make_draw_pile() -> Array[Card]:
	return cards()
