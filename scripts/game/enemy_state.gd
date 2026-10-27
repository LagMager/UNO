extends RefCounted

## Mutable state for the enemy in one encounter. Attack timing is derived from
## Encounter.completed_rounds, so there is no separate cooldown to synchronize.
var id: String
var health: int
var hand: Array[Card] = []


func _init(profile_id: String, starting_health: int) -> void:
	id = profile_id
	health = starting_health
