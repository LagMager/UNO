extends Control

const Encounter = preload("res://scripts/game/encounter.gd")

var encounter

var _status_label: Label
var _enemy_label: Label
var _pile_label: Label
var _hand_label: Label
var _hand_row: HFlowContainer
var _color_row: HBoxContainer
var _draw_button: Button
var _log_label: RichTextLabel
var _pending_wild_index := -1


func _ready() -> void:
	encounter = Encounter.new()
	_build_ui()
	_render()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "UNO Combat Prototype"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)

	_status_label = Label.new()
	column.add_child(_status_label)
	_enemy_label = Label.new()
	column.add_child(_enemy_label)
	_pile_label = Label.new()
	column.add_child(_pile_label)

	var separator := HSeparator.new()
	column.add_child(separator)

	_hand_label = Label.new()
	column.add_child(_hand_label)
	var hand_scroll := ScrollContainer.new()
	hand_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(hand_scroll)
	_hand_row = HFlowContainer.new()
	_hand_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_row.add_theme_constant_override("h_separation", 8)
	_hand_row.add_theme_constant_override("v_separation", 8)
	hand_scroll.add_child(_hand_row)

	_color_row = HBoxContainer.new()
	_color_row.visible = false
	column.add_child(_color_row)
	for color in Encounter.COLORS:
		var choice := Button.new()
		choice.text = "Choose " + color
		choice.pressed.connect(_on_color_chosen.bind(color))
		_color_row.add_child(choice)

	var actions := HBoxContainer.new()
	column.add_child(actions)
	_draw_button = Button.new()
	_draw_button.text = "Draw 1 and end turn"
	_draw_button.pressed.connect(_on_draw_pressed)
	actions.add_child(_draw_button)
	var restart := Button.new()
	restart.text = "Restart encounter"
	restart.pressed.connect(_on_restart_pressed)
	actions.add_child(restart)

	var history_title := Label.new()
	history_title.text = "Recent actions"
	column.add_child(history_title)
	_log_label = RichTextLabel.new()
	_log_label.custom_minimum_size = Vector2(0, 150)
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log_label)


func _render() -> void:
	_status_label.text = "%s  |  Your HP: %d  |  Enemy HP: %d" % [
		encounter.result if encounter.phase == "finished" else "Round %d" % (encounter.completed_rounds + 1),
		maxi(encounter.player_health, 0),
		maxi(encounter.enemy_health, 0)
	]
	_enemy_label.text = "Enemy cards: %d  |  Draw pile: %d" % [encounter.enemy_hand.size(), encounter.draw_pile.size()]
	_pile_label.text = "Top card: %s  |  Active color: %s  |  Completed rounds: %d" % [
		encounter.card_label(encounter.top_card()), encounter.active_color, encounter.completed_rounds
	]
	_hand_label.text = "Your hand (%d cards):" % encounter.player_hand.size()
	_draw_button.disabled = encounter.phase != "player"
	_color_row.visible = false
	_pending_wild_index = -1
	for child in _hand_row.get_children():
		_hand_row.remove_child(child)
		child.queue_free()
	for index in range(encounter.player_hand.size()):
		var card: Dictionary = encounter.player_hand[index]
		var button := Button.new()
		button.text = encounter.card_label(card)
		button.custom_minimum_size = Vector2(110, 56)
		button.disabled = encounter.phase != "player" or not encounter.can_play(card)
		button.pressed.connect(_on_card_pressed.bind(index))
		_hand_row.add_child(button)
	_log_label.text = "\n".join(encounter.events)


func _on_card_pressed(index: int) -> void:
	if encounter.player_hand[index]["kind"] == "wild":
		_pending_wild_index = index
		_color_row.visible = true
		return
	encounter.play_player_card(index)
	_render()


func _on_color_chosen(color: String) -> void:
	if _pending_wild_index >= 0:
		encounter.play_player_card(_pending_wild_index, color)
	_render()


func _on_draw_pressed() -> void:
	encounter.draw_player_card()
	_render()


func _on_restart_pressed() -> void:
	encounter.new_game()
	_render()
