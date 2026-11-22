extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_content_compatibility()
	_test_dag_convergence_and_validation()
	_test_invalid_graphs()
	_test_run_state_progression_and_resource_safety()

	if failures == 0:
		print("Milestone 1 map data tests passed.")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _test_content_compatibility() -> void:
	var normal_encounter := EncounterData.new("enc_std", "standard", EncounterData.Tier.NORMAL)
	var elite_encounter := EncounterData.new("enc_elite", "aggressor", EncounterData.Tier.ELITE)
	var boss_encounter := EncounterData.new("enc_boss", "trickster", EncounterData.Tier.BOSS)
	var decision := DecisionData.new("dec_shrine", "Ancient Shrine", "A glowing altar.")
	var shop := ShopData.new("shop_1")
	var rest := RestSiteData.new("rest_1", 3, true)

	_check(normal_encounter.is_compatible_with(MapEnums.NodeType.ENCOUNTER), "Normal EncounterData should match ENCOUNTER node.")
	_check(not normal_encounter.is_compatible_with(MapEnums.NodeType.BOSS), "Normal EncounterData should not match BOSS node.")
	_check(elite_encounter.is_compatible_with(MapEnums.NodeType.ELITE), "Elite EncounterData should match ELITE node.")
	_check(boss_encounter.is_compatible_with(MapEnums.NodeType.BOSS), "Boss EncounterData should match BOSS node.")
	_check(decision.is_compatible_with(MapEnums.NodeType.DECISION), "DecisionData should match DECISION node.")
	_check(not decision.is_compatible_with(MapEnums.NodeType.SHOP), "DecisionData should not match SHOP node.")
	_check(shop.is_compatible_with(MapEnums.NodeType.SHOP), "ShopData should match SHOP node.")
	_check(rest.is_compatible_with(MapEnums.NodeType.SAFE_ROOM), "RestSiteData should match SAFE_ROOM node.")

	var invalid_encounter := EncounterData.new("enc_bad", "nonexistent_profile", EncounterData.Tier.NORMAL)
	_check(not invalid_encounter.is_valid(), "EncounterData with unknown EnemyProfiles id should be invalid.")

	var mismatched_node := MapNodeData.new("n_bad", MapEnums.NodeType.SHOP, 1, 0, decision)
	_check(not mismatched_node.is_content_compatible() and not mismatched_node.is_valid(), "MapNodeData should reject incompatible content resource.")


func _test_dag_convergence_and_validation() -> void:
	# Build a diamond DAG:
	# Floor 0: f0_c1 (Start, Encounter)
	# Floor 1: f1_c0 (Decision), f1_c2 (Shop)
	# Floor 2: f2_c1 (Safe Room - both Floor 1 paths converge here)
	# Floor 3: f3_c1 (Boss)
	var map := MapData.new(12345, 4, "f0_c1", "f3_c1")

	var n_start := MapNodeData.new("f0_c1", MapEnums.NodeType.ENCOUNTER, 0, 1, EncounterData.new("enc_start", "standard", EncounterData.Tier.NORMAL))
	var n_left := MapNodeData.new("f1_c0", MapEnums.NodeType.DECISION, 1, 0, DecisionData.new("dec_1", "Crossroads", "Pick a path."))
	var n_right := MapNodeData.new("f1_c2", MapEnums.NodeType.SHOP, 1, 2, ShopData.new("shop_1"))
	var n_merge := MapNodeData.new("f2_c1", MapEnums.NodeType.SAFE_ROOM, 2, 1, RestSiteData.new("rest_1"))
	var n_boss := MapNodeData.new("f3_c1", MapEnums.NodeType.BOSS, 3, 1, EncounterData.new("enc_boss", "trickster", EncounterData.Tier.BOSS))

	_check(n_start.add_connection("f1_c0") and n_start.add_connection("f1_c2"), "Start node should connect to two branching nodes.")
	_check(n_left.add_connection("f2_c1") and n_right.add_connection("f2_c1"), "Branching paths should converge on the same node in the DAG.")
	_check(n_merge.add_connection("f3_c1"), "Converged node should connect to boss.")

	for node: MapNodeData in [n_start, n_left, n_right, n_merge, n_boss]:
		_check(map.add_node(node), "Adding unique node '%s' should succeed." % node.id)

	var validation: Dictionary = map.validate_graph()
	_check(validation["valid"], "Valid diamond DAG should pass validation: %s" % [str(validation["errors"])])
	_check(map.get_incoming_node_ids("f2_c1").size() == 2, "Converged node should report 2 incoming connections.")
	_check(map.get_nodes_on_floor(1).size() == 2, "Floor 1 should contain 2 sorted nodes.")


func _test_invalid_graphs() -> void:
	var map := MapData.new(99, 2, "start", "boss")
	var n_start := MapNodeData.new("start", MapEnums.NodeType.ENCOUNTER, 0, 0, EncounterData.new("enc_1", "standard", EncounterData.Tier.NORMAL))
	var n_orphan := MapNodeData.new("orphan", MapEnums.NodeType.SAFE_ROOM, 1, 1, RestSiteData.new("rest_1"))
	var n_boss := MapNodeData.new("boss", MapEnums.NodeType.BOSS, 2, 0, EncounterData.new("enc_boss", "aggressor", EncounterData.Tier.BOSS))
	n_start.add_connection("boss")
	map.add_node(n_start)
	map.add_node(n_orphan)
	map.add_node(n_boss)

	var result: Dictionary = map.validate_graph()
	_check(not result["valid"], "Map with unreachable orphan node should fail validation.")


func _test_run_state_progression_and_resource_safety() -> void:
	var shared_rest := RestSiteData.new("shared_rest", 3, true)
	var map := MapData.new(777, 3, "n0", "n2")
	var n0 := MapNodeData.new("n0", MapEnums.NodeType.ENCOUNTER, 0, 0, EncounterData.new("enc_0", "standard", EncounterData.Tier.NORMAL))
	var n1 := MapNodeData.new("n1", MapEnums.NodeType.SAFE_ROOM, 1, 0, shared_rest)
	var n2 := MapNodeData.new("n2", MapEnums.NodeType.BOSS, 2, 0, EncounterData.new("enc_boss", "trickster", EncounterData.Tier.BOSS))
	n0.add_connection("n1")
	n1.add_connection("n2")
	map.add_node(n0)
	map.add_node(n1)
	map.add_node(n2)

	var run_a := RunState.new(map, 8, 25)
	var run_b := RunState.new(map, 8, 25)

	_check(run_a.get_reachable_node_ids() == PackedStringArray(["n0"]), "Only start node should be reachable initially.")
	_check(not run_a.can_select_node("n1"), "Unreached floor 1 node cannot be selected before completing start node.")
	_check(run_a.select_node("n0"), "Selecting start node should succeed.")
	_check(run_a.get_reachable_node_ids().is_empty(), "No map node should be selectable while an interaction is active.")
	_check(run_a.complete_active_node(), "Completing active node should succeed.")
	_check(run_a.is_node_completed("n0") and not run_b.is_node_completed("n0"), "Completing a node in run_a must not mutate map_data or affect run_b.")
	_check(run_a.get_reachable_node_ids() == PackedStringArray(["n1"]), "Completing n0 should unlock n1.")
	_check(run_a.select_node("n1") and run_a.complete_active_node(), "Advancing through n1 should succeed.")
	_check(run_a.select_node("n2") and run_a.complete_active_node(), "Completing boss node should finish the run in victory.")
	_check(run_a.run_finished and run_a.run_victory, "Boss completion should mark run_finished and run_victory.")
