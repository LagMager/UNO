class_name PausePanel
extends Control

## Esc during a run: the screen dims and a small panel offers to go on, to copy the run's
## seed (to share or replay the same descent), or to go back to the main menu.

signal resume_requested
signal main_menu_requested

var _seed_label: Label
var _copied: Label
var _seed := 0


func _ready() -> void:
	# cover the whole screen (anchors AND offsets: with anchors alone it stayed at size zero,
	# and the panel ended up in the top-left corner)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_top = -150
	panel.offset_right = 200
	panel.offset_bottom = 150
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 30)
	col.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_seed_label = Label.new()
	_seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seed_label)
	var copy := Button.new()
	copy.text = "Copy"
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(str(_seed))
		_copied.modulate.a = 1.0
		create_tween().tween_property(_copied, "modulate:a", 0.0, 1.2).set_delay(0.8))
	row.add_child(copy)
	_copied = Label.new()
	_copied.text = "Seed copied."
	_copied.add_theme_font_size_override("font_size", 14)
	_copied.add_theme_color_override("font_color", Color(0.55, 0.5, 0.43, 1))
	_copied.modulate.a = 0.0
	col.add_child(_copied)
	for entry: Array in [["Resume", resume_requested], ["Main menu", main_menu_requested]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(0, 44)
		b.focus_mode = Control.FOCUS_NONE
		var sig: Signal = entry[1]
		b.pressed.connect(func() -> void: sig.emit())
		col.add_child(b)


func open(seed_value: int) -> void:
	_seed = seed_value
	_seed_label.text = "Seed  %d" % seed_value
	_copied.modulate.a = 0.0
	visible = true
