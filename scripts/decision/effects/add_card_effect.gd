class_name AddCardEffect
extends EffectData

## Clones and adds a configured Card resource to the player's persistent deck.

@export var card_template: Card = null


func _init(p_card_template: Card = null) -> void:
	card_template = p_card_template


func apply(run_state: RunState, _context: Dictionary) -> void:
	if run_state == null or run_state.player_deck == null or card_template == null:
		return
	run_state.player_deck.add_card(card_template.clone())
