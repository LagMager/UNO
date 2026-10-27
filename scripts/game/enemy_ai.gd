extends RefCounted

## Chooses enemy UNO actions. Encounter supplies the authoritative legality rule
## and remains responsible for validating and resolving the chosen action.


static func choose_card(hand: Array[Card], can_play: Callable, prioritize_actions: bool) -> int:
	var first_playable: int = -1
	for index: int in range(hand.size()):
		if not can_play.call(hand[index]):
			continue
		if first_playable == -1:
			first_playable = index
		if prioritize_actions and hand[index].kind in [Card.Kind.REPLAY, Card.Kind.SKIP]:
			return index
	return first_playable


static func choose_wild_color(remaining_hand: Array[Card]) -> Card.CardColor:
	var best_color: Card.CardColor = CardSystem.STANDARD_COLORS[0]
	var best_count: int = -1
	for color: Card.CardColor in CardSystem.STANDARD_COLORS:
		var count: int = 0
		for card: Card in remaining_hand:
			if card != null and card.color == color:
				count += 1
		if count > best_count:
			best_count = count
			best_color = color
	return best_color
