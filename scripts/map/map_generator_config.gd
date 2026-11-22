class_name MapGeneratorConfig
extends Resource

## Configuration resource controlling procedural DAG map generation and node type placement.

@export var total_floors: int = 7
@export var grid_columns: int = 5
@export var min_nodes_per_floor: int = 2
@export var max_nodes_per_floor: int = 4
@export_range(0.0, 1.0) var extra_branch_chance: float = 0.45
@export var guarantee_pre_boss_safe_room: bool = true
@export var min_elite_floor: int = 2

@export var weight_encounter: int = 45
@export var weight_decision: int = 22
@export var weight_shop: int = 12
@export var weight_safe_room: int = 11
@export var weight_elite: int = 10

@export var normal_encounters: Array[EncounterData] = []
@export var elite_encounters: Array[EncounterData] = []
@export var boss_encounters: Array[EncounterData] = []
@export var decisions: Array[DecisionData] = []
@export var shops: Array[ShopData] = []
@export var rest_sites: Array[RestSiteData] = []


func is_valid() -> bool:
	if total_floors < 3:
		return false
	if grid_columns < 1:
		return false
	if min_nodes_per_floor < 1 or max_nodes_per_floor < min_nodes_per_floor:
		return false
	if min_nodes_per_floor > grid_columns:
		return false
	var total_weight: int = weight_encounter + weight_decision + weight_shop + weight_safe_room + weight_elite
	return total_weight > 0
