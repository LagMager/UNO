class_name RunSession
extends RefCounted

const Encounter = preload("res://scripts/game/encounter.gd")
const EnemyProfiles = preload("res://scripts/game/enemy_profiles.gd")
const RewardSystem = preload("res://scripts/game/reward_system.gd")
const RunStateScript = preload("res://scripts/run/run_state.gd")
const EncounterDataScript = preload("res://scripts/content/encounter_data.gd")

const MODE_SINGLE := "single"
const MODE_RUN := "run"
const MODE_MAP := "map"
const BETWEEN_FIGHT_RECOVERY := 3

var encounter: RefCounted
var mode := ""
var run_index := 0
var reward_choices: Array[Card] = []
var reward_resolved := false
var map_run_state: RunStateScript = null
var active_encounter_data: EncounterDataScript = null
var _last_synced_result := ""


func _init(p_encounter: RefCounted = null) -> void:
	encounter = p_encounter if p_encounter != null else Encounter.new()


func start_single(enemy_id: String) -> bool:
	mode = MODE_SINGLE
	run_index = 0
	map_run_state = null
	active_encounter_data = null
	encounter.player_deck.reset_to_starter()
	return _begin_encounter(enemy_id, Encounter.STARTING_HEALTH)


func start_run() -> bool:
	mode = MODE_RUN
	run_index = 0
	map_run_state = null
	active_encounter_data = null
	encounter.player_deck.reset_to_starter()
	return _begin_encounter(EnemyProfiles.ORDER[0], Encounter.STARTING_HEALTH)


func start_map_encounter(p_run_state: RunStateScript, encounter_data: EncounterDataScript) -> bool:
	if p_run_state == null or encounter_data == null or not encounter_data.is_valid():
		return false
	mode = MODE_MAP
	map_run_state = p_run_state
	active_encounter_data = encounter_data
	encounter.player_deck = p_run_state.player_deck
	if not encounter.start_encounter_from_data(encounter_data, p_run_state.current_health):
		return false
	reward_choices.clear()
	reward_resolved = false
	_last_synced_result = ""
	return true


func advance_run() -> bool:
	if not can_advance_run():
		return false
	var next_health: int = mini(encounter.player_health + BETWEEN_FIGHT_RECOVERY, Encounter.STARTING_HEALTH)
	run_index += 1
	return _begin_encounter(EnemyProfiles.ORDER[run_index], next_health)


func can_advance_run() -> bool:
	if mode == MODE_MAP:
		return encounter.result == "Victory"
	return mode == MODE_RUN and encounter.result == "Victory" and run_index < EnemyProfiles.ORDER.size() - 1


func restart() -> bool:
	if mode == MODE_RUN:
		return start_run()
	if mode == MODE_SINGLE:
		return start_single(encounter.enemy_id)
	return false


func sync_rewards() -> void:
	var allow_rewards: bool = active_encounter_data == null or active_encounter_data.offers_card_reward
	if encounter.result == "Victory" and _last_synced_result != "Victory":
		if allow_rewards:
			reward_choices = RewardSystem.generate_card_rewards(RewardSystem.DEFAULT_REWARD_COUNT)
			reward_resolved = false
		else:
			reward_choices.clear()
			reward_resolved = true
	elif encounter.result != "Victory":
		reward_choices.clear()
		reward_resolved = false
	_last_synced_result = encounter.result


func has_active_rewards() -> bool:
	return encounter.result == "Victory" and not reward_resolved and not reward_choices.is_empty()


func claim_reward(index: int) -> bool:
	if reward_resolved or index < 0 or index >= reward_choices.size():
		return false
	var chosen_card: Card = reward_choices[index]
	if RewardSystem.claim_reward(encounter.player_deck, chosen_card):
		reward_resolved = true
		encounter.events.push_front("Reward: Added %s to your deck." % chosen_card.get_label())
		return true
	return false


func skip_reward() -> bool:
	if reward_resolved:
		return false
	reward_resolved = true
	encounter.events.push_front("Reward: Skipped card reward.")
	return true


func status_text() -> String:
	var status: String = encounter.result.to_upper() if encounter.phase == Encounter.PHASE_FINISHED else "Round %d — Your turn" % (encounter.completed_rounds + 1)
	if mode == MODE_RUN and encounter.phase == Encounter.PHASE_FINISHED:
		if encounter.result == "Defeat":
			status = "RUN ENDED — DEFEAT"
		elif run_index == EnemyProfiles.ORDER.size() - 1:
			status = "RUN COMPLETE — VICTORY"
	return "%s  |  Your HP: %d" % [status, maxi(encounter.player_health, 0)]


func progress_text() -> String:
	var profile: Dictionary = encounter.enemy_profile()
	if mode == MODE_MAP and map_run_state != null:
		return "Map expedition · %s  |  Gold: %d" % [profile["name"], map_run_state.gold]
	if mode == MODE_RUN:
		return "Encounter %d / %d · %s" % [run_index + 1, EnemyProfiles.ORDER.size(), profile["name"]]
	return "Single encounter · %s" % profile["name"]


func _begin_encounter(enemy_id: String, health: int) -> bool:
	if not encounter.start_encounter(enemy_id, health):
		return false
	reward_choices.clear()
	reward_resolved = false
	_last_synced_result = ""
	return true
