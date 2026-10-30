class_name MapData
extends Resource

## Represents an entire generated map as a directed acyclic graph (DAG).
## Connections are stored by stable node IDs so the resource is UI-independent and serializable.

@export var nodes: Array[MapNodeData] = []
@export var start_node_id: String = ""
@export var boss_node_id: String = ""
@export var generation_seed: int = 0
@export var total_floors: int = 0
@export var metadata: Dictionary = {}

var _node_lookup: Dictionary = {}


func _init(
	p_seed: int = 0,
	p_total_floors: int = 0,
	p_start_node_id: String = "",
	p_boss_node_id: String = ""
) -> void:
	generation_seed = p_seed
	total_floors = p_total_floors
	start_node_id = p_start_node_id
	boss_node_id = p_boss_node_id


func rebuild_index() -> void:
	_node_lookup.clear()
	for node: MapNodeData in nodes:
		if node != null and not node.id.is_empty():
			_node_lookup[node.id] = node


func add_node(node: MapNodeData) -> bool:
	if node == null or node.id.strip_edges().is_empty():
		return false
	_ensure_index()
	if _node_lookup.has(node.id):
		return false
	nodes.append(node)
	_node_lookup[node.id] = node
	if node.floor_index + 1 > total_floors:
		total_floors = node.floor_index + 1
	return true


func get_node(node_id: String) -> MapNodeData:
	_ensure_index()
	return _node_lookup.get(node_id, null) as MapNodeData


func has_node(node_id: String) -> bool:
	_ensure_index()
	return _node_lookup.has(node_id)


func has_edge(from_id: String, to_id: String) -> bool:
	var source: MapNodeData = get_node(from_id)
	if source == null or not has_node(to_id):
		return false
	return source.has_connection_to(to_id)


func get_outgoing_nodes(node_id: String) -> Array[MapNodeData]:
	var result: Array[MapNodeData] = []
	var source: MapNodeData = get_node(node_id)
	if source == null:
		return result
	for target_id: String in source.next_node_ids:
		var target: MapNodeData = get_node(target_id)
		if target != null:
			result.append(target)
	return result


func get_incoming_node_ids(target_id: String) -> PackedStringArray:
	var incoming := PackedStringArray()
	if not has_node(target_id):
		return incoming
	for node: MapNodeData in nodes:
		if node != null and node.has_connection_to(target_id):
			incoming.append(node.id)
	return incoming


func get_nodes_on_floor(floor_idx: int) -> Array[MapNodeData]:
	var floor_nodes: Array[MapNodeData] = []
	for node: MapNodeData in nodes:
		if node != null and node.floor_index == floor_idx:
			floor_nodes.append(node)
	floor_nodes.sort_custom(func(a: MapNodeData, b: MapNodeData) -> bool:
		return a.column_index < b.column_index
	)
	return floor_nodes


## Validates the DAG invariants:
## 1. Non-empty nodes with unique IDs and valid compatible content
## 2. Valid start_node_id and boss_node_id (with NodeType.BOSS)
## 3. All edges point to existing nodes on strictly higher floors (guarantees acyclicity)
## 4. Every node is reachable from start_node_id
## 5. Every node can reach boss_node_id
func validate_graph() -> Dictionary:
	rebuild_index()
	var errors: Array[String] = []

	if nodes.is_empty():
		errors.append("Map has no nodes.")
		return {"valid": false, "errors": errors}

	if _node_lookup.size() != nodes.size():
		errors.append("Map contains duplicate or empty node IDs.")

	var start_node: MapNodeData = get_node(start_node_id)
	if start_node == null:
		errors.append("Start node '%s' does not exist." % start_node_id)

	var boss_node: MapNodeData = get_node(boss_node_id)
	if boss_node == null:
		errors.append("Boss node '%s' does not exist." % boss_node_id)
	elif boss_node.node_type != MapEnums.NodeType.BOSS:
		errors.append("Boss node '%s' must have NodeType.BOSS." % boss_node_id)

	for node: MapNodeData in nodes:
		if node == null:
			errors.append("Map contains a null node entry.")
			continue
		if not node.is_valid():
			errors.append("Node '%s' failed validation (type/content mismatch or invalid fields)." % node.id)
		if node.id != boss_node_id and node.next_node_ids.is_empty():
			errors.append("Non-boss node '%s' has no outgoing connections." % node.id)
		if node.id == boss_node_id and not node.next_node_ids.is_empty():
			errors.append("Boss node '%s' should not have outgoing connections." % node.id)

		for target_id: String in node.next_node_ids:
			var target: MapNodeData = get_node(target_id)
			if target == null:
				errors.append("Node '%s' connects to missing node '%s'." % [node.id, target_id])
			elif target.floor_index <= node.floor_index:
				errors.append("Edge '%s' -> '%s' does not progress forward in floors (%d -> %d)." % [
					node.id, target.id, node.floor_index, target.floor_index
				])

	if start_node != null and boss_node != null and errors.is_empty():
		var reachable_from_start: Dictionary = _collect_reachable_from(start_node_id)
		for node: MapNodeData in nodes:
			if not reachable_from_start.has(node.id):
				errors.append("Node '%s' is not reachable from start node '%s'." % [node.id, start_node_id])

		var can_reach_boss: Dictionary = _collect_nodes_reaching(boss_node_id)
		for node: MapNodeData in nodes:
			if not can_reach_boss.has(node.id):
				errors.append("Node '%s' cannot reach boss node '%s'." % [node.id, boss_node_id])

	return {
		"valid": errors.is_empty(),
		"errors": errors,
	}


func _collect_reachable_from(root_id: String) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[String] = [root_id]
	visited[root_id] = true
	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current: MapNodeData = get_node(current_id)
		if current == null:
			continue
		for next_id: String in current.next_node_ids:
			if not visited.has(next_id) and has_node(next_id):
				visited[next_id] = true
				queue.append(next_id)
	return visited


func _collect_nodes_reaching(target_id: String) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[String] = [target_id]
	visited[target_id] = true
	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var incoming_ids: PackedStringArray = get_incoming_node_ids(current_id)
		for prev_id: String in incoming_ids:
			if not visited.has(prev_id):
				visited[prev_id] = true
				queue.append(prev_id)
	return visited


func _ensure_index() -> void:
	if _node_lookup.size() != nodes.size():
		rebuild_index()
