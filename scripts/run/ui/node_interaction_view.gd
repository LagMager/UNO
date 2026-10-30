class_name NodeInteractionView
extends CenterContainer

## Declarative interaction view for Safe Room, Shop, and Decision map nodes.
## Delegates gameplay state changes through RunState or DecisionRunner and emits
## interaction_finished when the player completes the node.

signal interaction_finished(pending_encounter: EncounterData)

const RewardSystem = preload("res://scripts/game/reward_system.gd")

var _run_state: RunState = null
var _active_shop_data: ShopData = null
var _shop_cards: Array[Card] = []
var _shop_purchased_indices: Array[int] = []
var _decision_runner: RefCounted = null

@onready var type_label: Label = $Panel/Margin/Column/TypeLabel
@onready var title_label: Label = $Panel/Margin/Column/TitleLabel
@onready var stats_label: Label = $Panel/Margin/Column/StatsLabel
@onready var description_label: Label = $Panel/Margin/Column/DescriptionLabel
@onready var feedback_label: Label = $Panel/Margin/Column/FeedbackLabel
@onready var options_container: VBoxContainer = $Panel/Margin/Column/OptionsContainer
@onready var continue_button: Button = $Panel/Margin/Column/ContinueButton


func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)


func open_safe_room(run_state: RunState, rest_data: RestSiteData) -> void:
	_run_state = run_state
	_decision_runner = null
	var data: RestSiteData = rest_data if rest_data != null else RestSiteData.new()

	type_label.text = "SAFE ROOM"
	title_label.text = data.display_name
	description_label.text = data.description
	feedback_label.text = ""
	feedback_label.visible = false
	continue_button.text = "Return to map"
	continue_button.visible = true
	_refresh_stats()
	_clear_options()

	var rest_btn := Button.new()
	rest_btn.name = "RestHealButton"
	rest_btn.custom_minimum_size.y = 40
	rest_btn.text = "Rest — Recover %d HP" % data.heal_amount
	rest_btn.pressed.connect(func() -> void:
		var healed: int = _run_state.modify_health(data.heal_amount)
		_show_feedback("Recovered %d HP." % healed)
		_disable_all_options()
		_refresh_stats()
	)
	options_container.add_child(rest_btn)

	if data.allow_card_upgrade:
		var upgrade_btn := Button.new()
		upgrade_btn.name = "RestUpgradeButton"
		upgrade_btn.custom_minimum_size.y = 40
		upgrade_btn.text = "Forge — Upgrade a card in your deck (+2 DMG)"
		upgrade_btn.pressed.connect(func() -> void:
			var upgraded: Card = _run_state.player_deck.upgrade_first_unupgraded()
			if upgraded != null:
				_show_feedback("Upgraded card to %s!" % upgraded.get_label())
			else:
				_show_feedback("All cards in your deck are already upgraded.")
			_disable_all_options()
			_refresh_stats()
		)
		options_container.add_child(upgrade_btn)


func open_shop(run_state: RunState, shop_data: ShopData) -> void:
	_run_state = run_state
	_decision_runner = null
	_active_shop_data = shop_data if shop_data != null else ShopData.new()

	type_label.text = "SHOP"
	title_label.text = _active_shop_data.display_name
	description_label.text = _active_shop_data.description
	feedback_label.text = ""
	feedback_label.visible = false
	continue_button.text = "Leave shop"
	continue_button.visible = true

	_shop_cards = RewardSystem.generate_card_rewards(maxi(_active_shop_data.card_slot_count, 1))
	_shop_purchased_indices.clear()
	_render_shop_options(_active_shop_data)


func open_decision(run_state: RunState, decision_data: DecisionData, runner: RefCounted = null) -> void:
	_run_state = run_state
	_decision_runner = runner

	if _decision_runner != null and _decision_runner.has_method("start"):
		_decision_runner.start(decision_data, run_state)
		_render_active_decision_from_runner()
		return

	# Placeholder fallback when DecisionRunner is not supplied
	var data: DecisionData = decision_data if decision_data != null else DecisionData.new()
	type_label.text = "DECISION / EVENT"
	title_label.text = data.title
	description_label.text = data.description
	feedback_label.text = ""
	feedback_label.visible = false
	continue_button.text = "Continue to map"
	continue_button.visible = true
	_refresh_stats()
	_clear_options()


func select_option_index(index: int) -> bool:
	if index < 0 or index >= options_container.get_child_count():
		return false
	var btn := options_container.get_child(index) as Button
	if btn == null or btn.disabled:
		return false
	btn.pressed.emit()
	return true


func finish_interaction() -> void:
	_on_continue_pressed()


func _render_active_decision_from_runner() -> void:
	_refresh_stats()
	_clear_options()

	var current_decision: DecisionData = _decision_runner.current_decision
	type_label.text = "DECISION / EVENT"
	title_label.text = current_decision.title if current_decision != null else "Event"
	description_label.text = current_decision.description if current_decision != null else ""

	if not _decision_runner.last_outcome_description.is_empty():
		_show_feedback(_decision_runner.last_outcome_description)
	else:
		feedback_label.visible = false

	if _decision_runner.is_finished:
		continue_button.text = "Enter combat" if _decision_runner.pending_encounter != null else "Return to map"
		continue_button.visible = true
		return

	continue_button.visible = false
	var states: Array[Dictionary] = _decision_runner.get_choice_states()
	if states.is_empty():
		continue_button.text = "Return to map"
		continue_button.visible = true
		return

	for index: int in range(states.size()):
		var info: Dictionary = states[index]
		var choice_btn := Button.new()
		choice_btn.name = "ChoiceButton_%d" % index
		choice_btn.custom_minimum_size.y = 42
		choice_btn.text = str(info["text"])
		choice_btn.disabled = not bool(info["available"])
		choice_btn.pressed.connect(func() -> void:
			if _decision_runner.choose(index):
				_render_active_decision_from_runner()
		)
		options_container.add_child(choice_btn)


func _render_shop_options(data: ShopData) -> void:
	_refresh_stats()
	_clear_options()

	for index: int in range(_shop_cards.size()):
		var card: Card = _shop_cards[index]
		var already_bought: bool = _shop_purchased_indices.has(index)
		var buy_btn := Button.new()
		buy_btn.name = "BuyCardButton_%d" % index
		buy_btn.custom_minimum_size.y = 38
		var summary: String = RewardSystem.describe_card(card)
		buy_btn.text = "Sold — %s" % card.get_label() if already_bought else "Buy %s (%s) — %d Gold" % [card.get_label(), summary, data.base_card_price]
		buy_btn.disabled = already_bought or not _run_state.can_afford(data.base_card_price)
		buy_btn.pressed.connect(_on_shop_buy_card.bind(index))
		options_container.add_child(buy_btn)

	if data.heal_amount > 0:
		var heal_btn := Button.new()
		heal_btn.name = "ShopHealButton"
		heal_btn.custom_minimum_size.y = 38
		heal_btn.text = "Heal %d HP — %d Gold" % [data.heal_amount, data.heal_price]
		heal_btn.disabled = not _run_state.can_afford(data.heal_price) or _run_state.current_health >= _run_state.max_health
		heal_btn.pressed.connect(_on_shop_heal)
		options_container.add_child(heal_btn)


func _on_shop_buy_card(index: int) -> void:
	if _active_shop_data == null or index < 0 or index >= _shop_cards.size():
		return
	if _shop_purchased_indices.has(index) or not _run_state.can_afford(_active_shop_data.base_card_price):
		return
	var card: Card = _shop_cards[index]
	_run_state.modify_gold(-_active_shop_data.base_card_price)
	_run_state.player_deck.add_card(card)
	_shop_purchased_indices.append(index)
	_show_feedback("Purchased %s!" % card.get_label())
	_render_shop_options(_active_shop_data)


func _on_shop_heal() -> void:
	if _active_shop_data == null or not _run_state.can_afford(_active_shop_data.heal_price):
		return
	_run_state.modify_gold(-_active_shop_data.heal_price)
	var healed: int = _run_state.modify_health(_active_shop_data.heal_amount)
	_show_feedback("Restored %d HP." % healed)
	_render_shop_options(_active_shop_data)


func _refresh_stats() -> void:
	if _run_state == null:
		stats_label.text = ""
		return
	stats_label.text = "HP: %d / %d  |  Gold: %d  |  Deck: %d cards" % [
		maxi(_run_state.current_health, 0),
		_run_state.max_health,
		_run_state.gold,
		_run_state.player_deck.size()
	]


func _show_feedback(message: String) -> void:
	feedback_label.text = message
	feedback_label.visible = not message.is_empty()


func _clear_options() -> void:
	for child in options_container.get_children():
		options_container.remove_child(child)
		child.queue_free()


func _disable_all_options() -> void:
	for child in options_container.get_children():
		if child is Button:
			child.disabled = true


func _on_continue_pressed() -> void:
	var pending_enc: EncounterData = null
	if _decision_runner != null and _decision_runner.get("pending_encounter") != null:
		pending_enc = _decision_runner.pending_encounter as EncounterData
	_clear_options()
	_shop_cards.clear()
	_active_shop_data = null
	_decision_runner = null
	interaction_finished.emit(pending_enc)
