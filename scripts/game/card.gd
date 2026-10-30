# Place this file at: res://scripts/game/card.gd
class_name Card
extends Resource

enum CardColor {
	RED,
	YELLOW,
	GREEN,
	BLUE,
	WILD,
	BLANK,
}

enum Kind {
	NUMBER,
	REPLAY,
	SKIP,
	WILD,
}

@export var instance_id: String = ""
@export var color: CardColor = CardColor.RED
@export var kind: Kind = Kind.NUMBER
@export var number: int = -1
@export var is_upgraded: bool = false
@export var bonus_damage: int = 0
@export var extra_actions: int = 0
@export var skips_next_uno: bool = false
@export var modifier: String = "none"


func _init(p_color: CardColor = CardColor.RED, p_kind: Kind = Kind.NUMBER, p_number: int = -1) -> void:
	color = p_color
	kind = p_kind
	number = p_number if p_kind == Kind.NUMBER else -1

	if p_kind == Kind.WILD:
		color = CardColor.WILD
	elif p_kind == Kind.REPLAY:
		extra_actions = 1
	elif p_kind == Kind.SKIP:
		skips_next_uno = true

	instance_id = "card_%d_%d" % [Time.get_ticks_usec(), get_instance_id()]


func get_damage() -> int:
	var base_damage: int = 1
	var upgrade_bonus: int = 2 if is_upgraded else 0
	return base_damage + bonus_damage + upgrade_bonus


func get_label() -> String:
	var prefix: String = "+" if is_upgraded else ""
	if kind == Kind.WILD:
		return "%sWild" % prefix

	var color_name: String = color_to_string(color)
	match kind:
		Kind.NUMBER:
			return "%s%s %d" % [prefix, color_name, number]
		Kind.REPLAY:
			return "%s%s Replay" % [prefix, color_name]
		Kind.SKIP:
			return "%s%s Skip" % [prefix, color_name]
		_:
			return "%s%s" % [prefix, color_name]


func upgrade() -> void:
	is_upgraded = true


func clone() -> Card:
	var copy := Card.new(color, kind, number)
	copy.instance_id = instance_id
	copy.is_upgraded = is_upgraded
	copy.bonus_damage = bonus_damage
	copy.extra_actions = extra_actions
	copy.skips_next_uno = skips_next_uno
	copy.modifier = modifier
	return copy


static func color_to_string(c: CardColor) -> String:
	match c:
		CardColor.RED:
			return "Red"
		CardColor.YELLOW:
			return "Yellow"
		CardColor.GREEN:
			return "Green"
		CardColor.BLUE:
			return "Blue"
		CardColor.WILD:
			return "Wild"
		CardColor.BLANK:
			return "Blank"
		_:
			return "Unknown"
