extends SceneTree

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

	# Build a deterministic 6-floor test map containing all 6 node types in sequence:
	# f0 (Encounter) -> f1 (Decision) -> f2 (Shop) -> f3 (Safe Room) -> f4 (Elite) -> f5 (Boss)
	var map := MapData.new(404, 6, "n_enc", "n_boss")
	var n_enc := MapNodeData.new("n_enc", MapEnums.NodeType.ENCOUNTER, 0, 0, EncounterData.new("enc_0", "standard", EncounterData.Tier.NORMAL))
	var n_dec := MapNodeData.new("n_dec", MapEnums.NodeType.DECISION, 1, 0, DecisionData.new("dec_1", "Crossroads", "A quiet shrine."))
	var n_shop := MapNodeData.new("n_shop", MapEnums.NodeType.SHOP, 2, 0, ShopData.new("shop_2"))
	var n_rest := MapNodeData.new("n_rest", MapEnums.NodeType.SAFE_ROOM, 3, 0, RestSiteData.new("rest_3", 3, true))
	var elite_data := EncounterData.new("elite_4", "aggressor", EncounterData.Tier.ELITE, "Elite Guard")
	elite_data.health_override = 10
	elite_data.gold_reward = 25
	var n_elite := MapNodeData.new("n_elite", MapEnums.NodeType.ELITE, 4, 0, elite_data)
	var boss_data := EncounterData.new("boss_5", "trickster", EncounterData.Tier.BOSS, "Grand Boss")
	boss_data.health_override = 12
	boss_data.gold_reward = 50
	var n_boss := MapNodeData.new("n_boss", MapEnums.NodeType.BOSS, 5, 0, boss_data)

	n_enc.add_connection("n_dec")
	n_dec.add_connection("n_shop")
	n_shop.add_connection("n_rest")
	n_rest.add_connection("n_elite")
	n_elite.add_connection("n_boss")
	for node: MapNodeData in [n_enc, n_dec, n_shop, n_rest, n_elite, n_boss]:
		map.add_node(node)

	var state: RunState = ui.run_controller.start_run_with_map(map, 8, 40)
	ui.map_view.bind_run_state(state)
	await process_frame

	_check(ui.map_view.visible and not ui.combat_view.visible and not ui.interaction_view.visible, "MapView should be shown at start of map run.")

	# 1. Select Encounter node -> routes to CombatView
	_check(ui.map_view.request_select_node("n_enc"), "Selecting start encounter node should succeed.")
	await process_frame
	_check(ui.combat_view.visible and not ui.map_view.visible, "Encounter node should route to CombatView.")
	ui.encounter.player_health = 5
	_force_combat_victory(ui)
	_check(ui.hand_dock.next_button.visible and ui.hand_dock.next_button.text == "Return to map", "Winning map encounter should display 'Return to map' button.")
	ui.advance_run()
	await process_frame
	_check(ui.map_view.visible and state.is_node_completed("n_enc") and state.current_health == 5 and state.gold == 55, "Completing encounter should sync HP (5), add gold (+15 -> 55), and return to MapView.")

	# 2. Select Decision node -> routes to NodeInteractionView
	_check(ui.map_view.request_select_node("n_dec"), "Selecting Decision node should succeed.")
	await process_frame
	_check(ui.interaction_view.visible and ui.interaction_view.type_label.text == "DECISION / EVENT", "Decision node should route to NodeInteractionView.")
	ui.interaction_view.finish_interaction()
	await process_frame
	_check(ui.map_view.visible and state.is_node_completed("n_dec"), "Completing Decision should return to MapView.")

	# 3. Select Shop node -> buy a card and return to MapView
	_check(ui.map_view.request_select_node("n_shop"), "Selecting Shop node should succeed.")
	await process_frame
	_check(ui.interaction_view.visible and ui.interaction_view.type_label.text == "SHOP", "Shop node should route to NodeInteractionView.")
	var deck_before_shop: int = state.player_deck.size()
	_check(ui.interaction_view.select_option_index(0), "Buying first shop card should succeed.")
	_check(state.player_deck.size() == deck_before_shop + 1 and state.gold == 30, "Shop purchase should add card to deck and spend 25 gold.")
	ui.interaction_view.finish_interaction()
	await process_frame
	_check(ui.map_view.visible and state.is_node_completed("n_shop"), "Leaving Shop should return to MapView.")

	# 4. Select Safe Room node -> heal +3 HP and return to MapView
	_check(ui.map_view.request_select_node("n_rest"), "Selecting Safe Room node should succeed.")
	await process_frame
	_check(ui.interaction_view.visible and ui.interaction_view.type_label.text == "SAFE ROOM", "Safe Room node should route to NodeInteractionView.")
	_check(ui.interaction_view.select_option_index(0), "Choosing Rest option should heal player.")
	_check(state.current_health == 8, "Safe Room rest should heal from 5 to 8 HP.")
	ui.interaction_view.finish_interaction()
	await process_frame
	_check(ui.map_view.visible and state.is_node_completed("n_rest"), "Leaving Safe Room should return to MapView.")

	# 5. Select Elite node -> routes to CombatView with overridden stats
	_check(ui.map_view.request_select_node("n_elite"), "Selecting Elite node should succeed.")
	await process_frame
	_check(ui.combat_view.visible and ui.encounter.enemy_health == 10, "Elite node should apply health_override (10 HP) in combat.")
	_force_combat_victory(ui)
	ui.advance_run()
	await process_frame
	_check(ui.map_view.visible and state.is_node_completed("n_elite") and state.gold == 55, "Winning Elite should award +25 gold and return to MapView.")

	# 6. Select Boss node -> routes to CombatView and finishes run on victory
	_check(ui.map_view.request_select_node("n_boss"), "Selecting Boss node should succeed.")
	await process_frame
	_check(ui.combat_view.visible and ui.encounter.enemy_health == 12, "Boss node should apply health_override (12 HP) in combat.")
	_force_combat_victory(ui)
	ui.advance_run()
	await process_frame
	_check(state.run_finished and state.run_victory, "Defeating Boss node should complete the run in victory.")

	ui.enemy_stage.clear_hit_effects()
	ui.queue_free()
	await process_frame
	if failures == 0:
		print("Milestone 4 interaction routing tests passed.")
	quit(1 if failures > 0 else 0)


func _force_combat_victory(ui: Control) -> void:
	ui.encounter.enemy_health = 1
	ui.encounter.player_hand.clear()
	ui.encounter.player_hand.append(Card.new(Card.CardColor.WILD, Card.Kind.WILD))
	ui.encounter.player_hand.append(Card.new(Card.CardColor.BLUE, Card.Kind.NUMBER, 3))
	ui.render()
	ui.hand_dock.press_card(0)
	ui.hand_dock.choose_wild_color(Card.CardColor.BLUE)
