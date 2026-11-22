class_name SelectionView
extends CenterContainer

signal single_encounter_requested(enemy_id: String)
signal run_requested
signal map_run_requested
## Open the shop on its own, just to look around and try it.
signal shop_requested
## Look at a zone on its own (the rest point, for now).
signal zone_requested(zone_id: String)
## The map's rest stop on its own: walk in, sit, choose (to try it without playing).
signal rest_requested

const EnemyProfiles = preload("res://scripts/game/enemy_profiles.gd")

@onready var choose_enemy_button: Button = $Panel/Padding/Choices/ChooseEnemyButton
@onready var enemy_choices: VBoxContainer = $Panel/Padding/Choices/EnemyChoices
@onready var run_button: Button = $Panel/Padding/Choices/ThreeEncounters
@onready var map_run_button: Button = $Panel/Padding/Choices/MapExpedition
@onready var shop_button: Button = get_node_or_null("Panel/Padding/Choices/VisitShop")
@onready var rest_point_button: Button = get_node_or_null("Panel/Padding/Choices/ViewRestPoint")
@onready var rest_button: Button = get_node_or_null("Panel/Padding/Choices/RestAtFire")


func _ready() -> void:
	choose_enemy_button.pressed.connect(toggle_enemy_choices)
	run_button.pressed.connect(func() -> void: run_requested.emit())
	if map_run_button != null:
		map_run_button.pressed.connect(func() -> void: map_run_requested.emit())
	if shop_button != null:
		shop_button.pressed.connect(func() -> void: shop_requested.emit())
	if rest_point_button != null:
		rest_point_button.pressed.connect(func() -> void: zone_requested.emit("rest_point"))
	if rest_button != null:
		rest_button.pressed.connect(func() -> void: rest_requested.emit())
	_populate_enemy_choices()


func reset_selection() -> void:
	enemy_choices.visible = false


func toggle_enemy_choices() -> void:
	enemy_choices.visible = not enemy_choices.visible


func request_single_encounter(enemy_id: String) -> void:
	single_encounter_requested.emit(enemy_id)


func request_run() -> void:
	run_requested.emit()


func _populate_enemy_choices() -> void:
	for child in enemy_choices.get_children():
		enemy_choices.remove_child(child)
		child.queue_free()
	for id: String in EnemyProfiles.ORDER:
		var profile: Dictionary = EnemyProfiles.get_profile(id)
		var button := Button.new()
		button.name = "%sButton" % profile["name"]
		button.text = "%s — %s" % [profile["name"], profile["description"]]
		button.custom_minimum_size.y = 42
		button.pressed.connect(request_single_encounter.bind(id))
		enemy_choices.add_child(button)
