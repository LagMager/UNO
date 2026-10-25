extends Control

const Encounter = preload("res://scripts/game/encounter.gd")
const ENEMY_COLOR := Color("#696969")
const HIT_COLOR := Color("#b75656")

var encounter

var _status_label: Label
var _pile_label: Label
var _enemy_label: Label
var _enemy_health_label: Label
var _enemy_health: ProgressBar
var _enemy_rect: ColorRect
var _hand_label: Label
var _hand_row: HBoxContainer
var _hand_holder: CenterContainer
var _hand_scroll: ScrollContainer
var _color_row: HBoxContainer
var _draw_button: Button
var _log_label: RichTextLabel
var _log_panel: PanelContainer
var _content: VBoxContainer
var _battle_row: HBoxContainer
var _side_spacer: Control
var _hit_tween: Tween
var _damage_popups: Array[Label] = []
var _pending_wild_index := -1


func _ready() -> void:
	encounter = Encounter.new()
	_build_ui()
	_render()
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _box(fill: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(5)
	return style


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var hud := VBoxContainer.new()
	hud.add_theme_constant_override("separation", 4)
	column.add_child(hud)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 19)
	hud.add_child(_status_label)
	_pile_label = Label.new()
	hud.add_child(_pile_label)

	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	column.add_child(_content)
	_battle_row = HBoxContainer.new()
	_battle_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_battle_row)
	_side_spacer = Control.new()
	_side_spacer.custom_minimum_size.x = 270
	_battle_row.add_child(_side_spacer)

	var stage := CenterContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battle_row.add_child(stage)
	var enemy_stack := VBoxContainer.new()
	enemy_stack.add_theme_constant_override("separation", 10)
	stage.add_child(enemy_stack)
	_enemy_rect = ColorRect.new()
	_enemy_rect.name = "Enemy"
	_enemy_rect.color = ENEMY_COLOR
	_enemy_rect.custom_minimum_size = Vector2(220, 180)
	_enemy_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_stack.add_child(_enemy_rect)
	var enemy_name := Label.new()
	enemy_name.text = "ENEMY"
	enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	enemy_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	enemy_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_rect.add_child(enemy_name)
	_enemy_health_label = Label.new()
	_enemy_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_stack.add_child(_enemy_health_label)
	_enemy_health = ProgressBar.new()
	_enemy_health.name = "EnemyHealth"
	_enemy_health.custom_minimum_size = Vector2(220, 16)
	_enemy_health.max_value = Encounter.STARTING_HEALTH
	_enemy_health.show_percentage = false
	_enemy_health.add_theme_stylebox_override("background", _box(Color("#333333"), Color("#777777")))
	_enemy_health.add_theme_stylebox_override("fill", _box(HIT_COLOR))
	enemy_stack.add_child(_enemy_health)

	_log_panel = PanelContainer.new()
	_log_panel.name = "ActionLog"
	_log_panel.custom_minimum_size = Vector2(270, 130)
	_log_panel.add_theme_stylebox_override("panel", _box(Color("#414141"), Color("#626262")))
	_battle_row.add_child(_log_panel)
	var log_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		log_margin.add_theme_constant_override("margin_" + side, 12)
	_log_panel.add_child(log_margin)
	var log_column := VBoxContainer.new()
	log_column.add_theme_constant_override("separation", 6)
	log_margin.add_child(log_column)
	var history_title := Label.new()
	history_title.text = "Recent actions"
	history_title.add_theme_font_size_override("font_size", 16)
	log_column.add_child(history_title)
	_enemy_label = Label.new()
	log_column.add_child(_enemy_label)
	_log_label = RichTextLabel.new()
	_log_label.name = "Entries"
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_column.add_child(_log_label)

	var dock := VBoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	column.add_child(dock)
	_hand_label = Label.new()
	_hand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dock.add_child(_hand_label)
	_hand_scroll = ScrollContainer.new()
	_hand_scroll.custom_minimum_size.y = 112
	_hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dock.add_child(_hand_scroll)
	_hand_scroll.resized.connect(_update_hand_width)
	_hand_holder = CenterContainer.new()
	_hand_scroll.add_child(_hand_holder)
	_hand_row = HBoxContainer.new()
	_hand_row.name = "HandRow"
	_hand_row.add_theme_constant_override("separation", 8)
	_hand_holder.add_child(_hand_row)

	var color_center := CenterContainer.new()
	dock.add_child(color_center)
	_color_row = HBoxContainer.new()
	_color_row.visible = false
	_color_row.add_theme_constant_override("separation", 6)
	color_center.add_child(_color_row)
	for color in Encounter.COLORS:
		var choice := Button.new()
		choice.text = "Choose " + color
		choice.pressed.connect(_on_color_chosen.bind(color))
		_color_row.add_child(choice)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.add_child(actions)
	var restart := Button.new()
	restart.text = "Restart encounter"
	restart.pressed.connect(_on_restart_pressed)
	actions.add_child(restart)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_draw_button = Button.new()
	_draw_button.name = "DrawButton"
	_draw_button.text = "Draw 1 and end turn"
	_draw_button.pressed.connect(_on_draw_pressed)
	actions.add_child(_draw_button)


func _update_layout() -> void:
	var narrow := get_window().size.x < 900
	_side_spacer.visible = not narrow
	if narrow and _log_panel.get_parent() != _content:
		_log_panel.reparent(_content)
	elif not narrow and _log_panel.get_parent() != _battle_row:
		_log_panel.reparent(_battle_row)
	_log_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if narrow else Control.SIZE_EXPAND_FILL
	_log_panel.custom_minimum_size.y = 120 if narrow else 130
	_update_hand_width()


func _update_hand_width() -> void:
	_hand_holder.custom_minimum_size.x = _hand_scroll.size.x


func _render() -> void:
	var status: String = encounter.result.to_upper() if encounter.phase == "finished" else "Round %d — Your turn" % (encounter.completed_rounds + 1)
	_status_label.text = "%s  |  Your HP: %d" % [status, maxi(encounter.player_health, 0)]
	var status_color := Color.WHITE
	if encounter.result == "Victory":
		status_color = Color.LIGHT_GREEN
	elif encounter.result == "Defeat":
		status_color = Color.SALMON
	_status_label.add_theme_color_override("font_color", status_color)
	_pile_label.text = "Top card: %s  |  Active color: %s  |  Draw pile: %d" % [
		encounter.card_label(encounter.top_card()), encounter.active_color, encounter.draw_pile.size()
	]
	_enemy_label.text = "Enemy cards: %d" % encounter.enemy_hand.size()
	_enemy_health.value = maxi(encounter.enemy_health, 0)
	_enemy_health_label.text = "Enemy HP  %d / %d" % [maxi(encounter.enemy_health, 0), Encounter.STARTING_HEALTH]
	_hand_label.text = "Your hand (%d cards)" % encounter.player_hand.size()
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
		button.custom_minimum_size = Vector2(112, 98)
		button.add_theme_stylebox_override("normal", _box(Color("#353535"), Color("#6c6c6c")))
		button.add_theme_stylebox_override("hover", _box(Color("#505050"), Color("#aaaaaa")))
		button.add_theme_stylebox_override("pressed", _box(Color("#777777"), Color("#dddddd")))
		button.add_theme_stylebox_override("disabled", _box(Color("#363636"), Color("#484848")))
		button.disabled = encounter.phase != "player" or not encounter.can_play(card)
		button.pressed.connect(_on_card_pressed.bind(index))
		_hand_row.add_child(button)
	_log_label.text = "\n\n".join(encounter.events)
	_update_layout()


func _show_hit(damage: int) -> void:
	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()
	_enemy_rect.color = ENEMY_COLOR
	_hit_tween = create_tween()
	_hit_tween.tween_property(_enemy_rect, "color", HIT_COLOR, 0.08)
	_hit_tween.tween_property(_enemy_rect, "color", ENEMY_COLOR, 0.25)

	var popup := Label.new()
	popup.text = "-%d" % damage
	popup.add_theme_font_size_override("font_size", 32)
	popup.add_theme_color_override("font_color", Color("#ffd4d4"))
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_rect.add_child(popup)
	_damage_popups.append(popup)
	popup.position = Vector2((_enemy_rect.size.x - 60) * 0.5, _enemy_rect.size.y * 0.45)
	var float_tween := popup.create_tween().set_parallel(true)
	float_tween.tween_property(popup, "position:y", popup.position.y - 62, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	float_tween.tween_property(popup, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	float_tween.chain().tween_callback(_finish_popup.bind(popup))


func _finish_popup(popup: Label) -> void:
	_damage_popups.erase(popup)
	popup.queue_free()


func _play_card(index: int, color: String = "") -> void:
	var previous_health: int = encounter.enemy_health
	if encounter.play_player_card(index, color):
		_render()
		var damage: int = maxi(previous_health - encounter.enemy_health, 0)
		if damage > 0:
			_show_hit(damage)


func _on_card_pressed(index: int) -> void:
	if _pending_wild_index >= 0 or encounter.phase != "player" or index < 0 or index >= encounter.player_hand.size():
		return
	if encounter.player_hand[index]["kind"] == "wild":
		_pending_wild_index = index
		_color_row.visible = true
		_draw_button.disabled = true
		for child in _hand_row.get_children():
			child.disabled = true
		return
	_play_card(index)


func _on_color_chosen(color: String) -> void:
	if _pending_wild_index >= 0 and _pending_wild_index < encounter.player_hand.size() and encounter.player_hand[_pending_wild_index]["kind"] == "wild":
		_play_card(_pending_wild_index, color)


func _on_draw_pressed() -> void:
	if _pending_wild_index >= 0:
		return
	encounter.draw_player_card()
	_render()


func _on_restart_pressed() -> void:
	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()
	_enemy_rect.color = ENEMY_COLOR
	for popup in _damage_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	_damage_popups.clear()
	encounter.new_game()
	_render()
