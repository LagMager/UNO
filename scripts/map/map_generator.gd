class_name MapGenerator
extends RefCounted

## Deterministic procedural generator for the roguelike branching map DAG.
## Independent of UI rendering; given the same seed and MapGeneratorConfig,
## generate() always produces an identical MapData graph.

const DEFAULT_SEED := 1337


static func generate(seed_value: int = DEFAULT_SEED, config: MapGeneratorConfig = null) -> MapData:
	var cfg: MapGeneratorConfig = config if config != null else MapGeneratorConfig.new()
	if not cfg.is_valid():
		push_error("MapGenerator received an invalid MapGeneratorConfig; falling back to defaults.")
		cfg = MapGeneratorConfig.new()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var pools: Dictionary = _build_content_pools(cfg)
	var center_col: int = cfg.grid_columns / 2
	var boss_floor: int = cfg.total_floors - 1

	var start_id := "f0_c%d" % center_col
	var boss_id := "f%d_c%d" % [boss_floor, center_col]
	var map := MapData.new(seed_value, cfg.total_floors, start_id, boss_id)
	map.metadata = {
		"grid_columns": cfg.grid_columns,
		"min_nodes_per_floor": cfg.min_nodes_per_floor,
		"max_nodes_per_floor": cfg.max_nodes_per_floor,
	}

	# Floor 0: single start node (Normal Encounter)
	var start_content: NodeContentData = _pick_from_pool(rng, pools["normal_encounters"])
	var start_node := MapNodeData.new(start_id, MapEnums.NodeType.ENCOUNTER, 0, center_col, start_content)
	map.add_node(start_node)

	# Intermediate floors: 1 .. boss_floor - 1
	var max_per_floor: int = mini(cfg.max_nodes_per_floor, cfg.grid_columns)
	var min_per_floor: int = mini(cfg.min_nodes_per_floor, max_per_floor)

	for floor_idx: int in range(1, boss_floor):
		var node_count: int = rng.randi_range(min_per_floor, max_per_floor)
		var columns: Array[int] = _choose_sorted_columns(rng, cfg.grid_columns, node_count)
		for col_idx: int in columns:
			var node_id := "f%d_c%d" % [floor_idx, col_idx]
			var node_type: MapEnums.NodeType = _choose_node_type(rng, floor_idx, boss_floor, cfg)
			var content: NodeContentData = _choose_content_for_type(rng, node_type, pools)
			var node := MapNodeData.new(node_id, node_type, floor_idx, col_idx, content)
			node.position_offset = Vector2(
				rng.randf_range(-8.0, 8.0),
				rng.randf_range(-6.0, 6.0)
			)
			map.add_node(node)

	# Final floor: single Boss node
	var boss_content: NodeContentData = _pick_from_pool(rng, pools["boss_encounters"])
	var boss_node := MapNodeData.new(boss_id, MapEnums.NodeType.BOSS, boss_floor, center_col, boss_content)
	map.add_node(boss_node)

	# Connect each floor to the next floor while preserving reachability and planar order
	for floor_idx: int in range(0, boss_floor):
		var curr_floor_nodes: Array[MapNodeData] = map.get_nodes_on_floor(floor_idx)
		var next_floor_nodes: Array[MapNodeData] = map.get_nodes_on_floor(floor_idx + 1)
		_connect_adjacent_floors(rng, curr_floor_nodes, next_floor_nodes, cfg.extra_branch_chance)

	map.rebuild_index()
	return map


static func _choose_sorted_columns(rng: RandomNumberGenerator, total_columns: int, count: int) -> Array[int]:
	var available: Array[int] = []
	for col: int in range(total_columns):
		available.append(col)

	var chosen: Array[int] = []
	var target_count: int = clampi(count, 1, total_columns)
	for _i: int in range(target_count):
		var pick_idx: int = rng.randi_range(0, available.size() - 1)
		chosen.append(available[pick_idx])
		available.remove_at(pick_idx)

	chosen.sort()
	return chosen


static func _choose_node_type(
	rng: RandomNumberGenerator,
	floor_idx: int,
	boss_floor: int,
	cfg: MapGeneratorConfig
) -> MapEnums.NodeType:
	# Floor 1 is always a combat encounter for a consistent opening
	if floor_idx == 1:
		return MapEnums.NodeType.ENCOUNTER

	# Pre-boss floor is a Safe Room when configured
	if cfg.guarantee_pre_boss_safe_room and floor_idx == boss_floor - 1:
		return MapEnums.NodeType.SAFE_ROOM

	var candidates: Array[Dictionary] = [
		{"type": MapEnums.NodeType.ENCOUNTER, "weight": maxi(cfg.weight_encounter, 0)},
		{"type": MapEnums.NodeType.DECISION, "weight": maxi(cfg.weight_decision, 0)},
		{"type": MapEnums.NodeType.SHOP, "weight": maxi(cfg.weight_shop, 0)},
		{"type": MapEnums.NodeType.SAFE_ROOM, "weight": maxi(cfg.weight_safe_room, 0)},
	]
	if floor_idx >= cfg.min_elite_floor:
		candidates.append({"type": MapEnums.NodeType.ELITE, "weight": maxi(cfg.weight_elite, 0)})

	var total_weight := 0
	for entry: Dictionary in candidates:
		total_weight += int(entry["weight"])

	if total_weight <= 0:
		return MapEnums.NodeType.ENCOUNTER

	var roll: int = rng.randi_range(0, total_weight - 1)
	var cumulative := 0
	for entry: Dictionary in candidates:
		cumulative += int(entry["weight"])
		if roll < cumulative:
			return entry["type"] as MapEnums.NodeType

	return MapEnums.NodeType.ENCOUNTER


static func _connect_adjacent_floors(
	rng: RandomNumberGenerator,
	curr_nodes: Array[MapNodeData],
	next_nodes: Array[MapNodeData],
	extra_branch_chance: float
) -> void:
	var n_count: int = curr_nodes.size()
	var m_count: int = next_nodes.size()
	if n_count == 0 or m_count == 0:
		return

	# Track edges as pairs of indices [u, v] into curr_nodes and next_nodes
	var edges: Array[Vector2i] = []

	# Step 1: Every node on curr_floor gets at least one outgoing edge
	for i: int in range(n_count):
		var primary_j: int = 0
		if n_count == 1:
			# Single node (e.g. Start node) connects to all nodes on the next floor
			for j: int in range(m_count):
				_add_index_edge(curr_nodes, next_nodes, edges, i, j)
			continue
		elif m_count > 1:
			primary_j = clampi(roundi(float(i) * float(m_count - 1) / float(n_count - 1)), 0, m_count - 1)
		_add_index_edge(curr_nodes, next_nodes, edges, i, primary_j)

	# Step 2: Every node on next_floor gets at least one incoming edge without crossing
	for j: int in range(m_count):
		if _has_incoming_index(edges, j):
			continue
		var best_i: int = 0
		if m_count > 1 and n_count > 1:
			best_i = clampi(roundi(float(j) * float(n_count - 1) / float(m_count - 1)), 0, n_count - 1)
		# Find a non-crossing source index if possible
		var chosen_i: int = best_i
		for candidate_i: int in range(n_count):
			if not _would_cross(edges, candidate_i, j):
				if _would_cross(edges, chosen_i, j) or absi(candidate_i - best_i) < absi(chosen_i - best_i):
					chosen_i = candidate_i
		_add_index_edge(curr_nodes, next_nodes, edges, chosen_i, j)

	# Step 3: Optionally add extra non-crossing branches to create diamond/converging paths
	if n_count > 1 and m_count > 1 and extra_branch_chance > 0.0:
		for i: int in range(n_count):
			for j: int in range(m_count):
				if _has_edge_indices(edges, i, j):
					continue
				if _would_cross(edges, i, j):
					continue
				# Only branch to nearby lanes so paths look natural
				var min_j: int = _min_target_for_source(edges, i)
				var max_j: int = _max_target_for_source(edges, i)
				if j == min_j - 1 or j == max_j + 1:
					if rng.randf() < extra_branch_chance:
						_add_index_edge(curr_nodes, next_nodes, edges, i, j)


static func _add_index_edge(
	curr_nodes: Array[MapNodeData],
	next_nodes: Array[MapNodeData],
	edges: Array[Vector2i],
	u: int,
	v: int
) -> void:
	if not _has_edge_indices(edges, u, v):
		edges.append(Vector2i(u, v))
		curr_nodes[u].add_connection(next_nodes[v].id)


static func _has_edge_indices(edges: Array[Vector2i], u: int, v: int) -> bool:
	for edge: Vector2i in edges:
		if edge.x == u and edge.y == v:
			return true
	return false


static func _has_incoming_index(edges: Array[Vector2i], v: int) -> bool:
	for edge: Vector2i in edges:
		if edge.y == v:
			return true
	return false


static func _would_cross(edges: Array[Vector2i], u: int, v: int) -> bool:
	for edge: Vector2i in edges:
		if (edge.x < u and edge.y > v) or (edge.x > u and edge.y < v):
			return true
	return false


static func _min_target_for_source(edges: Array[Vector2i], u: int) -> int:
	var result := 999999
	for edge: Vector2i in edges:
		if edge.x == u and edge.y < result:
			result = edge.y
	return result


static func _max_target_for_source(edges: Array[Vector2i], u: int) -> int:
	var result := -1
	for edge: Vector2i in edges:
		if edge.x == u and edge.y > result:
			result = edge.y
	return result


static func _choose_content_for_type(
	rng: RandomNumberGenerator,
	node_type: MapEnums.NodeType,
	pools: Dictionary
) -> NodeContentData:
	match node_type:
		MapEnums.NodeType.ENCOUNTER:
			return _pick_from_pool(rng, pools["normal_encounters"])
		MapEnums.NodeType.ELITE:
			return _pick_from_pool(rng, pools["elite_encounters"])
		MapEnums.NodeType.BOSS:
			return _pick_from_pool(rng, pools["boss_encounters"])
		MapEnums.NodeType.DECISION:
			return _pick_from_pool(rng, pools["decisions"])
		MapEnums.NodeType.SHOP:
			return _pick_from_pool(rng, pools["shops"])
		MapEnums.NodeType.SAFE_ROOM:
			return _pick_from_pool(rng, pools["rest_sites"])
		_:
			return _pick_from_pool(rng, pools["normal_encounters"])


static func _pick_from_pool(rng: RandomNumberGenerator, pool: Array) -> NodeContentData:
	var idx: int = rng.randi_range(0, pool.size() - 1)
	return pool[idx] as NodeContentData


static func _build_content_pools(cfg: MapGeneratorConfig) -> Dictionary:
	var normal_pool: Array[EncounterData] = cfg.normal_encounters.duplicate()
	if normal_pool.is_empty():
		normal_pool = [
			EncounterData.new("enc_standard", "standard", EncounterData.Tier.NORMAL, "Card Sentry", "Balanced UNO duelist."),
			EncounterData.new("enc_trickster", "trickster", EncounterData.Tier.NORMAL, "Trickster", "Prioritizes Replay and Skip actions."),
		]

	var elite_pool: Array[EncounterData] = cfg.elite_encounters.duplicate()
	if elite_pool.is_empty():
		var elite_aggressor := EncounterData.new(
			"elite_aggressor",
			"aggressor",
			EncounterData.Tier.ELITE,
			"Elite Aggressor",
			"Relentless attacker with reinforced health."
		)
		elite_aggressor.health_override = 10
		elite_aggressor.gold_reward = 30
		var elite_trickster := EncounterData.new(
			"elite_trickster",
			"trickster",
			EncounterData.Tier.ELITE,
			"Elite Illusionist",
			"Chains action cards and hits harder."
		)
		elite_trickster.health_override = 10
		elite_trickster.gold_reward = 30
		elite_pool = [elite_aggressor, elite_trickster]

	var boss_pool: Array[EncounterData] = cfg.boss_encounters.duplicate()
	if boss_pool.is_empty():
		var grand_dealer := EncounterData.new(
			"boss_grand_dealer",
			"aggressor",
			EncounterData.Tier.BOSS,
			"The Grand Dealer",
			"Boss encounter: attacks every round with high health."
		)
		grand_dealer.health_override = 12
		grand_dealer.gold_reward = 50
		boss_pool = [grand_dealer]

	var decision_pool: Array[DecisionData] = cfg.decisions.duplicate()
	if decision_pool.is_empty():
		var follow_up_blessing := DecisionData.new(
			"decision_altar_sanctum",
			"The Inner Sanctum",
			"The altar parts to reveal a chamber of gleaming cards.",
			[
				ChoiceData.new(
					"Claim the Wild Relic (+1 Wild Card)",
					[OutcomeData.new("You add a Wild card to your deck.", [AddCardEffect.new(Card.new(Card.CardColor.WILD, Card.Kind.WILD))])]
				),
				ChoiceData.new(
					"Take the coin coffer (+20 Gold)",
					[OutcomeData.new("You pocket 20 gold from the sanctum.", [GoldEffect.new(20)])]
				),
			]
		)

		var crimson_altar := DecisionData.new(
			"decision_crimson_altar",
			"The Crimson Altar",
			"An ornate UNO shrine hums with unstable energy. You may offer vitality or gold to unlock the Inner Sanctum.",
			[
				ChoiceData.new(
					"Offer 15 Gold to the shrine",
					[OutcomeData.new("The altar accepts your tribute and opens a hidden passage.", [GoldEffect.new(-15)], follow_up_blessing)],
					[MinGoldCondition.new(15)]
				),
				ChoiceData.new(
					"Offer 2 HP in blood tribute",
					[OutcomeData.new("Your vitality awakens the altar's inner chamber.", [HealthEffect.new(-2)], follow_up_blessing)],
					[MinHealthCondition.new(3)]
				),
				ChoiceData.new(
					"Step away respectfully (+1 HP)",
					[OutcomeData.new("You catch your breath and continue down the path.", [HealthEffect.new(1)])]
				),
			]
		)

		var collector_event := DecisionData.new(
			"decision_wandering_collector",
			"Wandering Collector",
			"A cloaked collector offers a trade from a gilded deck box.",
			[
				ChoiceData.new(
					"Pay 10 Gold for an Upgraded Red Replay",
					[OutcomeData.new("The collector hands you a gleaming Red Replay.", [
						GoldEffect.new(-10),
						AddCardEffect.new(_make_upgraded_card(Card.CardColor.RED, Card.Kind.REPLAY)),
					])],
					[MinGoldCondition.new(10)]
				),
				ChoiceData.new(
					"Trade 1 HP for 15 Gold",
					[OutcomeData.new("The collector pays you 15 gold for a vial of vitality.", [
						HealthEffect.new(-1),
						GoldEffect.new(15),
					])],
					[MinHealthCondition.new(2)]
				),
				ChoiceData.new(
					"Decline and move on",
					[OutcomeData.new("You part ways with the collector.")]
				),
			]
		)
		decision_pool = [crimson_altar, collector_event]

	var shop_pool: Array[ShopData] = cfg.shops.duplicate()
	if shop_pool.is_empty():
		shop_pool = [
			ShopData.new("shop_bazaar", "Card Bazaar", "Spend gold on new cards or recovery."),
		]

	var rest_pool: Array[RestSiteData] = cfg.rest_sites.duplicate()
	if rest_pool.is_empty():
		rest_pool = [
			RestSiteData.new("rest_sanctuary", 3, true, "Safe Room", "Recover 3 HP or upgrade a card in your deck."),
		]

	return {
		"normal_encounters": normal_pool,
		"elite_encounters": elite_pool,
		"boss_encounters": boss_pool,
		"decisions": decision_pool,
		"shops": shop_pool,
		"rest_sites": rest_pool,
	}


static func _make_upgraded_card(color: Card.CardColor, kind: Card.Kind, number: int = -1) -> Card:
	var card := Card.new(color, kind, number)
	card.upgrade()
	return card
