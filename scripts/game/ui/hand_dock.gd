extends VBoxContainer

signal card_play_requested(index: int, wild_color: Card.CardColor)
signal draw_requested
signal restart_requested
signal deck_requested
signal mode_select_requested
signal next_encounter_requested
## A Wild card was clicked: the screen should ask for its color.
signal wild_requested(from: Rect2, hand_index: int)

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
## 0 = cards gathered in a fan, 1 = spread out (only while the mouse is over the hand)
var spread := 0.0
## While locked (a round is being shown) the cards and the draw button ignore clicks.
var locked := false
const GATHERED_SEPARATION := -84.0
const SPREAD_SEPARATION := -60.0
const FAN_ANGLE := 0.42
const LIFT := 36.0
var _hovered := -1
var _time := 0.0


func _ready() -> void:
	hand_scroll.resized.connect(update_hand_width)
	hand_scroll.clip_contents = false
	hand_row.sort_children.connect(_apply_fan)
	hand_row.add_theme_constant_override("separation", int(GATHERED_SEPARATION))
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

	if locked:
		_apply_lock()
	update_hand_width()


func set_locked(value: bool) -> void:
	locked = value
	if _current_session != null and not value:
		render_dock(_current_session)
	elif value:
		_apply_lock()


func _apply_lock() -> void:
	draw_button.disabled = true
	for child in hand_row.get_children():
		if child is Button:
			child.disabled = true


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
		color_row.visible = false
		draw_button.disabled = true
		var src := hand_row.get_child(index) as Control if index < hand_row.get_child_count() else null
		wild_requested.emit(src.get_global_rect() if src != null else Rect2(), index)
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


func _process(delta: float) -> void:
	_time += delta
	var over := false
	if hand_row.get_child_count() > 0:
		var zone := hand_row.get_global_rect().grow(28)
		over = zone.has_point(get_global_mouse_position())
	var target := 1.0 if over and not locked and pending_wild_index < 0 else 0.0
	var previous := spread
	spread = move_toward(spread, target, delta * 5.0)
	if not is_equal_approx(previous, spread):
		var eased := spread * spread * (3.0 - 2.0 * spread)
		hand_row.add_theme_constant_override("separation", int(lerpf(GATHERED_SEPARATION, SPREAD_SEPARATION, eased)))
	_apply_fan()


func _apply_fan() -> void:
	# A held fan: it only opens a little when the mouse is over it, and the card
	# under the cursor is pulled up out of the fan (it straightens as it rises).
	# While a round is being shown (locked) or a Wild is pending, nothing reacts.
	var count := hand_row.get_child_count()
	var top := -1
	if not locked and pending_wild_index < 0:
		top = _card_under_mouse()
	_hovered = top
	for i: int in range(count):
		var card := hand_row.get_child(i) as Button
		if card == null:
			continue
		var u := 0.0 if count == 1 else float(i) / (count - 1) - 0.5
		card.pivot_offset = Vector2(card.size.x * 0.5, card.size.y * 1.9)
		var pulled := i == top and not card.disabled
		var k := 1.0 if pulled else 0.0
		var eased := spread * spread * (3.0 - 2.0 * spread)
		var fan_rot := u * FAN_ANGLE * (1.0 + 0.3 * eased)
		var target_rot := lerpf(fan_rot, fan_rot * 0.35, k) + sin(_time * 1.6 + i * 0.9) * 0.008
		card.rotation = lerpf(card.rotation, target_rot, 0.25)
		var target_y := -LIFT * k - sin(_time * 2.1 + i * 1.3) * 1.5
		card.position.y = lerpf(card.position.y, target_y, 0.25)
		card.scale = card.scale.lerp(Vector2.ONE * (1.06 if pulled else 1.0), 0.25)


## The card under the mouse, tested in each card's own (rotated) space against
## its resting shape, so a card rising under the cursor doesn't drop and flicker.
func _card_under_mouse() -> int:
	var mouse := get_global_mouse_position()
	var count := hand_row.get_child_count()
	# keep the current one while the mouse is still over where it rests
	if _hovered >= 0 and _hovered < count and _hit(hand_row.get_child(_hovered) as Control, mouse, LIFT + 6.0):
		return _hovered
	for i: int in range(count - 1, -1, -1):  # last drawn = on top
		if _hit(hand_row.get_child(i) as Control, mouse, 0.0):
			return i
	return -1


func _hit(card: Control, mouse: Vector2, extra_bottom: float) -> bool:
	if card == null:
		return false
	var local := card.get_global_transform().affine_inverse() * mouse
	return Rect2(Vector2.ZERO, card.size + Vector2(0, extra_bottom)).has_point(local)


## The Wild was put back: the hand is usable again.
func cancel_wild() -> void:
	pending_wild_index = -1
	if _current_session != null:
		render_dock(_current_session)
