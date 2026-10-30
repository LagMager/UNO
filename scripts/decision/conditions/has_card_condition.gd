class_name HasCardCondition
extends ConditionData

## Condition requiring the player's deck to contain a matching card.

@export var card_color: Card.CardColor = Card.CardColor.WILD
@export var card_kind: Card.Kind = Card.Kind.WILD
@export var card_number: int = -1


func _init(
	p_color: Card.CardColor = Card.CardColor.WILD,
	p_kind: Card.Kind = Card.Kind.WILD,
	p_number: int = -1
) -> void:
	card_color = p_color
	card_kind = p_kind
	card_number = p_number


func is_met(run_state: RunState) -> bool:
	if run_state == null or run_state.player_deck == null:
		return false
	return run_state.player_deck.has_matching_card(card_color, card_kind, card_number)


func describe() -> String:
	if card_kind == Card.Kind.WILD:
		return "Requires Wild card"
	var sample := Card.new(card_color, card_kind, card_number)
	return "Requires %s" % sample.get_label()
