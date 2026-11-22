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


func upgrade_first_unupgraded() -> Card:
	for card: Card in _cards:
		if card != null and not card.is_upgraded:
			card.upgrade()
			return card.clone()
	return null


func remove_card_by_instance_id(target_id: String) -> bool:
	for index: int in range(_cards.size()):
		if _cards[index] != null and _cards[index].instance_id == target_id:
			_cards.remove_at(index)
			return true
	return false


func has_matching_card(p_color: Card.CardColor, p_kind: Card.Kind, p_number: int = -1) -> bool:
	for card: Card in _cards:
		if card == null:
			continue
		if card.color != p_color or card.kind != p_kind:
			continue
		if p_kind == Card.Kind.NUMBER and p_number >= 0 and card.number != p_number:
			continue
		return true
	return false


func make_draw_pile() -> Array[Card]:
	return cards()
