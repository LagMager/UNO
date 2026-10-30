extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_deterministic_generation()
	_test_reachability_and_dag_invariants()
	_test_placement_rules_and_custom_config()

	if failures == 0:
		print("Milestone 2 map generator tests passed.")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _test_deterministic_generation() -> void:
	var config := MapGeneratorConfig.new()
	var map_a: MapData = MapGenerator.generate(20261028, config)
	var map_b: MapData = MapGenerator.generate(20261028, config)
	var map_c: MapData = MapGenerator.generate(99999999, config)

	_check(_serialize_map(map_a) == _serialize_map(map_b), "Same seed and config must produce identical maps.")
	_check(_serialize_map(map_a) != _serialize_map(map_c), "Different seeds should produce different maps.")


func _test_reachability_and_dag_invariants() -> void:
	var config := MapGeneratorConfig.new()
	config.total_floors = 8
	config.grid_columns = 5
	config.min_nodes_per_floor = 2
	config.max_nodes_per_floor = 4
	config.extra_branch_chance = 0.55

	var saw_converging_node := false
	var saw_branching_node := false

	for trial_seed: int in range(100, 125):
		var map: MapData = MapGenerator.generate(trial_seed, config)
		var validation: Dictionary = map.validate_graph()
		_check(validation["valid"], "Generated map (seed %d) must pass DAG validation: %s" % [trial_seed, str(validation["errors"])])

		_check(map.total_floors == config.total_floors, "Total floors should match config.")
		_check(map.get_nodes_on_floor(0).size() == 1 and map.get_nodes_on_floor(0)[0].id == map.start_node_id, "Floor 0 should contain the start node.")
		_check(map.get_nodes_on_floor(config.total_floors - 1).size() == 1 and map.get_nodes_on_floor(config.total_floors - 1)[0].id == map.boss_node_id, "Final floor should contain the boss node.")

		for node: MapNodeData in map.nodes:
			if node.next_node_ids.size() > 1:
				saw_branching_node = true
			if map.get_incoming_node_ids(node.id).size() > 1:
				saw_converging_node = true
			for next_id: String in node.next_node_ids:
				var next_node: MapNodeData = map.get_node(next_id)
				_check(next_node != null and next_node.floor_index == node.floor_index + 1, "Connections should advance strictly to the next floor.")

	_check(saw_branching_node and saw_converging_node, "Generator should produce branching and converging DAG paths.")


func _test_placement_rules_and_custom_config() -> void:
	var config := MapGeneratorConfig.new()
	config.total_floors = 6
	config.guarantee_pre_boss_safe_room = true
	config.min_elite_floor = 3

	for trial_seed: int in range(1, 15):
		var map: MapData = MapGenerator.generate(trial_seed, config)
		for node: MapNodeData in map.get_nodes_on_floor(1):
			_check(node.node_type == MapEnums.NodeType.ENCOUNTER, "Floor 1 nodes should always be normal encounters.")
		for node: MapNodeData in map.get_nodes_on_floor(2):
			_check(node.node_type != MapEnums.NodeType.ELITE, "Elites should not spawn before min_elite_floor.")
		for node: MapNodeData in map.get_nodes_on_floor(config.total_floors - 2):
			_check(node.node_type == MapEnums.NodeType.SAFE_ROOM, "Pre-boss floor should be Safe Rooms when guarantee_pre_boss_safe_room is true.")


func _serialize_map(map: MapData) -> String:
	var parts: Array[String] = [
		"seed=%d,floors=%d,start=%s,boss=%s" % [map.generation_seed, map.total_floors, map.start_node_id, map.boss_node_id]
	]
	for floor_idx: int in range(map.total_floors):
		for node: MapNodeData in map.get_nodes_on_floor(floor_idx):
			var edges := ",".join(node.next_node_ids)
			parts.append("%s:%d:%s->[%s]" % [node.id, node.node_type, node.content.content_id, edges])
	return "|".join(parts)
