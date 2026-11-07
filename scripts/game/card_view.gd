class_name CardView
extends Button

const FACES_DIR := "res://assets/cards/faces/"
const UPGRADED_COLOR := Color("#f2c46a")
const BONUS_COLOR := Color("#efe2c4")

static var _face_cache: Dictionary = {}

@onready var _name_label: Label = $Content/Labels/Name
@onready var _type_color_label: Label = $Content/Labels/TypeColor
@onready var _damage_label: Label = $Content/Labels/Damage
@onready var _details_label: Label = $Content/Labels/Details


func show_card(card: Card, details: String = "") -> void:
	icon = face_for(card)
	set_meta("card", card)
	_name_label.text = card.get_label()
	_type_color_label.text = "%s · %s" % [_kind_name(card.kind), Card.color_to_string(card.color)]
	_damage_label.text = "%d DMG" % card.get_damage()
	# The art already shows suit and value; only call out boosted damage.
	_damage_label.visible = card.get_damage() != 1 or card.is_upgraded
	_damage_label.add_theme_color_override("font_color", UPGRADED_COLOR if card.is_upgraded else BONUS_COLOR)
	_details_label.text = details
	_details_label.visible = not details.is_empty()
	tooltip_text = ""


static func face_for(card: Card) -> Texture2D:
	return _load_face(face_name(card))


static func face_name(card: Card) -> String:
	if card.kind == Card.Kind.WILD or card.color == Card.CardColor.WILD:
		return "wild"
	var color_key: String = Card.color_to_string(card.color).to_lower()
	match card.kind:
		Card.Kind.REPLAY:
			return "%s_replay" % color_key
		Card.Kind.SKIP:
			return "%s_skip" % color_key
		_:
			return "%s_%d" % [color_key, clampi(card.number, 0, 9)]


static func back_texture() -> Texture2D:
	return _load_face("back")


static func _load_face(face: String) -> Texture2D:
	if not _face_cache.has(face):
		var path := FACES_DIR + face + ".png"
		_face_cache[face] = load(path) if ResourceLoader.exists(path) else null
	return _face_cache[face]


func _kind_name(kind: Card.Kind) -> String:
	match kind:
		Card.Kind.NUMBER:
			return "Number"
		Card.Kind.REPLAY:
			return "Replay"
		Card.Kind.SKIP:
			return "Skip"
		_:
			return "Wild"
