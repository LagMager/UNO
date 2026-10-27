extends Control

const Encounter = preload("res://scripts/game/encounter.gd")
const EnemyProfiles = preload("res://scripts/game/enemy_profiles.gd")
const RewardSystem = preload("res://scripts/game/reward_system.gd")
const CardViewControl = preload("res://scripts/game/card_view.gd")
const CARD_VIEW = preload("res://scenes/game/card_view.tscn")
const ENEMY_COLOR := Color("#696969")
const HIT_COLOR := Color("#b75656")
const BETWEEN_FIGHT_RECOVERY := 3

var encounter
var _mode := ""
var _run_index := 0
var _combat_view: MarginContainer
var _selection_view: CenterContainer
var _enemy_choices: VBoxContainer

var _status_label: Label
var _progress_label: Label
var _pile_label: Label
var _enemy_label: Label
var _enemy_behavior_label: Label
var _enemy_health_label: Label
var _enemy_health: ProgressBar
var _enemy_rect: ColorRect
var _enemy_name: Label
var _hand_label: Label
var _hand_row: HBoxContainer
var _hand_holder: CenterContainer
var _hand_scroll: ScrollContainer
var _color_row: HBoxContainer
var _reward_container: VBoxContainer
var _reward_row: HBoxContainer
var _reward_choices: Array[Card] = []
var _reward_resolved := false
var _last_rendered_result := ""
var _draw_button: Button
var _restart_button: Button
var _deck_button: Button
var _deck_dialog: AcceptDialog
var _next_button: Button
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
	_build_selection_ui()
	_render()
	_show_selection()
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
	_combat_view = margin
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
	_progress_label = Label.new()
	hud.add_child(_progress_label)
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
	_enemy_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_enemy_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_stack.add_child(_enemy_rect)
	_enemy_name = Label.new()
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_enemy_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_enemy_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_rect.add_child(_enemy_name)
	_enemy_health_label = Label.new()
	_enemy_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_stack.add_child(_enemy_health_label)
	_enemy_health = ProgressBar.new()
	_enemy_health.name = "EnemyHealth"
	_enemy_health.custom_minimum_size = Vector2(220, 16)
	_enemy_health.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_enemy_health.max_value = Encounter.STARTING_HEALTH
	_enemy_health.show_percentage = false
	_enemy_health.add_theme_stylebox_override("background", _box(Color("#333333"), Color("#777777")))
	_enemy_health.add_theme_stylebox_override("fill", _box(HIT_COLOR))
	enemy_stack.add_child(_enemy_health)

	_reward_container = VBoxContainer.new()
	_reward_container.name = "RewardContainer"
	_reward_container.visible = false
	_reward_container.add_theme_constant_override("separation", 6)
	enemy_stack.add_child(_reward_container)
	var reward_title := Label.new()
	reward_title.text = "Victory Reward — Choose 1 card to add to your deck (or Skip):"
	reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_container.add_child(reward_title)
	_reward_row = HBoxContainer.new()
	_reward_row.name = "RewardRow"
	_reward_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_reward_row.add_theme_constant_override("separation", 8)
	_reward_container.add_child(_reward_row)

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
	_enemy_behavior_label = Label.new()
	_enemy_behavior_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_column.add_child(_enemy_behavior_label)
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
	_hand_scroll.custom_minimum_size.y = 146
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
	for color: Card.CardColor in Encounter.COLORS:
		var choice := Button.new()
		choice.text = "Choose " + Card.color_to_string(color)
		choice.pressed.connect(_on_color_chosen.bind(color))
		_color_row.add_child(choice)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.add_child(actions)
	_restart_button = Button.new()
	_restart_button.text = "Restart encounter"
	_restart_button.pressed.connect(_on_restart_pressed)
	actions.add_child(_restart_button)
	_deck_button = Button.new()
	_deck_button.name = "DeckButton"
	_deck_button.pressed.connect(_on_deck_pressed)
	actions.add_child(_deck_button)
	var back := Button.new()
	back.text = "Choose mode"
	back.pressed.connect(_show_selection)
	actions.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_next_button = Button.new()
	_next_button.text = "Next encounter"
	_next_button.pressed.connect(_advance_run)
	actions.add_child(_next_button)
	_draw_button = Button.new()
	_draw_button.name = "DrawButton"
	_draw_button.text = "Draw 1 and end turn"
	_draw_button.pressed.connect(_on_draw_pressed)
	actions.add_child(_draw_button)
	_deck_dialog = AcceptDialog.new()
	_deck_dialog.title = "Your deck"
	add_child(_deck_dialog)


func _build_selection_ui() -> void:
	_selection_view = CenterContainer.new()
	_selection_view.name = "EncounterSelection"
	_selection_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_selection_view)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 390
	panel.add_theme_stylebox_override("panel", _box(Color("#414141"), Color("#777777")))
	_selection_view.add_child(panel)
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(padding)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	padding.add_child(choices)
	var prompt := Label.new()
	prompt.text = "Choose a combat test"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 20)
	choices.add_child(prompt)
	var choose_enemy := Button.new()
	choose_enemy.text = "Choose an enemy"
	choose_enemy.pressed.connect(func() -> void: _enemy_choices.visible = not _enemy_choices.visible)
	choices.add_child(choose_enemy)
	_enemy_choices = VBoxContainer.new()
	_enemy_choices.name = "EnemyChoices"
	_enemy_choices.visible = false
	choices.add_child(_enemy_choices)
	for id in EnemyProfiles.ORDER:
		var profile: Dictionary = EnemyProfiles.get_profile(id)
		var button := Button.new()
		button.text = "%s — %s" % [profile["name"], profile["description"]]
		button.custom_minimum_size.y = 42
		button.pressed.connect(_start_single.bind(id))
		_enemy_choices.add_child(button)
	var run_button := Button.new()
	run_button.name = "ThreeEncounters"
	run_button.text = "Play 3 encounters"
	run_button.custom_minimum_size.y = 48
	run_button.pressed.connect(_start_run)
	choices.add_child(run_button)
	var run_details := Label.new()
	run_details.text = "Standard → Aggressor → Trickster · Recover 3 HP between wins"
	run_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	run_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choices.add_child(run_details)


func _show_selection() -> void:
	_clear_hit_effects()
	_combat_view.visible = false
	_selection_view.visible = true
	_enemy_choices.visible = false


func _start_single(id: String) -> void:
	_mode = "single"
	_run_index = 0
	encounter.player_deck.reset_to_starter()
	_begin_encounter(id, Encounter.STARTING_HEALTH)


func _start_run() -> void:
	_mode = "run"
	_run_index = 0
	encounter.player_deck.reset_to_starter()
	_begin_encounter(EnemyProfiles.ORDER[0], Encounter.STARTING_HEALTH)


func _advance_run() -> void:
	if _mode != "run" or encounter.result != "Victory" or _run_index >= EnemyProfiles.ORDER.size() - 1:
		return
	var next_health: int = mini(encounter.player_health + BETWEEN_FIGHT_RECOVERY, Encounter.STARTING_HEALTH)
	_run_index += 1
	_begin_encounter(EnemyProfiles.ORDER[_run_index], next_health)


func _begin_encounter(id: String, health: int) -> void:
	if not encounter.start_encounter(id, health):
		return
	_reward_choices.clear()
	_reward_resolved = false
	_last_rendered_result = ""
	_clear_hit_effects()
	_selection_view.visible = false
	_combat_view.visible = true
	_render()


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
	if encounter.result == "Victory" and _last_rendered_result != "Victory":
		_reward_choices = RewardSystem.generate_card_rewards(RewardSystem.DEFAULT_REWARD_COUNT)
		_reward_resolved = false
	elif encounter.result != "Victory":
		_reward_choices.clear()
		_reward_resolved = false
	_last_rendered_result = encounter.result

	var status: String = encounter.result.to_upper() if encounter.phase == "finished" else "Round %d — Your turn" % (encounter.completed_rounds + 1)
	if _mode == "run" and encounter.phase == "finished":
		if encounter.result == "Defeat":
			status = "RUN ENDED — DEFEAT"
		elif _run_index == EnemyProfiles.ORDER.size() - 1:
			status = "RUN COMPLETE — VICTORY"
	_status_label.text = "%s  |  Your HP: %d" % [status, maxi(encounter.player_health, 0)]
	var profile: Dictionary = encounter.enemy_profile()
	_progress_label.text = "Encounter %d / %d · %s" % [_run_index + 1, EnemyProfiles.ORDER.size(), profile["name"]] if _mode == "run" else "Single encounter · %s" % profile["name"]
	_enemy_name.text = profile["name"].to_upper()
	var status_color := Color.WHITE
	if encounter.result == "Victory":
		status_color = Color.LIGHT_GREEN
	elif encounter.result == "Defeat":
		status_color = Color.SALMON
	_status_label.add_theme_color_override("font_color", status_color)
	_pile_label.text = "Top card: %s  |  Active color: %s  |  Draw pile: %d" % [
		encounter.card_label(encounter.top_card()), encounter.active_color_name(), encounter.draw_pile.size()
	]
	_enemy_label.text = "Enemy cards: %d" % encounter.enemy_hand.size()
	var rounds_until_attack: int = profile["attack_interval"] - encounter.completed_rounds % profile["attack_interval"]
	_enemy_behavior_label.text = "Attack: %d damage in %d round%s\nUNO: %s" % [
		profile["attack_damage"], rounds_until_attack, "" if rounds_until_attack == 1 else "s",
		"action cards first" if profile["prioritize_actions"] else "first playable card"
	]
	_enemy_health.max_value = profile["health"]
	_enemy_health.value = maxi(encounter.enemy_health, 0)
	_enemy_health_label.text = "Enemy HP  %d / %d" % [maxi(encounter.enemy_health, 0), profile["health"]]
	_hand_label.text = "Your hand (%d cards)" % encounter.player_hand.size()
	_restart_button.text = "Restart run" if _mode == "run" else "Restart encounter"
	_deck_button.text = "Deck (%d)" % encounter.player_deck.size()
	_next_button.visible = _mode == "run" and encounter.result == "Victory" and _run_index < EnemyProfiles.ORDER.size() - 1
	_draw_button.disabled = encounter.phase != "player"
	_color_row.visible = false
	_pending_wild_index = -1
	_render_rewards()
	for child in _hand_row.get_children():
		_hand_row.remove_child(child)
		child.queue_free()
	for index: int in range(encounter.player_hand.size()):
		var card: Card = encounter.player_hand[index]
		var button := CARD_VIEW.instantiate() as CardViewControl
		_hand_row.add_child(button)
		button.show_card(card)
		button.disabled = encounter.phase != "player" or not encounter.can_play(card)
		button.pressed.connect(_on_card_pressed.bind(index))
	_log_label.text = "\n\n".join(encounter.events)
	_update_layout()


func _render_rewards() -> void:
	for child in _reward_row.get_children():
		_reward_row.remove_child(child)
		child.queue_free()

	var show_rewards: bool = encounter.result == "Victory" and not _reward_resolved and not _reward_choices.is_empty()
	_reward_container.visible = show_rewards
	if not show_rewards:
		return

	for index: int in range(_reward_choices.size()):
		var reward_card: Card = _reward_choices[index]
		var button := CARD_VIEW.instantiate() as CardViewControl
		button.custom_minimum_size = Vector2(124, 136)
		_reward_row.add_child(button)
		var details: String = RewardSystem.describe_card(reward_card).trim_prefix("%d DMG" % reward_card.get_damage()).trim_prefix(" · ")
		button.show_card(reward_card, details)
		button.pressed.connect(_on_reward_selected.bind(index))

	var skip_button := Button.new()
	skip_button.name = "SkipRewardButton"
	skip_button.text = "Skip"
	skip_button.custom_minimum_size = Vector2(72, 56)
	skip_button.pressed.connect(_on_reward_skipped)
	_reward_row.add_child(skip_button)


func _on_reward_selected(index: int) -> void:
	if _reward_resolved or index < 0 or index >= _reward_choices.size():
		return
	var chosen_card: Card = _reward_choices[index]
	if RewardSystem.claim_reward(encounter.player_deck, chosen_card):
		_reward_resolved = true
		encounter.events.push_front("Reward: Added %s to your deck." % chosen_card.get_label())
		_render()


func _on_reward_skipped() -> void:
	if _reward_resolved:
		return
	_reward_resolved = true
	encounter.events.push_front("Reward: Skipped card reward.")
	_render()


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


func _play_card(index: int, color: Card.CardColor = Card.CardColor.WILD) -> void:
	var previous_health: int = encounter.enemy_health
	if encounter.play_player_card(index, color):
		_render()
		var damage: int = maxi(previous_health - encounter.enemy_health, 0)
		if damage > 0:
			_show_hit(damage)


func _on_card_pressed(index: int) -> void:
	if _pending_wild_index >= 0 or encounter.phase != "player" or index < 0 or index >= encounter.player_hand.size():
		return
	if encounter.player_hand[index].kind == Card.Kind.WILD:
		_pending_wild_index = index
		_color_row.visible = true
		_draw_button.disabled = true
		for child in _hand_row.get_children():
			child.disabled = true
		return
	_play_card(index)


func _on_color_chosen(color_arg: Variant) -> void:
	var resolved_color: Card.CardColor = _parse_color_arg(color_arg)
	if _pending_wild_index >= 0 and _pending_wild_index < encounter.player_hand.size() and encounter.player_hand[_pending_wild_index].kind == Card.Kind.WILD:
		_play_card(_pending_wild_index, resolved_color)


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


func _on_draw_pressed() -> void:
	if _pending_wild_index >= 0:
		return
	encounter.draw_player_card()
	_render()


func _on_deck_pressed() -> void:
	var counts := {}
	for card: Card in encounter.player_deck.cards():
		var label: String = card.get_label()
		counts[label] = counts.get(label, 0) + 1
	var lines: Array[String] = []
	for color: Card.CardColor in CardSystem.STANDARD_COLORS:
		var color_name: String = Card.color_to_string(color)
		var numbers: Array[String] = []
		for number: int in range(CardSystem.NUMBER_COUNT):
			var label := "%s %d" % [color_name, number]
			if counts.has(label):
				numbers.append("%d%s" % [number, " ×%d" % counts[label] if counts[label] > 1 else ""])
		var actions: Array[String] = []
		for kind: Card.Kind in [Card.Kind.REPLAY, Card.Kind.SKIP]:
			var sample_card := Card.new(color, kind)
			var label: String = sample_card.get_label()
			var kind_title: String = "Replay" if kind == Card.Kind.REPLAY else "Skip"
			if counts.has(label):
				actions.append("%s ×%d" % [kind_title, counts[label]])
		lines.append("%s: %s" % [color_name, ", ".join(numbers)])
		if not actions.is_empty():
			lines.append("    %s" % ", ".join(actions))
	if counts.has("Wild"):
		lines.append("Wild ×%d" % counts["Wild"])
	_deck_dialog.dialog_text = "Cards in your collection: %d\n\n%s\n\nUsed to build each encounter's shared draw pile." % [
		encounter.player_deck.size(), "\n".join(lines)
	]
	_deck_dialog.popup_centered(Vector2i(460, 320))


func _clear_hit_effects() -> void:
	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()
	_enemy_rect.color = ENEMY_COLOR
	for popup in _damage_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	_damage_popups.clear()


func _on_restart_pressed() -> void:
	if _mode == "run":
		_start_run()
	elif _mode == "single":
		_start_single(encounter.enemy_id)
