class_name EncounterData
extends NodeContentData

## Reusable combat encounter definition for normal, elite, and boss map nodes.
## Reuses EnemyProfiles and Encounter rather than duplicating combat logic.

const EnemyProfiles = preload("res://scripts/game/enemy_profiles.gd")

enum Tier {
	NORMAL,
	ELITE,
	BOSS,
}

@export var enemy_profile_id: String = "standard"
@export var tier: Tier = Tier.NORMAL
@export var health_override: int = -1
@export var attack_damage_override: int = -1
@export var attack_interval_override: int = -1
@export var gold_reward: int = 15
@export var offers_card_reward: bool = true


func _init(
	p_id: String = "encounter_standard",
	p_profile_id: String = "standard",
	p_tier: Tier = Tier.NORMAL,
	p_name: String = "",
	p_description: String = ""
) -> void:
	var profile: Dictionary = EnemyProfiles.get_profile(p_profile_id)
	var resolved_name: String = p_name if not p_name.is_empty() else str(profile.get("name", "Standard"))
	var resolved_desc: String = p_description if not p_description.is_empty() else str(profile.get("description", ""))
	super._init(p_id, resolved_name, resolved_desc)
	enemy_profile_id = p_profile_id
	tier = p_tier


func is_compatible_with(node_type: MapEnums.NodeType) -> bool:
	if not is_valid():
		return false
	match node_type:
		MapEnums.NodeType.ENCOUNTER:
			return tier == Tier.NORMAL
		MapEnums.NodeType.ELITE:
			return tier == Tier.ELITE
		MapEnums.NodeType.BOSS:
			return tier == Tier.BOSS
		_:
			return false


func is_valid() -> bool:
	if not super.is_valid():
		return false
	if not EnemyProfiles.is_valid(enemy_profile_id):
		return false
	if health_override == 0 or health_override < -1:
		return false
	if attack_damage_override < -1:
		return false
	if attack_interval_override == 0 or attack_interval_override < -1:
		return false
	if gold_reward < 0:
		return false
	return true


## Builds an effective enemy profile dictionary with any configured overrides applied.
func resolve_enemy_profile() -> Dictionary:
	var profile: Dictionary = EnemyProfiles.get_profile(enemy_profile_id)
	if not display_name.is_empty():
		profile["name"] = display_name
	if not description.is_empty():
		profile["description"] = description
	if health_override > 0:
		profile["health"] = health_override
	if attack_damage_override >= 0:
		profile["attack_damage"] = attack_damage_override
	if attack_interval_override > 0:
		profile["attack_interval"] = attack_interval_override
	return profile
