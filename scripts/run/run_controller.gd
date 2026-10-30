class_name RunController
extends RefCounted

## Central progression and interaction router for a map-based roguelike run.
## Decouples MapView selection from combat, decision, shop, and safe room handlers.

signal map_shown(run_state: RunState)
signal combat_requested(node: MapNodeData, encounter_data: EncounterData)
signal decision_requested(node: MapNodeData, decision_data: DecisionData)
signal shop_requested(node: MapNodeData, shop_data: ShopData)
signal safe_room_requested(node: MapNodeData, rest_data: RestSiteData)
signal interaction_completed(node_id: String)
signal run_ended(victory: bool)

var run_state: RunState
var active_node: MapNodeData = null


func _init(p_run_state: RunState = null) -> void:
	run_state = p_run_state if p_run_state != null else RunState.new()


func start_new_run(seed_value: int = MapGenerator.DEFAULT_SEED, config: MapGeneratorConfig = null) -> RunState:
	var generated_map: MapData = MapGenerator.generate(seed_value, config)
	if run_state == null:
		run_state = RunState.new(generated_map)
	else:
		run_state.reset_run(generated_map)
	active_node = null
	map_shown.emit(run_state)
	return run_state


func start_run_with_map(custom_map: MapData, starting_health: int = 8, starting_gold: int = RunState.DEFAULT_STARTING_GOLD) -> RunState:
	if run_state == null:
		run_state = RunState.new(custom_map, starting_health, starting_gold)
	else:
		run_state.reset_run(custom_map, starting_health, starting_gold)
	active_node = null
	map_shown.emit(run_state)
	return run_state


## Validates and routes selection of a reachable map node to the appropriate handler.
func select_map_node(node_id: String) -> bool:
	if run_state == null or run_state.map_data == null:
		return false
	if not run_state.can_select_node(node_id):
		return false

	var node: MapNodeData = run_state.map_data.get_node(node_id)
	if node == null or not node.is_valid():
		push_error("RunController: Selected node '%s' is missing or has invalid content." % node_id)
		return false

	if not run_state.select_node(node_id):
		return false

	active_node = node
	_route_node(node)
	return true


## Resolves the completion of an Encounter / Elite / Boss combat interaction.
func resolve_combat_outcome(victory: bool, remaining_health: int) -> bool:
	if run_state == null or active_node == null:
		return false

	if not victory or remaining_health <= 0:
		run_state.current_health = 0
		active_node = null
		run_state.mark_run_defeat()
		run_ended.emit(false)
		return true

	run_state.current_health = clampi(remaining_health, 1, run_state.max_health)
	var enc_data := active_node.content as EncounterData
	if enc_data != null and enc_data.gold_reward > 0:
		run_state.modify_gold(enc_data.gold_reward)

	var finished_id: String = active_node.id
	active_node = null
	run_state.complete_active_node()
	interaction_completed.emit(finished_id)

	if run_state.run_finished:
		run_ended.emit(run_state.run_victory)
	else:
		map_shown.emit(run_state)
	return true


## Finishes a non-combat interaction (Decision, Shop, Safe Room) and returns to the map
## or transitions into combat if an event effect triggered an encounter.
func complete_non_combat_interaction(pending_encounter: EncounterData = null) -> bool:
	if run_state == null or active_node == null:
		return false

	if run_state.current_health <= 0 or (run_state.run_finished and not run_state.run_victory):
		active_node = null
		run_state.mark_run_defeat()
		run_ended.emit(false)
		return true

	if pending_encounter != null and pending_encounter.is_valid():
		combat_requested.emit(active_node, pending_encounter)
		return true

	var finished_id: String = active_node.id
	active_node = null
	run_state.complete_active_node()
	interaction_completed.emit(finished_id)

	if run_state.run_finished:
		run_ended.emit(run_state.run_victory)
	else:
		map_shown.emit(run_state)
	return true


func _route_node(node: MapNodeData) -> void:
	match node.node_type:
		MapEnums.NodeType.ENCOUNTER, MapEnums.NodeType.ELITE, MapEnums.NodeType.BOSS:
			combat_requested.emit(node, node.content as EncounterData)
		MapEnums.NodeType.DECISION:
			decision_requested.emit(node, node.content as DecisionData)
		MapEnums.NodeType.SHOP:
			shop_requested.emit(node, node.content as ShopData)
		MapEnums.NodeType.SAFE_ROOM:
			safe_room_requested.emit(node, node.content as RestSiteData)
