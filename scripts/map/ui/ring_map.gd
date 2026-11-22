class_name RingMap
extends Control

## The map as the circles of Hell seen from above: rings one inside the other, each band a
## zone of the descent (world design doc: the Mesquite, then the circles), the pit burning
## at the center. You start at the outer rim; every floor is a step inward and down.
## Each band carries its own inked drawings (thorn trees, gallows and broken rails, winds),
## and its name lettered along the curve. Drag to look around, wheel to zoom.
## The node buttons stay on top (MapGraphCanvas); this tells them where to stand.

const ZONES := [
	{"name": "THE MESQUITE", "circle": "Before the first circle", "hand": "The Mesquite", "line": "A thorny wood with no light at all. Sinners and desert beasts come out of the dark.",
		"tint": Color(0.17, 0.12, 0.08)},
	{"name": "LIMBO", "circle": "The first circle", "hand": "Limbo, the first circle", "line": "Scorched earth, chains and gallows. Grey shades that forbid your special cards.",
		"tint": Color(0.13, 0.125, 0.12)},
	{"name": "LUST", "circle": "The second circle", "hand": "Lust, the second circle", "line": "Winds of ash and sand drag the souls round and round, and swap the cards in your hand.",
		"tint": Color(0.17, 0.065, 0.05)},
]
const PIT := {"name": "THE PIT", "circle": "At the bottom", "hand": "The Pit", "line": "At the bottom, someone deals the last hand."}
const INK := Color(0.02, 0.015, 0.012, 1)
const RIM_INK := Color(0.55, 0.46, 0.36, 0.7)
const DRAW_INK := Color(0.05, 0.035, 0.03, 0.85)
const LABEL := Color(0.66, 0.6, 0.5, 1)
const OUTER := 760.0          # radius of the first floor's ring (map units)
const INNER := 150.0          # radius of the last floor before the pit
const NODE_GAP := 112.0       # map units between the options of one floor, along its ring

var _total_floors := 7
var _columns := 5
var _time := 0.0
var _scale := 1.0
var _scale_goal := 1.0
var _cam := Vector2(0, -620)          # map point at the middle of the panel
var _cam_goal := Vector2(0, -620)
var _decor: Array = []                # [kind, angle, radius, size, seed]
var _rng := RandomNumberGenerator.new()
## Baked: drawn straight from above as the ground texture of the 3D map (Inferno3D):
## the pit at the middle, BAKE_HALF map units to each edge, no camera, no vignette.
var baked := false
var _lw := 1.0      # line width factor (2.6 when baked)
const BAKE_HALF := 1300.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func terraces() -> int:
	return maxi(_total_floors - 1, 1)


func set_layout(total_floors: int, columns: int) -> void:
	_columns = maxi(columns, 1)
	if maxi(total_floors, 2) == _total_floors and not _decor.is_empty():
		return
	_total_floors = maxi(total_floors, 2)
	_build_decor()


func zone_of_floor(floor_index: int) -> int:
	if floor_index >= _total_floors - 1:
		return -1
	return clampi(int(float(floor_index) * ZONES.size() / terraces()), 0, ZONES.size() - 1)


func zone_info(zone: int) -> Dictionary:
	return PIT if zone < 0 else ZONES[zone]


# ------------------------------------------------------------------ geometry (map units, pit at 0,0)
func _floor_radius(f: int) -> float:
	return lerpf(OUTER, INNER, float(f) / maxf(terraces() - 1, 1))


func _half_step() -> float:
	return (_floor_radius(0) - _floor_radius(1)) * 0.5 if terraces() > 1 else 60.0


## Outer and inner radius of a zone's band.
func _band(zone: int) -> Vector2:
	var first := -1
	var last := -1
	for f: int in range(terraces()):
		if zone_of_floor(f) == zone:
			if first < 0:
				first = f
			last = f
	return Vector2(_floor_radius(first) + _half_step(), _floor_radius(last) - _half_step())


func _pit_radius() -> float:
	return _band(ZONES.size() - 1).y


func world_pos_of(floor_index: int, column: int) -> Vector3:
	if floor_index >= _total_floors - 1:
		return Vector3(0, 0, 0)
	var r := _floor_radius(floor_index)
	var gap := minf(NODE_GAP / r, PI * 0.85 / maxf(_columns - 1, 1))
	var ang := -PI * 0.5 + (float(column) - (_columns - 1) * 0.5) * gap
	return Vector3(cos(ang) * r, sin(ang) * r, 0)


func screen_pos_of(world: Vector3) -> Vector2:
	return (Vector2(world.x, world.y) - _cam) * _scale + size * 0.5


# ------------------------------------------------------------------ looking around
## Moves the view by a drag (screen pixels).
func pan(screen_delta: Vector2) -> void:
	_cam_goal -= screen_delta / _scale
	_cam = _cam_goal
	_clamp()


func zoom_by(factor: float, at_screen: Vector2) -> void:
	var before := (at_screen - size * 0.5) / _scale_goal + _cam_goal
	_scale_goal = clampf(_scale_goal * factor, 0.55, 2.2)
	_cam_goal = before - (at_screen - size * 0.5) / _scale_goal
	_clamp()


func zoom_to(world: Vector3) -> void:
	_cam_goal = Vector2(world.x, world.y) + Vector2(120, 0) / 1.7   # leave room for the details panel
	_scale_goal = 1.7


func zoom_out() -> void:
	_scale_goal = 1.0


## Centers the view on where you can go next.
func focus_on(points: Array) -> void:
	if points.is_empty():
		return
	var c := Vector2.ZERO
	for p: Vector3 in points:
		c += Vector2(p.x, p.y)
	_cam_goal = c / points.size() + Vector2(0, 160)
	_clamp()


func _clamp() -> void:
	_cam_goal.x = clampf(_cam_goal.x, -OUTER, OUTER)
	_cam_goal.y = clampf(_cam_goal.y, -OUTER - 60.0, 200.0)


# ------------------------------------------------------------------ drawings on the bands
func _build_decor() -> void:
	_decor.clear()
	_rng.seed = 4242
	for z: int in range(ZONES.size()):
		var b := _band(z)
		var count := int((b.x + b.y) * 0.5 * TAU / 70.0)
		for k: int in range(count):
			var a := _rng.randf() * TAU
			# between the floor rings, where the nodes don't stand
			var r := lerpf(b.y + 14.0, b.x - 14.0, _rng.randf())
			var near_ring := false
			for f: int in range(terraces()):
				if absf(r - _floor_radius(f)) < 26.0:
					near_ring = true
			if near_ring:
				continue
			_decor.append([z, a, r, _rng.randf_range(0.7, 1.3), _rng.randi()])


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if baked:
		_cam = Vector2.ZERO
		_scale = size.x / (2.0 * BAKE_HALF)
		_lw = 2.6
		queue_redraw()
		return
	var k := 1.0 - exp(-delta * 6.0)
	_cam = _cam.lerp(_cam_goal, k)
	_scale = lerpf(_scale, _scale_goal, k)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.016, 0.015))
	draw_set_transform(size * 0.5 - _cam * _scale, 0.0, Vector2(_scale, _scale))
	var c := Vector2.ZERO
	# outside the rim: dark rock
	draw_circle(c, OUTER + _half_step() + 520.0, Color(0.16, 0.13, 0.11) if baked else Color(0.06, 0.048, 0.042))
	if baked:
		_draw_outside(c)
	# the bands, outer to inner: each darker toward its inner edge (the ground slopes down),
	# with a deep shadow where it drops to the next one
	for z: int in range(ZONES.size()):
		var b := _band(z)
		var tint: Color = ZONES[z]["tint"]
		var steps := 10
		for i: int in range(steps):
			var u := float(i) / steps
			var r0 := lerpf(b.x, b.y, u)
			var r1 := lerpf(b.x, b.y, u + 1.0 / steps)
			var col := tint.lightened(0.16) if baked else tint
			draw_arc(c, (r0 + r1) * 0.5, 0, TAU, 220, col.darkened(u * 0.4), r0 - r1 + 1.0)
		draw_arc(c, b.y + 9.0, 0, TAU, 220, Color(0, 0, 0, 0.55), 18.0)
		_ragged_circle(c, b.x, RIM_INK, 3.0 * _lw, z * 7)
	# faint rings for each floor (the steps of the descent)
	for f: int in range(terraces()):
		_ragged_circle(c, _floor_radius(f), Color(RIM_INK.r, RIM_INK.g, RIM_INK.b, 0.3 if baked else 0.16), 1.5 * _lw, f + 20)
	for d: Array in _decor:
		_draw_decor(c, d)
	for z: int in range(ZONES.size()):
		var b := _band(z)
		if not baked:      # (in 3D the names are crisp labels over the view instead)
			_curved_text(c, (b.x + b.y) * 0.5, -PI * 0.5 - 0.55 + z * 0.06, ZONES[z]["name"], 22, LABEL)
	_draw_pit(c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if baked:
		return
	# a dark vignette over everything
	for i: int in range(6):
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.14), false, 26.0 + i * 24.0)


## Beyond the circles (the 3D map only): the rocky bank cracked and strewn with stones, and the
## river Acheron going all the way round, black water with ripples, Charon's boat crossing it
## slowly with its lantern lit.
const RIVER_IN := 45.0        # from the first band's outer edge
const RIVER_OUT := 110.0


func river_mid() -> float:
	return OUTER + _half_step() + (RIVER_IN + RIVER_OUT) * 0.5


func _draw_outside(c: Vector2) -> void:
	var rim := OUTER + _half_step()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	# cracks and stones on the bank, inside and outside the river
	for k: int in range(220):
		var a := rng.randf() * TAU
		var r := rim + rng.randf_range(12.0, 500.0)
		if r > rim + RIVER_IN - 8.0 and r < rim + RIVER_OUT + 8.0:
			continue
		var p := c + Vector2(cos(a), sin(a)) * r
		if rng.randf() < 0.55:
			draw_circle(p, rng.randf_range(4.0, 11.0), Color(0.26, 0.22, 0.19))
		else:
			var d := Vector2(cos(a + rng.randf_range(-1, 1)), sin(a + rng.randf_range(-1, 1)))
			draw_line(p, p + d * rng.randf_range(14.0, 40.0), Color(0.02, 0.015, 0.012), 2.0 * _lw)
	# the river: deep and dark in the middle, paler toward the banks
	var r_in := rim + RIVER_IN
	var r_out := rim + RIVER_OUT
	var bands := 8
	for i: int in range(bands):
		var u := (i + 0.5) / bands
		var depth := 1.0 - absf(u - 0.5) * 2.0                 # 1 in the middle, 0 at the banks
		var col := Color(0.12, 0.17, 0.22).lerp(Color(0.03, 0.05, 0.1), depth)
		draw_arc(c, lerpf(r_in, r_out, u), 0, TAU, 240, col, (r_out - r_in) / bands + 1.0)
	# the current: long streaks drifting round, faster in the middle
	for k: int in range(70):
		var lane := fmod(k * 0.618, 1.0)
		var speed := 0.02 + 0.03 * (1.0 - absf(lane - 0.5) * 2.0)
		var a := k * TAU / 70.0 + _time * speed
		var r := lerpf(r_in + 10.0, r_out - 10.0, lane)
		draw_arc(c, r, a, a + 0.04 + 0.05 * fmod(k * 0.37, 1.0), 6, Color(0.3, 0.4, 0.5, 0.5), 1.6 * _lw)
	# eddies turning in the water
	for k: int in range(10):
		var a := k * TAU / 10.0 + _time * 0.035 + sin(k * 3.3)
		var ep := c + Vector2(cos(a), sin(a)) * lerpf(r_in + 25.0, r_out - 25.0, fmod(k * 0.41, 1.0))
		var spin := _time * 1.2 + k
		var pts := PackedVector2Array()
		for s: int in range(10):
			var u := float(s) / 9.0
			pts.append(ep + Vector2(cos(spin + u * 5.0), sin(spin + u * 5.0)) * (2.0 + u * 9.0))
		draw_polyline(pts, Color(0.35, 0.45, 0.55, 0.45), 1.4 * _lw)
	# foam breaking along both banks
	for bank: float in [r_in + 5.0, r_out - 5.0]:
		for k: int in range(90):
			var a := k * TAU / 90.0 + sin(_time * 0.8 + k) * 0.01
			if fmod(k * 0.53 + _time * 0.2, 1.0) < 0.35:
				continue
			draw_arc(c, bank, a, a + 0.025, 4, Color(0.6, 0.65, 0.7, 0.6), 2.2 * _lw)
	# the bank fades into the dark: no edge to the world
	var fade_from := r_out + 140.0
	for i: int in range(24):
		var u := float(i) / 24.0
		var r := lerpf(fade_from, BAKE_HALF * 1.05, u)
		draw_arc(c, r, 0, TAU, 160, Color(0, 0, 0, smoothstep(0.0, 1.0, u)), (BAKE_HALF * 1.05 - fade_from) / 24.0 + 2.0)
	_ragged_circle(c, r_in, Color(0.25, 0.22, 0.2, 0.9), 2.5 * _lw, 3)
	_ragged_circle(c, r_out, Color(0.25, 0.22, 0.2, 0.9), 2.5 * _lw, 9)
	# Charon's boat, slowly crossing round, its lantern lit
	var ba := -_time * 0.04
	var bp := c + Vector2(cos(ba), sin(ba)) * (rim + (RIVER_IN + RIVER_OUT) * 0.5)
	var tan := Vector2(-sin(ba), cos(ba))
	var nor := Vector2(cos(ba), sin(ba))
	var hull := PackedVector2Array([bp + tan * 34.0, bp + tan * 14.0 + nor * 11.0, bp - tan * 30.0 + nor * 9.0,
		bp - tan * 34.0, bp - tan * 30.0 - nor * 9.0, bp + tan * 14.0 - nor * 11.0])
	draw_colored_polygon(hull, Color(0.16, 0.1, 0.06))
	draw_circle(bp - tan * 18.0, 7.0, Color(0.08, 0.07, 0.07))              # the ferryman
	for i: int in range(4):
		draw_circle(bp + tan * 26.0, 10.0 + i * 8.0, Color(1.0, 0.6, 0.2, 0.08))
	draw_circle(bp + tan * 26.0, 4.0, Color(1.0, 0.75, 0.35))
	for i: int in range(6):
		var q := bp + tan * 26.0 + nor * (14.0 + i * 7.0) + tan * sin(_time * 6.0 + i) * 3.0
		draw_line(q - tan * (6.0 - i * 0.6), q + tan * (6.0 - i * 0.6), Color(1.0, 0.6, 0.2, 0.5 - i * 0.07), 2.0 * _lw)


func _ragged_circle(c: Vector2, r: float, col: Color, width: float, seed: int) -> void:
	var pts := PackedVector2Array()
	var n := 220
	for i: int in range(n + 1):
		var a := TAU * i / n
		var wob := sin(a * 9.0 + seed) * 2.0 + sin(a * 23.0 + seed * 1.7) * 1.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r + wob))
	draw_polyline(pts, col, width)


## The zone's name lettered along its band, each letter turned with the curve.
func _curved_text(c: Vector2, r: float, start: float, text: String, fs: int, col: Color) -> void:
	var font := get_theme_default_font()
	var a := start
	for ch: String in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var mid := a + (w * 0.5) / r
		var p := c + Vector2(cos(mid), sin(mid)) * r
		draw_set_transform(size * 0.5 - _cam * _scale + p * _scale, mid + PI * 0.5, Vector2(_scale, _scale))
		draw_string_outline(font, Vector2(-w * 0.5, fs * 0.35), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, INK)
		draw_string(font, Vector2(-w * 0.5, fs * 0.35), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		a += (w + 2.0) / r
	draw_set_transform(size * 0.5 - _cam * _scale, 0.0, Vector2(_scale, _scale))


func _draw_decor(c: Vector2, d: Array) -> void:
	var zone: int = d[0]
	var a: float = d[1]
	var r: float = d[2]
	var s: float = d[3] * (1.8 if baked else 1.0)
	var p := c + Vector2(cos(a), sin(a)) * r
	var rng := RandomNumberGenerator.new()
	rng.seed = d[4]
	match zone:
		0:
			# a twisted, thorny mesquite tree, seen from above-ish: a trunk forking into claws
			_branch(p, -PI * 0.5 + rng.randf_range(-0.4, 0.4), 16.0 * s, 3.0 * s, 3, rng)
		1:
			if rng.randf() < 0.5:
				# gallows: a post, a beam, a hanging rope
				draw_line(p, p + Vector2(0, -26) * s, DRAW_INK, 3.0 * _lw)
				draw_line(p + Vector2(0, -26) * s, p + Vector2(14, -26) * s, DRAW_INK, 3.0 * _lw)
				draw_line(p + Vector2(12, -26) * s, p + Vector2(12, -15) * s, DRAW_INK, 1.5 * _lw)
				draw_circle(p + Vector2(12, -13) * s, 2.5 * s, DRAW_INK)
			else:
				# a stretch of broken rail along the ring
				var t := Vector2(-sin(a), cos(a))
				var n := Vector2(cos(a), sin(a))
				for k: int in range(5):
					var q := p + t * (k - 2) * 7.0 * s
					draw_line(q - n * 6.0 * s, q + n * 6.0 * s, DRAW_INK, 2.0 * _lw)
				draw_line(p - t * 18.0 * s + n * 3.5 * s, p + t * 10.0 * s + n * 3.5 * s, DRAW_INK, 1.5 * _lw)
				draw_line(p - t * 14.0 * s - n * 3.5 * s, p + t * 18.0 * s - n * 3.5 * s, DRAW_INK, 1.5 * _lw)
		2:
			# a gust of wind going round: a curl that turns slowly with time
			var spin := _time * 0.35 + float(d[4] % 100)
			var pts := PackedVector2Array()
			for k: int in range(14):
				var u := float(k) / 13.0
				var aa := spin + u * 4.5
				pts.append(p + Vector2(cos(aa), sin(aa)) * (3.0 + u * 13.0) * s)
			draw_polyline(pts, Color(0.55, 0.3, 0.22, 0.5), 1.8 * _lw)


func _branch(p: Vector2, ang: float, length: float, width: float, depth: int, rng: RandomNumberGenerator) -> void:
	var q := p + Vector2(cos(ang), sin(ang)) * length
	draw_line(p, q, DRAW_INK, maxf(width, 1.0) * _lw)
	if depth <= 0:
		# a thorn
		draw_line(q, q + Vector2(cos(ang + 0.6), sin(ang + 0.6)) * 3.0, DRAW_INK, 1.0 * _lw)
		return
	for k: int in range(2):
		_branch(q, ang + (k * 2 - 1) * rng.randf_range(0.3, 0.7), length * 0.68, width * 0.65, depth - 1, rng)


## The pit: a burning hole, flames licking up all round its edge.
func _draw_pit(c: Vector2) -> void:
	var r := _pit_radius()
	for i: int in range(12):
		var g := Color(0.8, 0.14, 0.05, 0.07 + 0.015 * sin(_time * 1.3))
		draw_circle(c, r * (1.15 - i * 0.08), g)
	draw_circle(c, r * 0.55, Color(0.05, 0.01, 0.01, 0.9))
	var n := 22
	for i: int in range(n):
		var a := TAU * i / n
		var h := (10.0 + 7.0 * sin(_time * 3.0 + i * 1.7)) * (0.8 + 0.2 * sin(i * 3.1))
		var base := c + Vector2(cos(a), sin(a)) * r * 0.8
		var tip := c + Vector2(cos(a), sin(a)) * (r * 0.8 + h)
		var side := Vector2(-sin(a), cos(a)) * 5.0
		draw_colored_polygon(PackedVector2Array([base - side, tip, base + side]), Color(0.95, 0.38, 0.1, 0.8))
