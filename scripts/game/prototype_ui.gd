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

var run_session: RefCounted
var run_controller: RunControllerScript
var decision_runner_factory: Callable = Callable()
var encounter: RefCounted:
	get:
		return run_session.encounter if run_session != null else null

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
	show_selection()
	get_viewport().size_changed.connect(update_layout)
	update_layout()


func show_selection() -> void:
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
	if encounter.play_player_card(index, wild_color):
		render()
		var damage: int = maxi(previous_health - encounter.enemy_health, 0)
		if damage > 0:
			enemy_stage.show_hit(damage)
		_sync_map_defeat_if_needed()


func draw_card() -> void:
	if encounter.draw_player_card():
		render()
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
	enemy_stage.clear_hit_effects()
	selection_view.visible = false
	map_view.visible = false
	interaction_view.visible = false
	combat_view.visible = true
	render()


func _show_map(_state: RunStateScript = null) -> void:
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
	selection_view.visible = false
	combat_view.visible = false
	map_view.visible = false
	interaction_view.visible = true
	interaction_view.open_shop(run_controller.run_state, shop_data)


func _on_map_safe_room_requested(_node: MapNodeDataScript, rest_data: RestSiteDataScript) -> void:
	selection_view.visible = false
	combat_view.visible = false
	map_view.visible = false
	interaction_view.visible = true
	interaction_view.open_safe_room(run_controller.run_state, rest_data)


func _on_interaction_finished(pending_encounter: EncounterDataScript) -> void:
	run_controller.complete_non_combat_interaction(pending_encounter)


func _sync_map_defeat_if_needed() -> void:
	if run_session.mode == RunSessionScript.MODE_MAP and encounter.result == "Defeat":
		run_controller.resolve_combat_outcome(false, 0)


func _connect_signals() -> void:
	selection_view.single_encounter_requested.connect(start_single)
	selection_view.run_requested.connect(start_run)
	selection_view.map_run_requested.connect(func() -> void: start_map_run())
	reward_panel.reward_selected.connect(select_reward)
	reward_panel.reward_skipped.connect(skip_reward)
	hand_dock.card_play_requested.connect(play_card)
	hand_dock.draw_requested.connect(draw_card)
	hand_dock.restart_requested.connect(restart_encounter)
	hand_dock.deck_requested.connect(open_deck_dialog)
	hand_dock.mode_select_requested.connect(show_selection)
	hand_dock.next_encounter_requested.connect(advance_run)

	map_view.node_selected.connect(func(node_id: String) -> void: run_controller.select_map_node(node_id))
	map_view.deck_requested.connect(open_deck_dialog)
	map_view.mode_select_requested.connect(show_selection)
	map_view.restart_run_requested.connect(func() -> void: start_map_run())

	run_controller.map_shown.connect(_show_map)
	run_controller.combat_requested.connect(_on_map_combat_requested)
	run_controller.decision_requested.connect(_on_map_decision_requested)
	run_controller.shop_requested.connect(_on_map_shop_requested)
	run_controller.safe_room_requested.connect(_on_map_safe_room_requested)
	interaction_view.interaction_finished.connect(_on_interaction_finished)
