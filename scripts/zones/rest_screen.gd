class_name RestScreen
extends Control

## The Safe Room node of the map, shown as the Rest Point: you walk in from the dark and sit
## by the fire, then the options appear. The rules stay in NodeInteractionView (heal, upgrade
## a card); this screen only mirrors its option buttons and acts them out (the fire swells).

const RestPointViewScript = preload("res://scripts/zones/rest_point_view.gd")
const CREAM := Color("#e8dcc0")
const DIM := Color("#9c8f78")
const INK := Color("#120d0b")
const ITALIC := preload("res://assets/fonts/SpecialElite-Regular.ttf")

var view: RestPointViewScript
var _iv: NodeInteractionView
var _ui: Control
var _fade: ColorRect
var _hp: Label
var _feedback: Label
var _options: VBoxContainer
var _leave: Button
var _leaving := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	view = RestPointViewScript.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.free_look = false
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	view.arrived.connect(_show_ui)
	var film := ColorRect.new()
	film.set_anchors_preset(Control.PRESET_FULL_RECT)
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://resources/shaders/film_look.gdshader")
	film.material = fm
	add_child(film)
	_build_ui()
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	visibility_changed.connect(_on_visibility)


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 36
	box.offset_top = -250
	box.offset_right = 520
	box.offset_bottom = -32
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(box)
	var title := _label(30, true)
	title.text = "The Rest Point"
	box.add_child(title)
	# the doc's own words for the place
	var lore := _label(17, false)
	lore.text = "Always night here. Better not make your stay too long."
	lore.add_theme_font_override("font", ITALIC)
	lore.add_theme_color_override("font_color", DIM)
	box.add_child(lore)
	_hp = _label(18, false)
	box.add_child(_hp)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	box.add_child(_options)
	_feedback = _label(20, false)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_feedback.anchor_left = 0.0
	_feedback.anchor_right = 1.0
	_feedback.offset_top = -150
	_feedback.offset_bottom = -116
	_feedback.modulate.a = 0.0
	_ui.add_child(_feedback)
	_leave = Button.new()
	_leave.text = "Move on"
	_leave.custom_minimum_size = Vector2(150, 44)
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_leave.offset_left = -186
	_leave.offset_top = -76
	_leave.offset_right = -36
	_leave.offset_bottom = -32
	_leave.pressed.connect(leave)
	_ui.add_child(_leave)


func _label(font_size: int, header: bool) -> Label:
	var l := Label.new()
	if header:
		l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", CREAM)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _on_visibility() -> void:
	if view != null and view.viewport != null:
		view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED


## Shows the safe room the interaction view has just opened: fade in, walk in, sit, choose.
func open(iv: NodeInteractionView) -> void:
	_iv = iv
	_leaving = false
	visible = true
	_ui.modulate.a = 0.0
	_ui.visible = false
	_feedback.modulate.a = 0.0
	_fade.modulate.a = 1.0
	_sync()
	view.play_arrival()
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 0.0, 1.2)


func close() -> void:
	visible = false


func leave() -> void:
	if _leaving or _iv == null:
		return
	_leaving = true
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", 1.0, 0.6)
	await t.finished
	_iv.finish_interaction()


func _show_ui() -> void:
	_ui.visible = true
	var t := create_tween()
	t.tween_property(_ui, "modulate:a", 1.0, 0.8)


## Mirrors the interaction view's options as our own buttons.
func _sync() -> void:
	if _iv == null:
		return
	var state := _iv.get_run_state()
	if state != null:
		_hp.text = "HP  %d / %d" % [maxi(state.current_health, 0), state.max_health]
	for c in _options.get_children():
		c.queue_free()
	var i := 0
	for child in _iv.options_container.get_children():
		var src := child as Button
		if src == null or src.is_queued_for_deletion():
			continue
		var b := Button.new()
		b.text = src.text
		b.disabled = src.disabled
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 42)
		b.focus_mode = Control.FOCUS_NONE
		var index := i
		b.pressed.connect(func() -> void: _choose(index))
		_options.add_child(b)
		i += 1


func _choose(index: int) -> void:
	if _iv == null or not _iv.select_option_index(index):
		return
	view.flare(0.9)
	_feedback.text = _iv.feedback_label.text
	var t := create_tween()
	t.tween_property(_feedback, "modulate:a", 1.0, 0.25)
	t.tween_interval(2.4)
	t.tween_property(_feedback, "modulate:a", 0.0, 0.8)
	_sync()


func _gui_input(event: InputEvent) -> void:
	# a click while walking in: straight to the seat
	if view.is_arriving() and event is InputEventMouseButton and event.pressed:
		view.skip_arrival()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and view.is_arriving() and event.pressed:
		view.skip_arrival()
		get_viewport().set_input_as_handled()
