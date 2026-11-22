class_name ZoneScreen
extends Control

## Shows a zone on its own from the main menu, to look at how it is built:
## the 3D view, the film grain on top and a way back. Drag to look around, R recenters.

signal closed

const RestPointViewScript = preload("res://scripts/zones/rest_point_view.gd")

var view: SubViewportContainer
var _back: Button
var _hint: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_show_circle(RestPointViewScript.Circle.MESQUITE)
	var film := ColorRect.new()
	film.set_anchors_preset(Control.PRESET_FULL_RECT)
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://resources/shaders/film_look.gdshader")
	film.material = fm
	add_child(film)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(120, 42)
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(func() -> void: closed.emit())
	add_child(_back)
	_hint = Label.new()
	_hint.text = "Drag to look around · R to recenter · 1 2 3 change circle"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.modulate = Color(0.85, 0.8, 0.7, 0.6)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	# which circle's rest to look at
	_circles = HBoxContainer.new()
	_circles.add_theme_constant_override("separation", 8)
	_circles.position = Vector2(16, 16)
	add_child(_circles)
	for i: int in range(CIRCLE_NAMES.size()):
		var b := Button.new()
		b.text = CIRCLE_NAMES[i]
		b.toggle_mode = true
		b.button_pressed = i == 0
		b.custom_minimum_size = Vector2(110, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_show_circle.bind(i))
		_circles.add_child(b)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_back.position = Vector2(size.x - _back.custom_minimum_size.x - 16, size.y - _back.custom_minimum_size.y - 16)
	_hint.position = Vector2(16, size.y - 32)


const CIRCLE_NAMES := ["Mesquite", "Limbo", "Lust"]
var _circles: HBoxContainer


## The rest is built for one circle, so changing it builds the place again.
func _show_circle(circle: int) -> void:
	if view != null:
		view.queue_free()
	view = RestPointViewScript.new()
	view.circle = circle
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	move_child(view, 0)
	if _circles != null:
		for i: int in range(_circles.get_child_count()):
			(_circles.get_child(i) as Button).set_pressed_no_signal(i == circle)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and event is InputEventKey:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_3:
			_show_circle(k - KEY_1)
