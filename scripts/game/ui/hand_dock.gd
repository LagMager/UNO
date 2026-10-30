extends VBoxContainer

signal card_play_requested(index: int, wild_color: Card.CardColor)
signal draw_requested
signal restart_requested
signal deck_requested
signal mode_select_requested
signal next_encounter_requested

const Encounter = preload("res://scripts/game/encounter.gd")
const RunSessionScript = preload("res://scripts/game/run_session.gd")
const CardViewControl = preload("res://scripts/game/card_view.gd")
const CARD_VIEW = preload("res://scenes/game/card_view.tscn")

@onready var hand_label: Label = $HandLabel
@onready var hand_scroll: ScrollContainer = $HandScroll
@onready var hand_holder: CenterContainer = $HandScroll/HandHolder
@onready var hand_row: HBoxContainer = $HandScroll/HandHolder/HandRow
@onready var color_row: HBoxContainer = $ColorCenter/ColorRow
@onready var restart_button: Button = $Actions/RestartButton
@onready var deck_button: Button = $Actions/DeckButton
@onready var choose_mode_button: Button = $Actions/ChooseModeButton
@onready var next_button: Button = $Actions/NextButton
@onready var draw_button: Button = $Actions/DrawButton

var pending_wild_index := -1
var _current_session: RefCounted


func _ready() -> void:
	hand_scroll.resized.connect(update_hand_width)
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	deck_button.pressed.connect(func() -> void: deck_requested.emit())
	choose_mode_button.pressed.connect(func() -> void: mode_select_requested.emit())
	next_button.pressed.connect(func() -> void: next_encounter_requested.emit())
	draw_button.pressed.connect(request_draw)
	_build_color_choices()


func render_dock(session: RefCounted) -> void:
	_current_session = session
	var encounter = session.encounter
	hand_label.text = "Your hand (%d cards)" % encounter.player_hand.size()
	restart_button.text = "Restart run" if session.mode in [RunSessionScript.MODE_RUN, RunSessionScript.MODE_MAP] else "Restart encounter"
	deck_button.text = "Deck (%d)" % encounter.player_deck.size()
	next_button.text = "Return to map" if session.mode == RunSessionScript.MODE_MAP else "Next encounter"
	next_button.visible = session.can_advance_run()
	draw_button.disabled = encounter.phase != Encounter.PHASE_PLAYER
	color_row.visible = false
	pending_wild_index = -1

	for child in hand_row.get_children():
		hand_row.remove_child(child)
		child.queue_free()

	for index: int in range(encounter.player_hand.size()):
		var card: Card = encounter.player_hand[index]
		var button := CARD_VIEW.instantiate() as CardViewControl
		hand_row.add_child(button)
		button.show_card(card)
		button.disabled = encounter.phase != Encounter.PHASE_PLAYER or not encounter.can_play(card)
		button.pressed.connect(press_card.bind(index))

	update_hand_width()


func update_hand_width() -> void:
	if hand_holder and hand_scroll:
		hand_holder.custom_minimum_size.x = hand_scroll.size.x


func press_card(index: int) -> void:
	if _current_session == null:
		return
	var encounter = _current_session.encounter
	if pending_wild_index >= 0 or encounter.phase != Encounter.PHASE_PLAYER or index < 0 or index >= encounter.player_hand.size():
		return
	if encounter.player_hand[index].kind == Card.Kind.WILD:
		pending_wild_index = index
		color_row.visible = true
		draw_button.disabled = true
		for child in hand_row.get_children():
			child.disabled = true
		return
	card_play_requested.emit(index, Card.CardColor.WILD)


func choose_wild_color(color_arg: Variant) -> void:
	if _current_session == null:
		return
	var encounter = _current_session.encounter
	var resolved_color: Card.CardColor = _parse_color_arg(color_arg)
	if pending_wild_index >= 0 and pending_wild_index < encounter.player_hand.size() and encounter.player_hand[pending_wild_index].kind == Card.Kind.WILD:
		var index_to_play := pending_wild_index
		card_play_requested.emit(index_to_play, resolved_color)


func request_draw() -> void:
	if pending_wild_index >= 0:
		return
	draw_requested.emit()


func _build_color_choices() -> void:
	for child in color_row.get_children():
		color_row.remove_child(child)
		child.queue_free()
	for color: Card.CardColor in Encounter.COLORS:
		var choice := Button.new()
		choice.text = "Choose " + Card.color_to_string(color)
		choice.pressed.connect(choose_wild_color.bind(color))
		color_row.add_child(choice)


func _parse_color_arg(color_arg: Variant) -> Card.CardColor:
	if color_arg is int:
		return color_arg as Card.CardColor
	if color_arg is String:
		match color_arg:
			"Red":
				return Card.CardColor.RED
			"Yellow":
				return Card.CardColor.YELLOW
			"Green":
				return Card.CardColor.GREEN
			"Blue":
				return Card.CardColor.BLUE
	return Card.CardColor.WILD
