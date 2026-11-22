extends VBoxContainer

signal reward_selected(index: int)
signal reward_skipped

const RewardSystem = preload("res://scripts/game/reward_system.gd")
const CardViewControl = preload("res://scripts/game/card_view.gd")
const CARD_VIEW = preload("res://scenes/game/card_view.tscn")

@onready var reward_row: HBoxContainer = $RewardRow


func render_rewards(session: RefCounted) -> void:
	for child in reward_row.get_children():
		reward_row.remove_child(child)
		child.queue_free()

	var show_rewards: bool = session.has_active_rewards()
	visible = show_rewards
	if not show_rewards:
		return

	for index: int in range(session.reward_choices.size()):
		var reward_card: Card = session.reward_choices[index]
		var button := CARD_VIEW.instantiate() as CardViewControl
		button.custom_minimum_size = Vector2(124, 136)
		reward_row.add_child(button)
		var details: String = RewardSystem.describe_card(reward_card).trim_prefix("%d DMG" % reward_card.get_damage()).trim_prefix(" · ")
		button.show_card(reward_card, details)
		button.pressed.connect(select_reward.bind(index))

	var skip_button := Button.new()
	skip_button.name = "SkipRewardButton"
	skip_button.text = "Skip"
	skip_button.custom_minimum_size = Vector2(72, 56)
	skip_button.pressed.connect(skip_reward)
	reward_row.add_child(skip_button)


func select_reward(index: int) -> void:
	reward_selected.emit(index)


func skip_reward() -> void:
	reward_skipped.emit()
