class_name RunState
extends RefCounted

## Single authoritative runtime state for an active roguelike run.
## Keeps mutable player stats, deck collection, and map node progression separate
## from shared Resource definitions (.tres).

const Encounter = preload("res://scripts/game/encounter.gd")
const PlayerDeck = preload("res://scripts/game/player_deck.gd")

signal state_changed
signal node_entered(node_id: String)
signal node_completed(node_id: String)

const DEFAULT_STARTING_GOLD := 30

var max_health: int = Encounter.STARTING_HEALTH
var current_health: int = Encounter.STARTING_HEALTH
var gold: int = DEFAULT_STARTING_GOLD
var player_deck: PlayerDeck
var map_data: MapData = null

var current_node_id: String = ""
var active_interaction_node_id: String = ""
var completed_node_ids: PackedStringArray = PackedStringArray()
var discovered_node_ids: PackedStringArray = PackedStringArray()
var run_finished: bool = false
var run_victory: bool = false


func _init(p_map_data: MapData = null, p_starting_health: int = Encounter.STARTING_HEALTH, p_starting_gold: int = DEFAULT_STARTING_GOLD) -> void:
	player_deck = PlayerDeck.new()
	reset_run(p_map_data, p_starting_health, p_starting_gold)


func reset_run(p_map_data: MapData = null, p_starting_health: int = Encounter.STARTING_HEALTH, p_starting_gold: int = DEFAULT_STARTING_GOLD) -> void:
	max_health = maxi(p_starting_health, 1)
	current_health = max_health
	gold = maxi(p_starting_gold, 0)
	player_deck.reset_to_starter()
	map_data = p_map_data
	current_node_id = ""
	active_interaction_node_id = ""
	completed_node_ids.clear()
	discovered_node_ids.clear()
	run_finished = false
	run_victory = false

	if map_data != null and not map_data.start_node_id.is_empty() and map_data.has_node(map_data.start_node_id):
		_mark_discovered(map_data.start_node_id)
	state_changed.emit()


## Returns the node IDs currently selectable by the player on the map.
func get_reachable_node_ids() -> PackedStringArray:
	var reachable := PackedStringArray()
	if map_data == null or run_finished:
		return reachable
	# Cannot select a new map node while an interaction is still in progress.
	if not active_interaction_node_id.is_empty():
		return reachable

	if current_node_id.is_empty():
		if map_data.has_node(map_data.start_node_id):
			reachable.append(map_data.start_node_id)
		return reachable

	# Current node must be completed before advancing to outgoing nodes.
	if not is_node_completed(current_node_id):
		return reachable

	var current_node: MapNodeData = map_data.get_node(current_node_id)
	if current_node == null:
		return reachable

	for next_id: String in current_node.next_node_ids:
		if map_data.has_node(next_id) and not is_node_completed(next_id):
			reachable.append(next_id)
	return reachable


func can_select_node(node_id: String) -> bool:
	return get_reachable_node_ids().has(node_id)


func is_node_completed(node_id: String) -> bool:
	return completed_node_ids.has(node_id)


func is_node_discovered(node_id: String) -> bool:
	return discovered_node_ids.has(node_id)


## Moves the player onto a reachable node and begins its interaction.
func select_node(node_id: String) -> bool:
	if not can_select_node(node_id):
		return false
	current_node_id = node_id
	active_interaction_node_id = node_id
	_mark_discovered(node_id)
	var node: MapNodeData = map_data.get_node(node_id)
	if node != null:
		for next_id: String in node.next_node_ids:
			_mark_discovered(next_id)
	node_entered.emit(node_id)
	state_changed.emit()
	return true


## Marks the currently active node interaction as completed and unlocks its outgoing paths.
func complete_active_node() -> bool:
	if active_interaction_node_id.is_empty() or map_data == null:
		return false
	var finished_id: String = active_interaction_node_id
	active_interaction_node_id = ""
	if not completed_node_ids.has(finished_id):
		completed_node_ids.append(finished_id)

	var node: MapNodeData = map_data.get_node(finished_id)
	if node != null:
		for next_id: String in node.next_node_ids:
			_mark_discovered(next_id)

	if finished_id == map_data.boss_node_id:
		run_finished = true
		run_victory = true

	node_completed.emit(finished_id)
	state_changed.emit()
	return true


func mark_run_defeat() -> void:
	active_interaction_node_id = ""
	run_finished = true
	run_victory = false
	state_changed.emit()


func modify_health(delta: int) -> int:
	var previous: int = current_health
	current_health = clampi(current_health + delta, 0, max_health)
	if current_health <= 0:
		run_finished = true
		run_victory = false
	state_changed.emit()
	return current_health - previous


func modify_gold(delta: int) -> int:
	var previous: int = gold
	gold = maxi(gold + delta, 0)
	state_changed.emit()
	return gold - previous


func can_afford(cost: int) -> bool:
	return cost >= 0 and gold >= cost


func to_dict() -> Dictionary:
	return {
		"max_health": max_health,
		"current_health": current_health,
		"gold": gold,
		"current_node_id": current_node_id,
		"active_interaction_node_id": active_interaction_node_id,
		"completed_node_ids": Array(completed_node_ids),
		"discovered_node_ids": Array(discovered_node_ids),
		"run_finished": run_finished,
		"run_victory": run_victory,
		"generation_seed": map_data.generation_seed if map_data != null else 0,
	}


func load_progression_dict(state: Dictionary) -> void:
	max_health = maxi(int(state.get("max_health", max_health)), 1)
	current_health = clampi(int(state.get("current_health", current_health)), 0, max_health)
	gold = maxi(int(state.get("gold", gold)), 0)
	current_node_id = str(state.get("current_node_id", ""))
	active_interaction_node_id = str(state.get("active_interaction_node_id", ""))
	completed_node_ids = PackedStringArray(state.get("completed_node_ids", []))
	discovered_node_ids = PackedStringArray(state.get("discovered_node_ids", []))
	run_finished = bool(state.get("run_finished", false))
	run_victory = bool(state.get("run_victory", false))
	state_changed.emit()


func _mark_discovered(node_id: String) -> void:
	if not node_id.is_empty() and not discovered_node_ids.has(node_id):
		discovered_node_ids.append(node_id)
