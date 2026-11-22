class_name Inferno3D
extends SubViewportContainer

## The map in 3D: the circles of Hell as real terraces, one step down per floor, around a
## burning pit. The ground is the inked ring map itself (RingMap drawn from above into a
## texture: the bands, their names along the curve, thorn trees, gallows, winds), laid on
## the steps, so it reads like the 2D map but has depth, light and shadow, and the game's
## pixelated dither. Drag to move over it, wheel to zoom. The node buttons stay 2D on top;
## this tells them where to stand (screen_pos_of).

const RingMapScript = preload("res://scripts/map/ui/ring_map.gd")
const PIXEL_SHRINK := 3
const U := 0.01                 # meters per map unit
const STEP := 0.38              # how much lower each floor is
const PIT_DEPTH := 1.3
const TEX := 2048

var viewport: SubViewport
var camera: Camera3D
var _world: Node3D
var _rings: RingMapScript       # draws the ground texture
var _ground_vp: SubViewport
var _terrain: Node3D
var _spinners: Array[MeshInstance3D] = []   # one per zone: its terraces turn together
var _spin: Array[float] = []                  # their current angles
var _total_floors := 0
var _columns := 5
var _target := Vector3(0, -1.0, 0)        # the point the camera looks down at
var _target_goal := _target
var _dist := 19.0
var _dist_goal := 19.0
var _zoom_saved := 19.0
var _time := 0.0
var _env: Environment


func _ready() -> void:
	stretch = true
	stretch_shrink = PIXEL_SHRINK
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var dither := ShaderMaterial.new()
	dither.shader = preload("res://resources/shaders/pixel_dither.gdshader")
	dither.set_shader_parameter("contrast", 1.05)     # softer than the duel: the map is to be read
	material = dither
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the ink map, drawn from above, live (its winds turn, its pit burns)
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.own_world_3d = true
	add_child(viewport)
	_world = Node3D.new()
	viewport.add_child(_world)
	# (inside the 3D viewport, not in this container: the container shows every viewport it
	# holds, and this one was drawn over the 3D, all black)
	_ground_vp = SubViewport.new()
	_ground_vp.size = Vector2i(TEX, TEX)
	_ground_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(_ground_vp)
	_rings = RingMapScript.new()
	_rings.baked = true
	_rings.size = Vector2(TEX, TEX)
	_rings.theme = preload("res://resources/themes/western_theme.tres")
	_ground_vp.add_child(_rings)
	_build_light()
	set_layout(7, 5)


# ------------------------------------------------------------------ the map's interface
func set_layout(total_floors: int, columns: int) -> void:
	_columns = maxi(columns, 1)
	_rings.set_layout(total_floors, columns)
	if maxi(total_floors, 2) == _total_floors:
		return
	_total_floors = maxi(total_floors, 2)
	_build_terrain()


func zone_of_floor(floor_index: int) -> int:
	return _rings.zone_of_floor(floor_index)


func zone_info(zone: int) -> Dictionary:
	return _rings.zone_info(zone)


func _terraces() -> int:
	return maxi(_total_floors - 1, 1)


func _floor_y(f: int) -> float:
	return -STEP * f


## A node's place: on its floor's ring, on that floor's step.
func world_pos_of(floor_index: int, column: int) -> Vector3:
	var p: Vector3 = _rings.world_pos_of(floor_index, column)
	if floor_index >= _total_floors - 1:
		return Vector3(0, _floor_y(_terraces()) - PIT_DEPTH + 0.05, 0)
	var z := zone_of_floor(floor_index)
	var a: float = _spin[z] if z >= 0 and z < _spin.size() else 0.0
	return Basis(Vector3.UP, a) * Vector3(p.x * U, _floor_y(floor_index) + 0.02, p.y * U)


func screen_pos_of(world: Vector3) -> Vector2:
	if camera == null or camera.is_position_behind(world):
		return Vector2(-9999, -9999)
	return camera.unproject_position(world) * PIXEL_SHRINK


## Drag: the ground slides under the mouse.
func pan(screen_delta: Vector2) -> void:
	var per_px := _dist * 0.0016
	var right := camera.global_transform.basis.x
	var fwd := Vector3(-camera.global_transform.basis.z.x, 0, -camera.global_transform.basis.z.z).normalized()
	_target_goal += (-right * screen_delta.x + fwd * screen_delta.y) * per_px
	_clamp()
	_target = _target_goal


func zoom_by(factor: float, _at_screen: Vector2) -> void:
	_dist_goal = clampf(_dist_goal / factor, 6.0, 26.0)


## A closer look at one place (the details panel is open): the eye goes down to it.
func zoom_to(world: Vector3) -> void:
	_target_goal = world + Vector3(0.9, 0, 0)     # a little to the side: the panel is on the right
	_dist_goal = 4.2


## Back to the whole circle.
func zoom_out() -> void:
	set_current_zone(current_zone)


## A point on a circle's band, turning with it (angle: around the funnel, 0 = toward +X).
func zone_point(zone: int, angle: float) -> Vector3:
	var floors: Array[int] = []
	for f: int in range(_terraces()):
		if zone_of_floor(f) == zone:
			floors.append(f)
	if floors.is_empty():
		return Vector3.ZERO
	var r := (_rings._floor_radius(floors[0]) + _rings._floor_radius(floors[floors.size() - 1])) * 0.5 * U
	var a: float = angle + (_spin[zone] if zone < _spin.size() else 0.0)
	return Vector3(cos(a) * r, _floor_y(floors[0]), sin(a) * r)


## Kept for the map view (the eye now follows the circle you are in: set_current_zone).
func focus_on(_points: Array) -> void:
	pass


var current_zone := 0


## The circle you are in (-1: the pit). The eye hangs over it, framing just that ring and the
## depth below; when it changes, the eye descends to the next, slowly.
var _drop := -1.0      # >= 0 while falling to the next circle (seconds)


## Falls to a circle, hard: the eye drops fast and lands with a jolt.
func drop_to_zone(zone: int) -> void:
	set_current_zone(zone)
	_drop = 0.0


func set_current_zone(zone: int) -> void:
	current_zone = zone
	var n := _terraces()
	var floors: Array[int] = []
	for f: int in range(n):
		if zone_of_floor(f) == zone:
			floors.append(f)
	if floors.is_empty():
		# the pit: look straight down into it
		_target_goal = Vector3(0, _floor_y(n - 1) - PIT_DEPTH, 0)
		_dist_goal = 6.0
		return
	var outer := _rings._floor_radius(floors[0]) * U
	var y := (_floor_y(floors[0]) + _floor_y(floors[floors.size() - 1])) * 0.5
	_target_goal = Vector3(0, y, 0)
	# the first circle also shows what lies outside it (the river, the running souls)
	_dist_goal = (outer + 2.4) * 2.25 if zone == 0 else outer * 2.4


func _clamp() -> void:
	var r := Vector2(_target_goal.x, _target_goal.z).length()
	if r > 8.0:
		var v := Vector2(_target_goal.x, _target_goal.z) * (8.0 / r)
		_target_goal.x = v.x
		_target_goal.z = v.y


# ------------------------------------------------------------------ building
func _build_light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#030202")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b8a898")
	env.ambient_light_energy = 0.5        # the ink must read even in shadow, without washing out
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#050304")
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 50.0
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	camera = Camera3D.new()
	camera.fov = 45.0
	_world.add_child(camera)
	# a low, cold light from one side: every step throws its shadow on the one below
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#c9c2d8")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.rotation_degrees = Vector3(-64, -35, 0)     # high: each step only drops a short shadow on the next
	_world.add_child(sun)


## The terraces: flat rings at each floor's height, a cliff between each and the next, the
## pit at the middle, and the rim of rock rising round the outside. Normals are set by hand
## (up for the ground, toward the middle for the cliffs), so the light is right whatever the
## winding. The ground texture is the ink map, projected straight down.
func _build_terrain() -> void:
	if _terrain != null:
		_terrain.queue_free()
	_terrain = Node3D.new()
	_world.add_child(_terrain)
	_spinners.clear()
	_spin.clear()
	var seg := 160
	var n := _terraces()
	var radii: Array[float] = []        # the floors' rings, in meters
	for f: int in range(n):
		radii.append(_rings._floor_radius(f) * U)
	var half := (radii[0] - radii[1]) * 0.5 if n > 1 else 0.6
	var edges: Array[float] = [radii[0] + half]
	for f: int in range(n):
		edges.append(radii[f] - half)
	# the rim (fixed): a wall up from the first floor, then rock out to the edge
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim_y := _floor_y(0) + 1.4
	_rim_r = edges[0]
	_rim_y = rim_y
	_ring_top(st, edges[0], 13.0, rim_y, seg)
	_ring_wall(st, edges[0], rim_y, _floor_y(0), seg)
	_add_piece(st, false, false)     # the rim: no shadow (its wall darkened half the funnel)
	# each zone's terraces in one piece that turns on its own
	var zones := 0
	for f: int in range(n):
		zones = maxi(zones, zone_of_floor(f) + 1)
	for z: int in range(zones):
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f: int in range(n):
			if zone_of_floor(f) != z:
				continue
			_ring_top(st, edges[f + 1], edges[f], _floor_y(f), seg)
			var below := _floor_y(f + 1) if f + 1 < n else _floor_y(n - 1) - PIT_DEPTH
			_ring_wall(st, edges[f + 1], _floor_y(f), below, seg)
		_add_piece(st, true)
	# the pit (fixed)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring_top(st, 0.0, edges[n], _floor_y(n - 1) - PIT_DEPTH, seg)
	_add_piece(st, false)
	# the pit's fire lights the cliffs around it red
	var glow := OmniLight3D.new()
	glow.name = "PitGlow"
	glow.light_color = Color("#ff4a1c")
	glow.light_energy = 3.0
	glow.omni_range = 4.5
	glow.position = Vector3(0, _floor_y(n - 1) - PIT_DEPTH + 0.5, 0)
	_terrain.add_child(glow)
	_build_vestibule()
	_build_waiting()


var _ground_mat: StandardMaterial3D


# ------------------------------------------------------------------ the Vestibule
## Outside the circles (Inferno, canto III): the souls who never took a side run forever
## behind a blank banner that never stops, round and round the rim. Pale pixel-art figures
## (2D sprites standing in the 3D), running, two frames.
var _rim_r := 8.0
var _rim_y := 1.4
var _runners: Array[Sprite3D] = []
var _banner: Sprite3D
var _run_angle := 0.0


func _pixel_tex(rows: Array, col: Color) -> ImageTexture:
	var h := rows.size()
	var w := (rows[0] as String).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in range(h):
		var row: String = rows[y]
		for x: int in range(w):
			if row[x] == "x":
				img.set_pixel(x, y, col)
			elif row[x] == "o":
				img.set_pixel(x, y, col.darkened(0.55))
	return ImageTexture.create_from_image(img)


func _build_vestibule() -> void:
	_runners.clear()
	var pale := Color(0.8, 0.78, 0.72)
	var run_a := ["...xx...", "...xx...", "..xxxx..", ".x.xx.x.", "x..xx..x", "...xx...", "..x..x..", ".x....x.", "x......x"]
	var run_b := ["...xx...", "...xx...", "..xxxx..", "..xxxx..", "...xx.x.", "...xx...", "...xx...", "..x.x...", "..x..x.."]
	var frames := [_pixel_tex(run_a, pale), _pixel_tex(run_b, pale)]
	var flag := ["xxxxxxx.", "xxxxxxxo", "xxxxxxx.", "xxxxxxo.", "xxxxxx..", "x.......", "x.......", "x.......",
		"x.......", "x.......", "x.......", "x......."]
	_banner = Sprite3D.new()
	_banner.texture = _pixel_tex(flag, Color(0.92, 0.9, 0.84))
	_banner.pixel_size = 0.09
	_banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_banner.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_banner.shaded = false
	_terrain.add_child(_banner)
	for i: int in range(24):
		var s := Sprite3D.new()
		s.texture = frames[i % 2]
		s.set_meta("frames", frames)
		# a loose crowd, not files: most bunched behind the banner, some fallen behind,
		# a few strayed far round the bank
		var roll := randf()
		var lag := randf_range(0.03, 0.5) if roll < 0.85 else randf_range(0.55, 0.85)    # together, a few lagging
		s.set_meta("lag", lag)
		s.set_meta("surge", randf_range(0.4, 1.3))     # each one loses and catches up its own way
		s.set_meta("lane", randf_range(-0.6, 0.6))
		s.set_meta("phase", randf() * TAU)
		s.pixel_size = randf_range(0.065, 0.085)
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED    # seen from above they must still stand
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.shaded = false
		s.modulate = Color(1, 1, 1, randf_range(0.55, 0.95))
		_terrain.add_child(s)
		_runners.append(s)


## The souls that wait at the water's edge for Charon to take them across (canto III): small
## groups standing still on the near bank, swaying a little, some on their knees.
var _waiting: Array[Sprite3D] = []


func _build_waiting() -> void:
	_waiting.clear()
	var pale := Color(0.72, 0.72, 0.7)
	var stand_a := ["..xx..", "..xx..", ".xxxx.", "x.xx.x", "..xx..", "..xx..", ".x..x.", ".x..x.", ".x..x."]
	var stand_b := ["..xx..", "..xx..", ".xxxx.", ".xxxx.", "x.xx.x", "..xx..", ".x..x.", ".x..x.", ".x..x."]
	var kneel := ["......", "......", "..xx..", "..xx..", ".xxxx.", "x.xx.x", "..xx..", ".xxxx.", "xx..xx"]
	var frames_stand := [_pixel_tex(stand_a, pale), _pixel_tex(stand_b, pale)]
	var frame_kneel := _pixel_tex(kneel, pale)
	var r := (_rings.river_mid() + (RingMapScript.RIVER_OUT - RingMapScript.RIVER_IN) * 0.5) * U + 0.18
	for g: int in range(6):
		var ga := g * TAU / 6.0 + randf_range(-0.3, 0.3)
		for k: int in range(randi_range(4, 7)):
			var s := Sprite3D.new()
			var kneeling := randf() < 0.25
			s.texture = frame_kneel if kneeling else frames_stand[0]
			s.set_meta("frames", [frame_kneel, frame_kneel] if kneeling else frames_stand)
			s.set_meta("phase", randf() * TAU)
			s.pixel_size = randf_range(0.06, 0.075)
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.shaded = false
			s.modulate = Color(1, 1, 1, randf_range(0.45, 0.8))
			var a := ga + randf_range(-0.09, 0.09)
			var rr := r + randf_range(0.0, 0.35)
			s.position = Vector3(cos(a) * rr, _rim_y + 0.3, sin(a) * rr)
			_terrain.add_child(s)
			_waiting.append(s)


func _update_vestibule(delta: float) -> void:
	for s: Sprite3D in _waiting:
		var frames: Array = s.get_meta("frames")
		s.texture = frames[int(_time * 0.8 + float(s.get_meta("phase"))) % 2]
	if _banner == null:
		return
	_run_angle += delta * 0.16
	var r := _rings.river_mid() * U + (RingMapScript.RIVER_OUT - RingMapScript.RIVER_IN) * U * 0.5 + 0.55
	_banner.position = Vector3(cos(_run_angle) * r, _rim_y + 0.55, sin(_run_angle) * r)
	for s: Sprite3D in _runners:
		var ph: float = s.get_meta("phase")
		var surge: float = s.get_meta("surge")
		var a: float = _run_angle - float(s.get_meta("lag")) + sin(_time * 0.6 * surge + ph) * 0.07
		var rr: float = r + float(s.get_meta("lane")) + sin(_time * 0.9 * surge + ph * 2.0) * 0.18
		var hop := absf(sin(_time * 9.0 + float(s.get_meta("phase")))) * 0.06
		s.position = Vector3(cos(a) * rr, _rim_y + 0.34 + hop, sin(a) * rr)
		var frames: Array = s.get_meta("frames")
		s.texture = frames[int(_time * 8.0 + float(s.get_meta("phase"))) % 2]


func _add_piece(st: SurfaceTool, spins: bool, shadows := true) -> void:
	if _ground_mat == null:
		_ground_mat = StandardMaterial3D.new()
		_ground_mat.albedo_texture = _ground_vp.get_texture()
		_ground_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_ground_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		_ground_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_ground_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ground_mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_terrain.add_child(mi)
	if spins:
		_spinners.append(mi)
		_spin.append(0.0)


func _uv(p: Vector3) -> Vector2:
	var half_m := RingMapScript.BAKE_HALF * U
	return Vector2(p.x / (2.0 * half_m) + 0.5, p.z / (2.0 * half_m) + 0.5)


func _vert(st: SurfaceTool, p: Vector3, n: Vector3, uv_from := Vector3.INF) -> void:
	st.set_normal(n)
	st.set_uv(_uv(p if uv_from == Vector3.INF else uv_from))
	st.add_vertex(p)


func _ring_top(st: SurfaceTool, r_in: float, r_out: float, y: float, seg: int) -> void:
	for s: int in range(seg):
		var a0 := TAU * s / seg
		var a1 := TAU * (s + 1) / seg
		var p := [Vector3(cos(a0) * r_out, y, sin(a0) * r_out), Vector3(cos(a1) * r_out, y, sin(a1) * r_out),
			Vector3(cos(a1) * r_in, y, sin(a1) * r_in), Vector3(cos(a0) * r_in, y, sin(a0) * r_in)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			_vert(st, p[k], Vector3.UP)


## A cliff at radius r from y_top down to y_bottom, facing the middle. Its texture is the ink
## of the ring just above, darkened by the shading.
func _ring_wall(st: SurfaceTool, r: float, y_top: float, y_bottom: float, seg: int) -> void:
	for s: int in range(seg):
		var a0 := TAU * s / seg
		var a1 := TAU * (s + 1) / seg
		var n0 := Vector3(-cos(a0), 0, -sin(a0))
		var n1 := Vector3(-cos(a1), 0, -sin(a1))
		var t0 := Vector3(cos(a0) * r, y_top, sin(a0) * r)
		var t1 := Vector3(cos(a1) * r, y_top, sin(a1) * r)
		var b0 := Vector3(cos(a0) * r, y_bottom, sin(a0) * r)
		var b1 := Vector3(cos(a1) * r, y_bottom, sin(a1) * r)
		# the wall takes its colors from a thin band just outside its top edge (rock, not ink)
		var src0 := t0 * (1.0 + 0.04)
		var src1 := t1 * (1.0 + 0.04)
		_vert(st, t0, n0, src0)
		_vert(st, t1, n1, src1)
		_vert(st, b1, n1, src1)
		_vert(st, t0, n0, src0)
		_vert(st, b1, n1, src1)
		_vert(st, b0, n0, src0)


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_update_vestibule(delta)
	for i: int in range(_spinners.size()):
		_spin[i] += delta * 0.025 * (1.0 + i * 0.35) * (1.0 if i % 2 == 0 else -1.0)
		_spinners[i].rotation.y = _spin[i]
	var rate := 1.2
	var jolt := Vector3.ZERO
	if _drop >= 0.0:
		_drop += delta
		rate = 9.0 * smoothstep(0.0, 0.15, _drop)        # a fall, not a glide
		var land := _drop - 0.35
		if land > 0.0:
			jolt = Vector3(sin(land * 70.0), cos(land * 53.0), 0) * 0.25 * exp(-land * 7.0)
		if _drop > 1.2:
			_drop = -1.0
	var k := 1.0 - exp(-delta * rate)
	_target = _target.lerp(_target_goal, k)
	_dist = lerpf(_dist, _dist_goal, k)
	# looking down into the funnel from high above, a little tilted so the steps still show
	# the fog starts past what the eye is looking at (it was swallowing the funnel and the river)
	if _env != null:
		_env.fog_depth_begin = _dist * 0.95
		_env.fog_depth_end = _dist + 16.0
	var back := Vector3(0, 0.95, 0.32).normalized() * _dist
	var sway := Vector3(sin(_time * 0.17), 0, cos(_time * 0.13)) * 0.05
	camera.look_at_from_position(_target + back + sway + jolt, _target + jolt * 0.5)
	var glow := _terrain.get_node_or_null("PitGlow") as OmniLight3D
	if glow != null:
		glow.light_energy = 3.0 * (0.85 + 0.15 * sin(_time * 4.3) * sin(_time * 1.7))
