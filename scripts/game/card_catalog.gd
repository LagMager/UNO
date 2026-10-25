extends RefCounted

## Card rules and deck balance. Hands and piles keep small card dictionaries so the
## encounter can move cards without creating a separate node for each one.

const COLORS: Array[String] = ["Red", "Yellow", "Green", "Blue"]
const NUMBER_COUNT := 10
const TYPES := {
	"number": {"copies_per_color": 1, "damage": 1, "extra_actions": 0, "skip_next_uno": false, "label": ""},
	"replay": {"copies_per_color": 2, "damage": 1, "extra_actions": 1, "skip_next_uno": false, "label": "Replay"},
	"skip": {"copies_per_color": 2, "damage": 1, "extra_actions": 0, "skip_next_uno": true, "label": "Skip"},
	"wild": {"copies": 4, "damage": 1, "extra_actions": 0, "skip_next_uno": false, "label": "Wild"},
}


static func make_card(color: String, kind: String, number: int = -1) -> Dictionary:
	return {"color": color, "kind": kind, "number": number}


static func make_deck() -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	for color in COLORS:
		for number in range(NUMBER_COUNT):
			deck.append(make_card(color, "number", number))
		for kind in TYPES:
			if kind == "number" or kind == "wild":
				continue
			for copy in range(TYPES[kind]["copies_per_color"]):
				deck.append(make_card(color, kind))
	for copy in range(TYPES["wild"]["copies"]):
		deck.append(make_card("Wild", "wild"))
	return deck


static func label(card: Dictionary) -> String:
	var kind: String = card["kind"]
	if kind == "number":
		return "%s %d" % [card["color"], card["number"]]
	if kind == "wild":
		return TYPES[kind]["label"]
	return "%s %s" % [card["color"], TYPES[kind]["label"]]


static func damage(card: Dictionary) -> int:
	return TYPES[card["kind"]]["damage"]


static func extra_actions(card: Dictionary) -> int:
	return TYPES[card["kind"]]["extra_actions"]


static func skips_next_uno(card: Dictionary) -> bool:
	return TYPES[card["kind"]]["skip_next_uno"]
