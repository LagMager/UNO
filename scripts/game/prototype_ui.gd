extends Control

const RunSessionScript = preload("res://scripts/game/run_session.gd")
const RunControllerScript = preload("res://scripts/run/run_controller.gd")
const RunStateScript = preload("res://scripts/run/run_state.gd")
const MapGeneratorScript = preload("res://scripts/map/map_generator.gd")
const MapGeneratorConfigScript = preload("res://scripts/map/map_generator_config.gd")
const MapNodeDataScript = preload("res://scripts/map/map_node_data.gd")
const EncounterDataScript = preload("res://scripts/content/encounter_data.gd")
const DecisionDataScript = preload("res://scripts/content/decision_data.gd")
const ShopDataScript = preload("res://scripts/content/shop_data.gd")
const RestSiteDataScript = preload("res://scripts/content/rest_site_data.gd")
const DecisionRunnerScript = preload("res://scripts/decision/decision_runner.gd")
const CombatHUDScript = preload("res://scripts/game/ui/combat_hud.gd")
const EnemyStageScript = preload("res://scripts/game/ui/enemy_stage.gd")
const RewardPanelScript = preload("res://scripts/game/ui/reward_panel.gd")
const ActionLogPanelScript = preload("res://scripts/game/ui/action_log_panel.gd")
const HandDockScript = preload("res://scripts/game/ui/hand_dock.gd")
const SelectionViewScript = preload("res://scripts/game/ui/selection_view.gd")
const MapViewScript = preload("res://scripts/map/ui/map_view.gd")
const NodeInteractionViewScript = preload("res://scripts/run/ui/node_interaction_view.gd")
const DeckDialogScript = preload("res://scripts/game/ui/deck_dialog.gd")
const MenuBackdropScript = preload("res://scripts/menu/menu_backdrop.gd")
const TableStageScript = preload("res://scripts/game/ui/table_stage.gd")
const WildPickerScript = preload("res://scripts/game/ui/wild_picker.gd")
const ShopScreenScript = preload("res://scripts/run/ui/shop_screen.gd")
const ZoneScreenScript = preload("res://scripts/zones/zone_screen.gd")
const RestScreenScript = preload("res://scripts/zones/rest_screen.gd")
const SaveGameScript = preload("res://scripts/run/save_game.gd")
const SaveToastScript = preload("res://scripts/ui/save_toast.gd")
var save_toast: SaveToastScript
const MainMenuScript = preload("res://scripts/menu/main_menu.gd")
const SettingsPanelScript = preload("res://scripts/menu/settings_panel.gd")
const UIGrimeScript = preload("res://scripts/ui/grime.gd")
const ScreenBurnScript = preload("res://scripts/ui/screen_burn.gd")
const PausePanelScript = preload("res://scripts/menu/pause_panel.gd")
## Gold and health for a shop opened from the menu (just to look around).
const PREVIEW_GOLD := 100
const PREVIEW_WOUNDS := 6

var run_session: RefCounted
var run_controller: RunControllerScript
var decision_runner_factory: Callable = Callable()
var shop_screen: ShopScreenScript
var _shop_preview := false
var _rest_preview := false
var zone_screen: ZoneScreenScript
## The first screen: La Cantina with Play / Settings / Quit (tests live behind Debug).
var main_menu: MainMenuScript
## Burns the old screen away whenever the scenery changes.
var screen_burn: ScreenBurnScript
var _scenery := ""
## Esc during a run (shows the seed, with a button to copy it).
var pause_panel: PausePanelScript
## The map's Safe Room, shown as the 3D Rest Point (built when first needed).
var rest_screen: RestScreenScript
var encounter: RefCounted:
	get:
		return run_session.encounter if run_session != null else null

@onready var backdrop: TextureRect = $Backdrop
@onready var menu_backdrop: MenuBackdropScript = $MenuBackdrop
@onready var table_stage: TableStageScript = $TableStage
@onready var combat_view: MarginContainer = $CombatView
@onready var combat_hud: CombatHUDScript = $CombatView/Column/CombatHUD
@onready var content: VBoxContainer = $CombatView/Column/Content
@onready var battle_row: HBoxContainer = $CombatView/Column/Content/BattleRow
@onready var side_spacer: Control = $CombatView/Column/Content/BattleRow/SideSpacer
@onready var enemy_stage: EnemyStageScript = $CombatView/Column/Content/BattleRow/Stage/EnemyStack/EnemyStage
@onready var reward_panel: RewardPanelScript = $CombatView/Column/Content/BattleRow/Stage/EnemyStack/RewardContainer
@onready var action_log_panel: ActionLogPanelScript = $CombatView/Column/Content/BattleRow/ActionLog
@onready var hand_dock: HandDockScript = $CombatView/Column/HandDock
@onready var selection_view: SelectionViewScript = $EncounterSelection
@onready var map_view: MapViewScript = $MapView
@onready var interaction_view: NodeInteractionViewScript = $NodeInteractionView
@onready var deck_dialog: DeckDialogScript = $DeckDialog


func _ready() -> void:
	run_session = RunSessionScript.new()
	run_controller = RunControllerScript.new()
	_connect_signals()
	render()
	SettingsPanelScript.apply_saved()
	# behind every screen: near black, never the engine's grey
	RenderingServer.set_default_clear_color(Color(0.02, 0.016, 0.015))
	screen_burn = ScreenBurnScript.new()
	add_child(screen_burn)
	save_toast = SaveToastScript.new()
	add_child(save_toast)
	main_menu = MainMenuScript.new()
	main_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_menu)
	move_child(main_menu, deck_dialog.get_index())
	main_menu.set_saves(_saves_list())
	main_menu.play_requested.connect(func(slot: int) -> void:
		map_view.debug_tools = false
		# the page picked to write over, or the first empty one
		SaveGameScript.slot = slot if slot >= 0 else SaveGameScript.pick_slot_for_new_run()
		SaveGameScript.clear()
		start_map_run())
	main_menu.continue_requested.connect(continue_run)
	main_menu.debug_requested.connect(show_selection)
	selection_view.back_requested.connect(show_main_menu)
	pause_panel = PausePanelScript.new()
	add_child(pause_panel)
	move_child(pause_panel, deck_dialog.get_index())
	pause_panel.resume_requested.connect(func() -> void: pause_panel.visible = false)
	pause_panel.save_requested.connect(func() -> void:
		pause_panel.visible = false
		_save_run())
	pause_panel.main_menu_requested.connect(func() -> void:
		pause_panel.visible = false
		show_main_menu())
	show_main_menu()
	get_viewport().size_changed.connect(update_layout)
	# The old gray enemy box stays for layout and tests; the rival is now drawn at the table.
	enemy_stage.modulate.a = 0.0
	table_stage.hand_row = hand_dock.hand_row
	table_stage.busy_changed.connect(hand_dock.set_locked)
	var picker := WildPickerScript.new()
	picker.duel = table_stage.duel
	add_child(picker)
	hand_dock.wild_requested.connect(picker.open)
	picker.color_chosen.connect(hand_dock.choose_wild_color)
	picker.cancelled.connect(hand_dock.cancel_wild)
	# the arms already show the hand; the label only covered the table
	hand_dock.hand_label.visible = false
	shop_screen = ShopScreenScript.new()
	shop_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_screen.visible = false
	add_child(shop_screen)
	move_child(shop_screen, interaction_view.get_index() + 1)
	selection_view.shop_requested.connect(open_shop_preview)
	selection_view.zone_requested.connect(open_zone_preview)
	selection_view.rest_requested.connect(open_rest_preview)
	# the whole interface gets the dirty, dithered finish of the 3D
	UIGrimeScript.apply(self)
	update_layout()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if pause_panel == null or _scenery in ["main_menu", "menu", ""]:
		return
	if pause_panel.visible:
		pause_panel.visible = false
	else:
		pause_panel.open(map_view.get_seed())
		if map_view.debug_tools:
			pause_panel.set_can_save(false, "not in debug runs")
		else:
			pause_panel.set_can_save(_scenery == "map", "only on the map")
	get_viewport().set_input_as_handled()


func show_main_menu() -> void:
	_set_scenery("main_menu")
	main_menu.set_saves(_saves_list())
	enemy_stage.clear_hit_effects()
	combat_view.visible = false
	map_view.visible = false
	interaction_view.visible = false
	selection_view.visible = false
	main_menu.open()


## Leaving a fight or the map: a real run goes back to the main menu, a test to Debug.
func _leave_play() -> void:
	if run_session.mode == RunSessionScript.MODE_MAP:
		show_main_menu()
	else:
		show_selection()


func show_selection() -> void:
	_set_scenery("menu")
	enemy_stage.clear_hit_effects()
	combat_view.visible = false
	map_view.visible = false
	interaction_view.visible = false
	selection_view.visible = true
	selection_view.reset_selection()


func start_single(enemy_id: String) -> void:
	if not run_session.start_single(enemy_id):
		return
	_open_combat()


func start_run() -> void:
	if not run_session.start_run():
		return
	_open_combat()


## Writes the run to its slot and shows the note in the corner.
func _save_run() -> void:
	var zone := _circle_info()
	if SaveGameScript.save(run_controller.run_state, String(zone.get("hand", "")), String(zone.get("name", ""))):
		save_toast.show_saving()


func _saves_list() -> Array:
	var out: Array = []
	for i: int in range(SaveGameScript.SLOTS):
		out.append(SaveGameScript.peek(i))
	return out


## The circle the run is in (its zone info), written on its paper in the drawer.
func _circle_info() -> Dictionary:
	var state := run_controller.run_state
	if map_view.inferno == null or state == null or state.map_data == null:
		return {}
	var node: MapNodeDataScript = state.map_data.get_node(state.current_node_id) if not state.current_node_id.is_empty() else null
	return map_view.inferno.zone_info(map_view.inferno.zone_of_floor(node.floor_index if node != null else 0))


## A saved run (drawer slot), back where it was left on the map.
func continue_run(slot: int = 0) -> void:
	map_view.debug_tools = false
	if not SaveGameScript.load_into(run_controller, slot):
		start_map_run()
		return
	map_view.bind_run_state(run_controller.run_state)
	_show_map()


func start_map_run(seed_value: int = MapGeneratorScript.DEFAULT_SEED, config: MapGeneratorConfigScript = null) -> void:
	var state: RunStateScript = run_controller.start_new_run(seed_value, config)
	map_view.bind_run_state(state)
	_show_map()


func advance_run() -> void:
	if run_session.mode == RunSessionScript.MODE_MAP:
		run_controller.resolve_combat_outcome(encounter.result == "Victory", encounter.player_health)
		return
	if not run_session.advance_run():
		return
	_open_combat()


func restart_encounter() -> void:
	if run_session.mode == RunSessionScript.MODE_MAP:
		var seed_val: int = run_controller.run_state.map_data.generation_seed if run_controller.run_state.map_data != null else MapGeneratorScript.DEFAULT_SEED
		start_map_run(seed_val)
		return
	if not run_session.restart():
		return
	_open_combat()


func play_card(index: int, wild_color: Card.CardColor = Card.CardColor.WILD) -> void:
	var previous_health: int = encounter.enemy_health
	var before: Dictionary = table_stage.snapshot(encounter)
	var played: Card = encounter.player_hand[index] if index >= 0 and index < encounter.player_hand.size() else null
	var from_rect := Rect2()
	if index >= 0 and index < hand_dock.hand_row.get_child_count():
		var button: Control = hand_dock.hand_row.get_child(index)
		from_rect = Rect2(button.global_position - table_stage.global_position, button.size)
	if encounter.play_player_card(index, wild_color):
		render()
		table_stage.play_round(before, encounter, played, from_rect, false)
		var damage: int = maxi(previous_health - encounter.enemy_health, 0)
		if damage > 0:
			enemy_stage.show_hit(damage)
		_sync_map_defeat_if_needed()


func draw_card() -> void:
	var before: Dictionary = table_stage.snapshot(encounter)
	if encounter.draw_player_card():
		render()
		table_stage.play_round(before, encounter, null, Rect2(), true)
		_sync_map_defeat_if_needed()


func select_reward(index: int) -> void:
	if run_session.claim_reward(index):
		render()


func skip_reward() -> void:
	if run_session.skip_reward():
		render()


func open_deck_dialog() -> void:
	if map_view.visible and run_controller.run_state != null:
		deck_dialog.open_for_deck(run_controller.run_state.player_deck)
	else:
		deck_dialog.open_for_deck(encounter.player_deck)


func render() -> void:
	run_session.sync_rewards()
	combat_hud.render_hud(run_session)
	enemy_stage.render_enemy(encounter)
	reward_panel.render_rewards(run_session)
	action_log_panel.render_log(encounter)
	hand_dock.render_dock(run_session)
	table_stage.sync_now(encounter)
	update_layout()


func update_layout() -> void:
	var narrow := get_window().size.x < 900
	side_spacer.visible = not narrow
	if narrow and action_log_panel.get_parent() != content:
		action_log_panel.reparent(content)
	elif not narrow and action_log_panel.get_parent() != battle_row:
		action_log_panel.reparent(battle_row)
	action_log_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if narrow else Control.SIZE_EXPAND_FILL
	action_log_panel.custom_minimum_size.y = 120 if narrow else 130
	hand_dock.update_hand_width()


func _open_combat() -> void:
	_set_scenery("table")
	table_stage.new_encounter(encounter)
	enemy_stage.clear_hit_effects()
	selection_view.visible = false
	map_view.visible = false
	interaction_view.visible = false
	combat_view.visible = true
	render()


func _show_map(_state: RunStateScript = null) -> void:
	_set_scenery("map")
	# back on the map: the run is saved here (not the debug ones)
	if not map_view.debug_tools:
		_save_run()
	enemy_stage.clear_hit_effects()
	selection_view.visible = false
	combat_view.visible = false
	interaction_view.visible = false
	map_view.visible = true
	map_view.render_map(run_controller.run_state)


func _on_map_combat_requested(_node: MapNodeDataScript, encounter_data: EncounterDataScript) -> void:
	if run_session.start_map_encounter(run_controller.run_state, encounter_data):
		_open_combat()


func _on_map_decision_requested(_node: MapNodeDataScript, decision_data: DecisionDataScript) -> void:
	_set_scenery("saloon")
	selection_view.visible = false
	combat_view.visible = false
	map_view.visible = false
	interaction_view.visible = true
	var runner: RefCounted = null
	if decision_runner_factory.is_valid():
		runner = decision_runner_factory.call()
	else:
		runner = DecisionRunnerScript.new()
	interaction_view.open_decision(run_controller.run_state, decision_data, runner)


func _on_map_shop_requested(_node: MapNodeDataScript, shop_data: ShopDataScript) -> void:
	_open_shop(run_controller.run_state, shop_data)


## The shop from the main menu: a throwaway purse, so every item can be tried.
func open_shop_preview() -> void:
	_shop_preview = true
	var state := RunStateScript.new()
	state.gold = PREVIEW_GOLD
	state.current_health = maxi(state.max_health - PREVIEW_WOUNDS, 1)
	_open_shop(state, ShopDataScript.new())


## A zone on its own, from the main menu (built lazily: it is a whole 3D scene).
func open_zone_preview(_zone_id: String) -> void:
	if zone_screen == null:
		zone_screen = ZoneScreenScript.new()
		zone_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(zone_screen)
		zone_screen.closed.connect(close_zone_preview)
	_set_scenery("zone")
	selection_view.visible = false
	combat_view.visible = false
	map_view.visible = false
	interaction_view.visible = false


func close_zone_preview() -> void:
	if zone_screen != null:
		zone_screen.queue_free()
		zone_screen = null
	show_selection()


func _open_shop(state: RunStateScript, shop_data: ShopDataScript) -> void:
	_set_scenery("shop")
	selection_view.visible = false
	combat_view.visible = false
	map_view.visible = false
	interaction_view.visible = true
	interaction_view.open_shop(state, shop_data)
	if shop_screen != null:
		shop_screen.open(interaction_view)


func _on_map_safe_room_requested(node: MapNodeDataScript, rest_data: RestSiteDataScript) -> void:
	# the rest looks like the circle it is in (the pit's counts as the last one)
	var zone: int = map_view.inferno.zone_of_floor(node.floor_index) if map_view.inferno != null else 0
	_open_rest(run_controller.run_state, rest_data, 2 if zone < 0 else mini(zone, 2))


## The rest stop from the main menu: a throwaway run, wounded, so both options can be tried.
## It starts in the Mesquite; buttons at the top walk you into the other circles' rests.
func open_rest_preview() -> void:
	_rest_preview = true
	var state := RunStateScript.new()
	state.current_health = maxi(state.max_health - PREVIEW_WOUNDS, 1)
	_open_rest(state, RestSiteDataScript.new(), 0)


func _open_rest(state: RunStateScript, rest_data: RestSiteDataScript, circle := 0) -> void:
	if rest_screen == null:
		rest_screen = RestScreenScript.new()
		rest_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		rest_screen.visible = false
		add_child(rest_screen)
		move_child(rest_screen, interaction_view.get_index() + 1)
	_set_scenery("rest")
	selection_view.visible = false
	combat_view.visible = false
	map_view.visible = false
	interaction_view.visible = true
	interaction_view.open_safe_room(state, rest_data)
	rest_screen.open(interaction_view, circle, _rest_preview)


func _on_interaction_finished(pending_encounter: EncounterDataScript) -> void:
	if shop_screen != null:
		shop_screen.close()
	if rest_screen != null:
		rest_screen.close()
	if _rest_preview:
		_rest_preview = false
		show_selection()
		return
	if _shop_preview:
		_shop_preview = false
		show_selection()
		return
	run_controller.complete_non_combat_interaction(pending_encounter)


func _sync_map_defeat_if_needed() -> void:
	if run_session.mode == RunSessionScript.MODE_MAP and encounter.result == "Defeat":
		run_controller.resolve_combat_outcome(false, 0)


func _connect_signals() -> void:
	selection_view.single_encounter_requested.connect(start_single)
	selection_view.run_requested.connect(start_run)
	selection_view.map_run_requested.connect(func() -> void:
		map_view.debug_tools = true     # from Debug: the circles can be walked freely
		start_map_run())
	reward_panel.reward_selected.connect(select_reward)
	reward_panel.reward_skipped.connect(skip_reward)
	hand_dock.card_play_requested.connect(play_card)
	hand_dock.draw_requested.connect(draw_card)
	hand_dock.restart_requested.connect(restart_encounter)
	hand_dock.deck_requested.connect(open_deck_dialog)
	hand_dock.mode_select_requested.connect(_leave_play)
	hand_dock.next_encounter_requested.connect(advance_run)

	map_view.node_selected.connect(func(node_id: String) -> void: run_controller.select_map_node(node_id))
	map_view.deck_requested.connect(open_deck_dialog)
	map_view.mode_select_requested.connect(show_main_menu)
	map_view.restart_run_requested.connect(func() -> void: start_map_run())

	run_controller.map_shown.connect(_show_map)
	run_controller.run_ended.connect(func(_victory: bool) -> void:
		if not map_view.debug_tools:
			SaveGameScript.clear())
	run_controller.combat_requested.connect(_on_map_combat_requested)
	run_controller.decision_requested.connect(_on_map_decision_requested)
	run_controller.shop_requested.connect(_on_map_shop_requested)
	run_controller.safe_room_requested.connect(_on_map_safe_room_requested)
	interaction_view.interaction_finished.connect(_on_interaction_finished)


func _set_scenery(kind: String) -> void:
	if kind != _scenery and _scenery != "" and screen_burn != null:
		screen_burn.burn()
	_scenery = kind
	if main_menu != null:
		main_menu.visible = kind == "main_menu"
	backdrop.visible = kind == "saloon"
	table_stage.visible = kind == "table"
	menu_backdrop.visible = kind == "menu"
	# the shop is its own 3D room; the gray panel only keeps the shop's rules
	interaction_view.get_node("Panel").visible = kind not in ["shop", "rest"]
	if shop_screen != null:
		shop_screen.visible = kind == "shop"
	menu_backdrop.speed_scale = 1.0 if kind == "menu" else 0.35
	if zone_screen != null:
		zone_screen.visible = kind == "zone"
	if rest_screen != null:
		rest_screen.visible = kind == "rest"
