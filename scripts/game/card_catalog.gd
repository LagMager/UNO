extends RefCounted

const COLORS: Array[String] = ["Red", "Yellow", "Green", "Blue", "Wild"]
const NUMBER_COUNT := 10

const TYPES := {
	"number": {"base_damage": 1, "extra_actions": 0, "skip_next_uno": false, "label": ""},
	"replay": {"base_damage": 1, "extra_actions": 1, "skip_next_uno": false, "label": "Replay"},
	"skip": {"base_damage": 1, "extra_actions": 0, "skip_next_uno": true, "label": "Skip"},
	"wild": {"base_damage": 1, "extra_actions": 0, "skip_next_uno": false, "label": "Wild"},
}

# Keep a counter to generate unique instance IDs
static var _id_counter: int = 0

static func _generate_instance_id() -> String:
	_id_counter += 1
	return "card_%d_%d" % [Time.get_ticks_msec(), _id_counter]


## Creates a unique card instance for a deck or hand
static func make_card_instance(color: String, kind: String, number: int = -1) -> Dictionary:
	return {
		"instance_id": _generate_instance_id(),
		"color": color,
		"kind": kind,
		"number": number,
		"upgraded": false,
		"bonus_damage": 0,
		"modifier": "none" # e.g., "foil", "holographic", "polychrome" (Balatro style)
	}


static func is_valid_card(card: Dictionary) -> bool:
	if not card.has("instance_id") or not card.has("color") or not card.has("kind") or not card.has("number"):
		return false
	if not card["color"] is String or not card["kind"] is String or not card["number"] is int:
		return false
	var kind: String = card["kind"]
	if not TYPES.has(kind):
		return false
	if kind == "wild":
		return card["color"] == "Wild" and card["number"] == -1
	if not COLORS.has(card["color"]):
		return false
	if kind == "number":
		return card["number"] >= 0 and card["number"] < NUMBER_COUNT
	return card["number"] == -1


static func make_starting_deck() -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	for color in COLORS:
		if color == "Wild":
			continue
		for number in range(NUMBER_COUNT):
			deck.append(make_card_instance(color, "number", number))
		for kind in TYPES:
			if kind == "number" or kind == "wild":
				continue
			deck.append(make_card_instance(color, kind))
	for i in range(4):
		deck.append(make_card_instance("Wild", "wild"))
	return deck


static func label(card: Dictionary) -> String:
	var kind: String = card["kind"]
	var prefix = "+ " if card.get("upgraded", false) else ""

	if kind == "number":
		return "%s%s %d" % [prefix, card["color"], card["number"]]
	if kind == "wild":
		return TYPES[kind]["label"]
	return "%s%s %s" % [prefix, card["color"], TYPES[kind]["label"]]


static func damage(card: Dictionary) -> int:
	var kind: String = card["kind"]
	var base = TYPES[kind]["base_damage"]
	var bonus = card.get("bonus_damage", 0)
	var upgrade_bonus = 2 if card.get("upgraded", false) else 0
	return base + bonus + upgrade_bonus


static func extra_actions(card: Dictionary) -> int:
	return TYPES[card["kind"]]["extra_actions"]


static func skips_next_uno(card: Dictionary) -> bool:
	return TYPES[card["kind"]]["skip_next_uno"]
