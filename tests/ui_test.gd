extends SceneTree

const CardViewControl = preload("res://scripts/game/card_view.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/game/main.tscn")
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	_check(ui._selection_view.visible and not ui._combat_view.visible, "Selection should open before combat.")
	ui._enemy_choices.visible = true
	ui._start_single("standard")
	await process_frame
	await process_frame
	_check(ui._combat_view.visible and not ui._selection_view.visible, "Choosing an enemy should open combat.")

	var enemy: ColorRect = ui.find_child("Enemy", true, false)
	var bar: ProgressBar = ui.find_child("EnemyHealth", true, false)
	var log_panel: PanelContainer = ui.find_child("ActionLog", true, false)
	var hand: HBoxContainer = ui.find_child("HandRow", true, false)
	var draw_button: Button = ui.find_child("DrawButton", true, false)
	var deck_button: Button = ui.find_child("DeckButton", true, false)
	_check(enemy != null and bar != null and log_panel != null and hand != null and draw_button != null and deck_button != null, "Combat UI elements should exist.")
	_check(deck_button.text == "Deck (60)", "Deck button should show the collection size.")
	ui._on_deck_pressed()
	_check(ui._deck_dialog.dialog_text.contains("Wild ×4"), "Deck view should show the starter composition.")
	ui._deck_dialog.hide()
	_check(absf(enemy.get_global_rect().get_center().x - ui.get_viewport_rect().size.x * 0.5) < 30.0, "Enemy should be centered on a wide screen.")
	_check(hand.get_global_rect().get_center().y > enemy.get_global_rect().get_center().y, "Cards should sit below the enemy.")
	_check(hand.get_child_count() > 0 and hand.get_child(0) is CardViewControl, "Hand cards should use the reusable card scene.")
	var first_card: CardViewControl = hand.get_child(0)
	_check(first_card.find_child("Name").text != "" and first_card.find_child("TypeColor").text != "" and first_card.find_child("Damage").text.contains("DMG"), "Card scene should show name, type/color, and damage.")
	_check(absf(hand.get_global_rect().get_center().x - ui.get_viewport_rect().size.x * 0.5) < 30.0, "Cards should be centered on a wide screen.")
	_check(log_panel.get_global_rect().end.y < hand.get_global_rect().position.y, "Wide log should not overlap the cards.")
	_check(absf(draw_button.get_global_rect().end.x - (ui.get_viewport_rect().size.x - 24.0)) < 8.0, "Draw button should sit at the bottom right on a wide screen.")
	_check(draw_button.get_global_rect().position.y > hand.get_global_rect().position.y, "Draw button should sit below the cards.")
	_check(bar.value == 8.0, "Health bar should start full.")
	for label in ui.find_children("*", "Label", true, false):
		_check(label.text != "UNO Combat Prototype", "Title should be absent.")

	ui.encounter.draw_pile.clear()
	ui.encounter.discard_pile.clear()
	ui.encounter.player_hand.clear()
	ui.encounter.enemy_hand.clear()
	ui.encounter.discard_pile.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 1))
	ui.encounter.active_color = Card.CardColor.RED
	ui.encounter.player_hand.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 2))
	ui.encounter.player_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	ui.encounter.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 4))
	ui._render()
	_check(not hand.get_child(0).disabled and hand.get_child(1).disabled, "Card scene should reflect whether each hand card can be played.")
	ui._on_card_pressed(0)
	_check(ui.encounter.enemy_health == 7 and bar.value == 7.0, "Card play should update enemy HP and bar immediately.")
	_check(ui._damage_popups.size() == 1 and ui._damage_popups[0].text == "-1", "Card play should create correct damage popup.")
	_check(ui._log_label.text.contains("Enemy takes 1 damage"), "Card damage should appear in the action log.")
	await create_timer(0.75).timeout
	_check(ui._damage_popups.is_empty(), "Damage popup should fade and be removed.")
	_check(enemy.color.is_equal_approx(Color("#696969")), "Enemy flash should return to gray.")
	ui.encounter.player_hand[0] = Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 3)
	ui._render()
	ui._on_card_pressed(0)
	_check(ui._damage_popups.size() == 1, "Second hit should start its animation.")
	ui._on_restart_pressed()
	_check(ui._damage_popups.is_empty() and enemy.color.is_equal_approx(Color("#696969")), "Restart should clear active hit feedback.")

	root.size = Vector2i(640, 800)
	await process_frame
	await process_frame
	_check(log_panel.get_parent() == ui._content, "Log should move below enemy on narrow screens.")
	_check(absf(enemy.get_global_rect().get_center().x - ui.get_viewport_rect().size.x * 0.5) < 30.0, "Enemy should remain centered on narrow screens.")
	_check(hand.get_global_rect().get_center().y > enemy.get_global_rect().get_center().y, "Cards should remain below enemy on narrow screens.")
	_check(absf(hand.get_global_rect().get_center().x - ui.get_viewport_rect().size.x * 0.5) < 30.0, "Cards should be centered on a narrow screen.")
	_check(log_panel.get_global_rect().end.y < hand.get_global_rect().position.y, "Narrow log should not overlap the cards.")
	_check(absf(draw_button.get_global_rect().end.x - (ui.get_viewport_rect().size.x - 24.0)) < 8.0, "Draw button should stay at the bottom right on a narrow screen.")
	ui._show_selection()
	await process_frame
	await process_frame
	_check(ui._selection_view.visible and not ui._combat_view.visible, "Choose mode should return to selection.")
	var selection_panel: PanelContainer = ui._selection_view.get_child(0)
	_check(selection_panel.get_global_rect().position.x >= 0 and selection_panel.get_global_rect().end.x <= ui.get_viewport_rect().size.x, "Selection panel should fit the narrow window.")
	ui._start_single("trickster")
	_check(ui.encounter.enemy_id == "trickster" and ui._progress_label.text.contains("Trickster"), "Single enemy selection should use the chosen profile.")
	_force_victory(ui)
	_check(not ui._next_button.visible, "Single encounter victory should not offer a next fight.")
	_check(ui._reward_container.visible and ui._reward_choices.size() == 3, "Victory should present 3 card reward choices.")
	_check(ui._reward_row.get_child(0) is CardViewControl, "Reward choices should reuse the card scene.")
	await process_frame
	_check(ui._reward_row.get_global_rect().end.y < hand.get_global_rect().position.y, "Reward cards should fit above the hand on a narrow screen.")
	_check(is_equal_approx(enemy.size.x, 220.0) and is_equal_approx(bar.size.x, 220.0), "Victory rewards should not stretch the enemy or its health bar.")
	ui._on_reward_selected(0)
	_check(not ui._reward_container.visible and ui.encounter.player_deck.size() == 61, "Selecting a reward card should add it to the deck and close rewards.")
	ui._on_restart_pressed()
	_check(ui.encounter.enemy_id == "trickster" and ui.encounter.result == "", "Restart encounter should repeat the selected enemy.")
	_check(ui.encounter.player_deck.size() == 60, "Restarting a single encounter should restore the starter collection.")
	ui._start_run()
	_check(ui._run_index == 0 and ui.encounter.enemy_id == "standard", "Three-encounter mode should start with Standard.")
	_check(ui.encounter.player_deck.add_card(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 9)), "Run should allow a deck edit for persistence testing.")
	ui.encounter.player_health = 4
	_force_victory(ui)
	_check(ui._next_button.visible, "A run victory should offer the next encounter.")
	ui._advance_run()
	_check(ui._run_index == 1 and ui.encounter.enemy_id == "aggressor" and ui.encounter.player_health == 7, "Run should carry health and recover 3 HP.")
	_check(ui.encounter.player_deck.size() == 61 and ui.encounter.draw_pile.size() + ui.encounter.player_hand.size() + ui.encounter.enemy_hand.size() + ui.encounter.discard_pile.size() == 61, "Next fight should use the persistent edited collection.")
	_force_victory(ui)
	ui._advance_run()
	_check(ui._run_index == 2 and ui.encounter.enemy_id == "trickster", "Run should progress to the third profile.")
	_force_victory(ui)
	_check(not ui._next_button.visible and ui._status_label.text.contains("RUN COMPLETE"), "Third victory should complete the run.")
	ui._on_restart_pressed()
	_check(ui._run_index == 0 and ui.encounter.enemy_id == "standard" and ui.encounter.player_health == 8, "Restart run should return to the first encounter.")
	_check(ui.encounter.player_deck.size() == 60 and deck_button.text == "Deck (60)", "Restart run should restore the starter collection.")
	ui.encounter.player_health = 1
	ui.encounter.completed_rounds = 1
	ui.encounter.enemy_hand.clear()
	ui.encounter.enemy_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	ui.encounter.draw_pile.clear()
	ui.encounter.discard_pile.clear()
	ui.encounter.discard_pile.append(Card.new(Card.CardColor.RED, Card.Kind.NUMBER, 1))
	ui.encounter.active_color = Card.CardColor.RED
	ui._on_draw_pressed()
	_check(ui.encounter.result == "Defeat" and not ui._next_button.visible and ui._status_label.text.contains("RUN ENDED"), "Defeat should end the run without a next encounter.")

	if failures == 0:
		print("UI tests passed.")
	quit(1 if failures > 0 else 0)


func _force_victory(ui: Control) -> void:
	ui.encounter.enemy_health = 1
	ui.encounter.player_hand.clear()
	ui.encounter.player_hand.append(Card.new(Card.CardColor.WILD, Card.Kind.WILD))
	ui.encounter.player_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	ui._render()
	ui._on_card_pressed(0)
	ui._on_color_chosen(Card.CardColor.BLUE)
	_check(ui.encounter.result == "Victory", "Forced encounter should end in victory.")
