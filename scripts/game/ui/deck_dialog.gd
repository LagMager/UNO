class_name DeckDialog
extends AcceptDialog


func open_for_deck(player_deck: RefCounted) -> void:
	dialog_text = format_deck_summary(player_deck)
	popup_centered(Vector2i(460, 320))


static func format_deck_summary(player_deck: RefCounted) -> String:
	var counts := {}
	for card: Card in player_deck.cards():
		var label: String = card.get_label()
		counts[label] = counts.get(label, 0) + 1
	var lines: Array[String] = []
	for color: Card.CardColor in CardSystem.STANDARD_COLORS:
		var color_name: String = Card.color_to_string(color)
		var numbers: Array[String] = []
		for number: int in range(CardSystem.NUMBER_COUNT):
			var label := "%s %d" % [color_name, number]
			if counts.has(label):
				numbers.append("%d%s" % [number, " ×%d" % counts[label] if counts[label] > 1 else ""])
		var actions: Array[String] = []
		for kind: Card.Kind in [Card.Kind.REPLAY, Card.Kind.SKIP]:
			var sample_card := Card.new(color, kind)
			var label: String = sample_card.get_label()
			var kind_title: String = "Replay" if kind == Card.Kind.REPLAY else "Skip"
			if counts.has(label):
				actions.append("%s ×%d" % [kind_title, counts[label]])
		lines.append("%s: %s" % [color_name, ", ".join(numbers)])
		if not actions.is_empty():
			lines.append("    %s" % ", ".join(actions))
	if counts.has("Wild"):
		lines.append("Wild ×%d" % counts["Wild"])
	return "Cards in your collection: %d\n\n%s\n\nUsed to build each encounter's shared draw pile." % [
		player_deck.size(),
		"\n".join(lines)
	]
