class_name WildPicker
extends Control

## Input layer for choosing a Wild's color. It draws nothing: the choice lives in
## the 3D duel scene (the card in front of the player's face and four plain color
## slabs under it, see DuelView.wild_show). This control only catches the mouse.
## Right click (or Esc) puts the card back.

signal color_chosen(color: Card.CardColor)
signal cancelled

const COLORS := [Card.CardColor.RED, Card.CardColor.YELLOW, Card.CardColor.GREEN, Card.CardColor.BLUE]

var duel: Node   # DuelView
var _locked := true
var _hover := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## from: the Wild's rect in the hand (global), hand_index: its position in the hand.
func open(from: Rect2 = Rect2(), hand_index: int = -1) -> void:
	visible = true
	_locked = true
	_hover = -1
	var start := from.get_center() if from.size != Vector2.ZERO else Vector2(size.x * 0.5, size.y - 90)
	duel.wild_show(start - duel.get_global_rect().position, hand_index)
	await get_tree().create_timer(0.6).timeout
	_locked = false


func _duel_pos(global_pos: Vector2) -> Vector2:
	return global_pos - duel.get_global_rect().position


func _gui_input(event: InputEvent) -> void:
	accept_event()
	if _locked or not (event is InputEventMouse):
		return
	var local := _duel_pos(get_global_transform() * (event as InputEventMouse).position)
	if event is InputEventMouseMotion:
		_hover = duel.wild_pick(local)
		duel.wild_hover(_hover)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var h: int = duel.wild_pick(local)
			if h >= 0:
				_choose(h)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and not _locked and event.is_action_pressed("ui_cancel"):
		_cancel()


func _cancel() -> void:
	_locked = true
	visible = false
	duel.wild_cancel()
	cancelled.emit()


func _choose(i: int) -> void:
	_locked = true
	duel.wild_choose(i)
	await get_tree().create_timer(0.3).timeout
	visible = false
	color_chosen.emit(COLORS[i])
