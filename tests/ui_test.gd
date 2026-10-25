extends SceneTree

const Cards = preload("res://scripts/game/card_catalog.gd")

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

	var enemy: ColorRect = ui.find_child("Enemy", true, false)
	var bar: ProgressBar = ui.find_child("EnemyHealth", true, false)
	var log_panel: PanelContainer = ui.find_child("ActionLog", true, false)
	var hand: HBoxContainer = ui.find_child("HandRow", true, false)
	var draw_button: Button = ui.find_child("DrawButton", true, false)
	_check(enemy != null and bar != null and log_panel != null and hand != null and draw_button != null, "Combat UI elements should exist.")
	_check(absf(enemy.get_global_rect().get_center().x - ui.get_viewport_rect().size.x * 0.5) < 30.0, "Enemy should be centered on a wide screen.")
	_check(hand.get_global_rect().get_center().y > enemy.get_global_rect().get_center().y, "Cards should sit below the enemy.")
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
	ui.encounter.discard_pile.append(Cards.make_card("Red", "number", 1))
	ui.encounter.active_color = "Red"
	ui.encounter.player_hand.append(Cards.make_card("Red", "number", 2))
	ui.encounter.player_hand.append(Cards.make_card("Blue", "number", 3))
	ui.encounter.enemy_hand.append(Cards.make_card("Blue", "number", 4))
	ui._render()
	ui._on_card_pressed(0)
	_check(ui.encounter.enemy_health == 7 and bar.value == 7.0, "Card play should update enemy HP and bar immediately.")
	_check(ui._damage_popups.size() == 1 and ui._damage_popups[0].text == "-1", "Card play should create correct damage popup.")
	_check(ui._log_label.text.contains("Enemy takes 1 damage"), "Card damage should appear in the action log.")
	await create_timer(0.75).timeout
	_check(ui._damage_popups.is_empty(), "Damage popup should fade and be removed.")
	_check(enemy.color.is_equal_approx(Color("#696969")), "Enemy flash should return to gray.")
	ui.encounter.player_hand[0] = Cards.make_card("Red", "number", 3)
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

	if failures == 0:
		print("UI tests passed.")
	quit(1 if failures > 0 else 0)
