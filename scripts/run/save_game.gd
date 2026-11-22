class_name SaveGame
extends RefCounted

## Runs kept on disk between sessions, in three slots (user://save_<n>.json), shown in the
## main menu as papers in the dresser drawer.
## The run you are playing is written to its slot every time you are back on the map (so a
## fight or a shop you quit halfway starts again from the map), and erased when the run
## ends, won or lost. The map is not stored: it is rebuilt from its seed, then the progress
## is laid on top.

const SLOTS := 3
const VERSION := 2

## The slot the run being played goes to.
static var slot := 0
## Where the slots live. Tests point this elsewhere so they never touch the player's runs.
static var root := "user://"


static func path(s: int) -> String:
	if root != "user://":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	return root.path_join("save_%d.json" % s)


static func exists(s: int = -1) -> bool:
	if s >= 0:
		return FileAccess.file_exists(path(s))
	for i: int in range(SLOTS):
		if FileAccess.file_exists(path(i)):
			return true
	return false


static func clear(s: int = -2) -> void:
	var which := slot if s == -2 else s
	if which >= 0 and exists(which):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(which)))


## A new run takes the first empty slot, or the one saved longest ago.
static func pick_slot_for_new_run() -> int:
	var oldest := 0
	var oldest_time := INF
	for i: int in range(SLOTS):
		var info := peek(i)
		if info.is_empty():
			return i
		if float(info.get("saved_at", 0)) < oldest_time:
			oldest_time = float(info.get("saved_at", 0))
			oldest = i
	return oldest


## What the drawer shows of a slot ({} if empty): circle, health, gold, saved_at.
static func peek(s: int) -> Dictionary:
	if not exists(s):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path(s)))
	if typeof(parsed) != TYPE_DICTIONARY or int((parsed as Dictionary).get("version", 0)) != VERSION:
		return {}
	return parsed


## circle / circle_short: where the run is, for its paper in the drawer.
static func save(state: RunState, circle := "", circle_short := "") -> bool:
	if state == null or state.map_data == null or state.run_finished:
		return false
	var data := state.to_dict()
	data["version"] = VERSION
	data["active_interaction_node_id"] = ""      # always back on the map when loaded
	data["saved_at"] = Time.get_unix_time_from_system()
	data["circle"] = circle
	data["circle_short"] = circle_short
	var here: MapNodeData = state.map_data.get_node(state.current_node_id) if not state.current_node_id.is_empty() else null
	data["step"] = here.floor_index if here != null else -1
	var deck: Array = []
	for card: Card in state.player_deck.cards():
		deck.append({
			"id": card.instance_id, "color": int(card.color), "kind": int(card.kind),
			"number": card.number, "upgraded": card.is_upgraded, "bonus": card.bonus_damage,
			"actions": card.extra_actions, "skips": card.skips_next_uno, "modifier": card.modifier,
		})
	data["deck"] = deck
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: cannot write %s" % path(slot))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


## Restores slot `s` into the controller (and keeps saving there). Returns false if it is
## empty or unreadable (an unreadable one is erased).
static func load_into(controller: RunController, s: int = -1) -> bool:
	var which := slot if s < 0 else s
	var data := peek(which)
	if data.is_empty():
		clear(which)
		return false
	slot = which
	controller.start_new_run(int(data.get("generation_seed", MapGenerator.DEFAULT_SEED)))
	var state := controller.run_state
	var cards: Array[Card] = []
	for c: Variant in data.get("deck", []):
		var d: Dictionary = c
		var card := Card.new(int(d.get("color", 0)) as Card.CardColor, int(d.get("kind", 0)) as Card.Kind, int(d.get("number", -1)))
		card.instance_id = str(d.get("id", card.instance_id))
		card.color = int(d.get("color", 0)) as Card.CardColor
		card.is_upgraded = bool(d.get("upgraded", false))
		card.bonus_damage = int(d.get("bonus", 0))
		card.extra_actions = int(d.get("actions", 0))
		card.skips_next_uno = bool(d.get("skips", false))
		card.modifier = str(d.get("modifier", "none"))
		cards.append(card)
	if not cards.is_empty():
		state.player_deck.load_cards(cards)
	state.load_progression_dict(data)
	return true
