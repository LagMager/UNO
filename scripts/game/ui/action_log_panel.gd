class_name ActionLogPanel
extends PanelContainer

@onready var enemy_label: Label = $LogMargin/LogColumn/EnemyLabel
@onready var enemy_behavior_label: Label = $LogMargin/LogColumn/EnemyBehaviorLabel
@onready var entries_label: RichTextLabel = $LogMargin/LogColumn/Entries


func render_log(encounter: RefCounted) -> void:
	var profile: Dictionary = encounter.enemy_profile()
	enemy_label.text = "Enemy cards: %d" % encounter.enemy_hand.size()
	var rounds_until_attack: int = profile["attack_interval"] - encounter.completed_rounds % profile["attack_interval"]
	enemy_behavior_label.text = "Attack: %d damage in %d round%s\nUNO: %s" % [
		profile["attack_damage"],
		rounds_until_attack,
		"" if rounds_until_attack == 1 else "s",
		"action cards first" if profile["prioritize_actions"] else "first playable card"
	]
	entries_label.text = "\n\n".join(encounter.events)
