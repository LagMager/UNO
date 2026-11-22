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
	view = RestPointViewScript.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(view)
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
	_hint.text = "Drag to look around · R to recenter"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.modulate = Color(0.85, 0.8, 0.7, 0.6)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_back.position = Vector2(size.x - _back.custom_minimum_size.x - 16, size.y - _back.custom_minimum_size.y - 16)
	_hint.position = Vector2(16, size.y - 32)
