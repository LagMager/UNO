class_name MenuBackdrop
extends Control

## Desert at dusk with parallax layers that scroll forever, plus small living
## details: a tumbleweed rolling past, vultures gliding, dust in the air.
## speed_scale lets the map screen use a calmer version of the same backdrop.

const SKY := preload("res://assets/menu/sky.png")
const LAYERS := [
	[preload("res://assets/menu/clouds.png"), 6.0],
	[preload("res://assets/menu/mesas_far.png"), 10.0],
	[preload("res://assets/menu/mesas_mid.png"), 24.0],
	[preload("res://assets/menu/ground_near.png"), 70.0],
]
const ART_H := 1080.0

@export var speed_scale := 1.0

var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _dust: Array[Dictionary] = []
var _weed_x := -1.0
var _weed_wait := 3.0
var _weed_angle := 0.0
var _weed_strokes: Array[PackedVector2Array] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	for i: int in range(45):
		_dust.append(_new_mote(true))
	# tumbleweed: a tangle of random arcs
	for i: int in range(14):
		var arc := PackedVector2Array()
		var r := _rng.randf_range(0.45, 1.0)
		var a0 := _rng.randf() * TAU
		var span := _rng.randf_range(1.5, 4.0)
		for k: int in range(10):
			var a := a0 + span * k / 9.0
			arc.append(Vector2(cos(a), sin(a)) * r * _rng.randf_range(0.85, 1.05))
		_weed_strokes.append(arc)


func _new_mote(anywhere: bool) -> Dictionary:
	return {
		"p": Vector2(_rng.randf() if anywhere else 1.05, _rng.randf_range(0.35, 0.95)),
		"v": Vector2(-_rng.randf_range(0.01, 0.04), _rng.randf_range(-0.004, 0.004)),
		"r": _rng.randf_range(1.0, 2.6),
		"phase": _rng.randf() * TAU,
	}


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta * speed_scale
	for i: int in range(_dust.size()):
		var m: Dictionary = _dust[i]
		m["p"] += m["v"] * delta * speed_scale
		if m["p"].x < -0.05:
			_dust[i] = _new_mote(false)
	if _weed_x < 0.0:
		_weed_wait -= delta * speed_scale
		if _weed_wait <= 0.0:
			_weed_x = 1.1
	else:
		_weed_x -= delta * 0.16 * speed_scale
		_weed_angle -= delta * 5.0 * speed_scale
		if _weed_x < -0.1:
			_weed_x = -1.0
			_weed_wait = _rng.randf_range(6.0, 12.0)
	queue_redraw()


func _draw() -> void:
	var s := maxf(size.x / 1920.0, size.y / ART_H)
	var sky_size := Vector2(1920, ART_H) * s
	draw_texture_rect(SKY, Rect2((size - sky_size) * 0.5, sky_size), false)
	for layer: Array in LAYERS:
		var tex: Texture2D = layer[0]
		var w: float = tex.get_width() * s
		var h: float = ART_H * s
		var y := (size.y - h) * 0.5
		var off: float = fmod(_time * layer[1] * s, w)
		var x := -off
		while x < size.x:
			draw_texture_rect(tex, Rect2(Vector2(x, y), Vector2(w, h)), false)
			x += w
	_draw_vultures(s)
	_draw_tumbleweed(s)
	for m: Dictionary in _dust:
		var tw := 0.5 + 0.5 * sin(_time * 1.7 + m["phase"])
		draw_circle(Vector2(m["p"].x * size.x, m["p"].y * size.y), m["r"] * s * 1.5, Color(1.0, 0.82, 0.55, 0.25 * tw))


func _draw_vultures(s: float) -> void:
	for i: int in range(2):
		var t := _time * (0.22 + i * 0.05) + i * 2.4
		var center := Vector2(size.x * (0.3 + i * 0.12), size.y * (0.22 + i * 0.05))
		var p := center + Vector2(cos(t) * 90.0, sin(t) * 26.0) * s * 1.5
		var flap := sin(_time * 3.0 + i) * 0.25
		var w := 16.0 * s * 1.5
		var col := Color(0.1, 0.06, 0.08, 0.9)
		draw_polyline(PackedVector2Array([p + Vector2(-w, -w * (0.35 + flap)), p + Vector2(-w * 0.45, -w * 0.1), p,
			p + Vector2(w * 0.45, -w * 0.1), p + Vector2(w, -w * (0.35 + flap))]), col, 2.5 * s * 1.5, true)


func _draw_tumbleweed(s: float) -> void:
	if _weed_x < 0.0:
		return
	var ground_y := size.y * 0.5 + (0.85 - 0.5) * ART_H * s
	var radius := 30.0 * s * 1.5
	var bounce := absf(sin(_weed_x * 22.0)) * 26.0 * s
	var c := Vector2(_weed_x * size.x, ground_y - radius - bounce)
	var rot := Transform2D(_weed_angle, Vector2.ZERO)
	for arc: PackedVector2Array in _weed_strokes:
		var pts := PackedVector2Array()
		for p: Vector2 in arc:
			pts.append(c + rot * (p * radius))
		draw_polyline(pts, Color(0.2, 0.11, 0.08, 0.95), 2.0 * s * 1.5, true)
	draw_arc(c, radius * 0.98, -0.6, 0.6, 8, Color(1.0, 0.55, 0.3, 0.8), 2.0 * s * 1.5, true)
