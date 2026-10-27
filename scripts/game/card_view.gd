class_name CardView
extends Button

@onready var _name_label: Label = $Content/Labels/Name
@onready var _type_color_label: Label = $Content/Labels/TypeColor
@onready var _damage_label: Label = $Content/Labels/Damage
@onready var _details_label: Label = $Content/Labels/Details


func show_card(card: Card, details: String = "") -> void:
	_name_label.text = card.get_label()
	_type_color_label.text = "%s · %s" % [_kind_name(card.kind), Card.color_to_string(card.color)]
	_damage_label.text = "%d DMG" % card.get_damage()
	_details_label.text = details
	_details_label.visible = not details.is_empty()
	tooltip_text = "%s — %s — %d DMG" % [card.get_label(), _type_color_label.text, card.get_damage()]
	if not details.is_empty():
		tooltip_text += " — %s" % details


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
