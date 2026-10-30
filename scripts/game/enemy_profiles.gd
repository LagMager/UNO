extends RefCounted

## Small playtest profiles. Keep behavior choices here instead of branching in UI.
const ORDER: Array[String] = ["standard", "aggressor", "trickster"]
const PROFILES := {
	"standard": {
		"name": "Standard",
		"description": "Original enemy: attacks every 2 rounds and plays its first match.",
		"health": 8,
		"attack_interval": 2,
		"attack_damage": 1,
		"prioritize_actions": false,
	},
	"aggressor": {
		"name": "Aggressor",
		"description": "Pressures you with an attack every round.",
		"health": 8,
		"attack_interval": 1,
		"attack_damage": 1,
		"prioritize_actions": false,
	},
	"trickster": {
		"name": "Trickster",
		"description": "Prefers Replay and Skip when they can be played.",
		"health": 8,
		"attack_interval": 2,
		"attack_damage": 1,
		"prioritize_actions": true,
	},
}


static func get_profile(id: String) -> Dictionary:
	# Preserve the Standard fallback without exposing the shared dictionary to mutation.
	return PROFILES.get(id, PROFILES["standard"]).duplicate(true)


static func is_valid(id: String) -> bool:
	if not PROFILES.has(id):
		return false
	return is_valid_profile(PROFILES[id])


static func is_valid_profile(profile: Dictionary) -> bool:
	return profile.get("name") is String \
		and profile.get("description") is String \
		and profile.get("health") is int and profile["health"] > 0 \
		and profile.get("attack_interval") is int and profile["attack_interval"] > 0 \
		and profile.get("attack_damage") is int and profile["attack_damage"] >= 0 \
		and profile.get("prioritize_actions") is bool
