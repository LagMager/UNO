extends CanvasLayer

## A small note in the lower right corner whenever the run is saved: "Saving..." with a
## revolver cylinder turning, then "Saved", and it fades away. Above every screen.

const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const CREAM := Color("#e8dcc0")
const EMBER := Color(0.95, 0.45, 0.15)

var _box: PanelContainer
var _label: Label
var _wheel: Control
var _spin := 0.0
var _spinning := false
var _tween: Tween


func _ready() -> void:
	layer = 90
	_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.035, 0.03, 0.86)
	sb.border_color = Color(0.35, 0.22, 0.13)
	sb.set_border_width_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_box.add_theme_stylebox_override("panel", sb)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.modulate.a = 0.0
	add_child(_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	_wheel = Control.new()
	_wheel.custom_minimum_size = Vector2(22, 22)
	_wheel.draw.connect(_draw_wheel)
	row.add_child(_wheel)
	_label = Label.new()
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", CREAM)
	row.add_child(_label)
	get_viewport().size_changed.connect(_place)


func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	_box.reset_size()
	_box.position = vp - _box.size - Vector2(22, 22)


## The cylinder: six chambers round a pin, turning while it saves, still once it is done.
func _draw_wheel() -> void:
	var c := _wheel.size * 0.5
	var col := EMBER if _spinning else CREAM
	_wheel.draw_circle(c, 10.0, Color(col, 0.25))
	_wheel.draw_arc(c, 10.0, 0, TAU, 20, col, 1.5)
	for k: int in range(6):
		var a := _spin + k * TAU / 6.0
		var hole := c + Vector2(cos(a), sin(a)) * 6.0
		_wheel.draw_circle(hole, 2.2, Color(0.05, 0.035, 0.03) if k > 0 or not _spinning else col)
	_wheel.draw_circle(c, 1.6, col)


func _process(delta: float) -> void:
	if _spinning:
		# it keeps turning, four chambers a second
		_spin += delta * TAU / 6.0 * 4.0
		_wheel.queue_redraw()


## Shows the note: saving for a moment, then saved, then gone.
func show_saving() -> void:
	if _tween != null:
		_tween.kill()
	_label.text = "Saving..."
	_spinning = true
	_place()
	_tween = create_tween()
	_tween.tween_property(_box, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(0.9)
	_tween.tween_callback(func() -> void:
		_spinning = false
		_label.text = "Saved"
		_wheel.queue_redraw()
		_place())
	_tween.tween_interval(1.0)
	_tween.tween_property(_box, "modulate:a", 0.0, 0.6)


func is_showing() -> bool:
	return _box.modulate.a > 0.0
