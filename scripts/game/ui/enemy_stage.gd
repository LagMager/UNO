class_name EnemyStage
extends VBoxContainer

const ENEMY_COLOR := Color("#696969")
const HIT_COLOR := Color("#b75656")

@onready var enemy_rect: ColorRect = $Enemy
@onready var enemy_name_label: Label = $Enemy/EnemyName
@onready var enemy_health_label: Label = $EnemyHealthLabel
@onready var enemy_health_bar: ProgressBar = $EnemyHealth

var damage_popups: Array[Label] = []
var _hit_tween: Tween


func render_enemy(encounter: RefCounted) -> void:
	var profile: Dictionary = encounter.enemy_profile()
	enemy_name_label.text = profile["name"].to_upper()
	enemy_health_bar.max_value = profile["health"]
	enemy_health_bar.value = maxi(encounter.enemy_health, 0)
	enemy_health_label.text = "Enemy HP  %d / %d" % [maxi(encounter.enemy_health, 0), profile["health"]]


func show_hit(damage: int) -> void:
	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()
	enemy_rect.color = ENEMY_COLOR
	_hit_tween = create_tween()
	_hit_tween.tween_property(enemy_rect, "color", HIT_COLOR, 0.08)
	_hit_tween.tween_property(enemy_rect, "color", ENEMY_COLOR, 0.25)

	var popup := Label.new()
	popup.text = "-%d" % damage
	popup.add_theme_font_size_override("font_size", 32)
	popup.add_theme_color_override("font_color", Color("#ffd4d4"))
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_rect.add_child(popup)
	damage_popups.append(popup)
	popup.position = Vector2((enemy_rect.size.x - 60) * 0.5, enemy_rect.size.y * 0.45)
	var float_tween := popup.create_tween().set_parallel(true)
	float_tween.tween_property(popup, "position:y", popup.position.y - 62, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	float_tween.tween_property(popup, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	float_tween.chain().tween_callback(_finish_popup.bind(popup))


func clear_hit_effects() -> void:
	if _hit_tween and _hit_tween.is_running():
		_hit_tween.kill()
	enemy_rect.color = ENEMY_COLOR
	for popup in damage_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	damage_popups.clear()


func _finish_popup(popup: Label) -> void:
	damage_popups.erase(popup)
	popup.queue_free()
