class_name RestPointView
extends SubViewportContainer

## The Rest Point (world design doc v0.4): a dark, silent clearing under a starry sky
## with four-pointed stars, a dry twisted tree beside a lit campfire. The fire and the
## sky are the only lights. It is always night.
## Seen in first person, with the same pixelated, dithered look as the duel and the shop.
## In the viewer the camera can be turned by dragging the mouse (R recenters it).
## The same rest changes with the circle you are in (set `circle` before adding it):
##  0 The Mesquite: the starry night above.
##  1 Limbo: a green meadow under a dome of cold artificial light, the castle of seven walls
##    far off (Dante), and at the edges the doc's burnt frontier: broken rails, a gallows.
##  2 Lust: open and dark, an endless gale of sand and ash dragging the souls past.
enum Circle { MESQUITE, LIMBO, LUST }
var circle := Circle.MESQUITE

const TREE_SCENE := preload("res://assets/models/zones/rest_point/rp_tree.glb")
const FIRE_SCENE := preload("res://assets/models/zones/rest_point/rp_campfire.glb")
const GROUND_TEX := preload("res://assets/textures/zones/rest_ground.png")
const SKY_SHADER := preload("res://resources/shaders/night_sky.gdshader")
const OUTLINE := preload("res://resources/shaders/outline.gdshader")
const FLAME_SHADER := preload("res://resources/shaders/toon_flame.gdshader")

const PIXEL_SHRINK := 3
const EYE := Vector3(0.0, 0.98, 0.0)     # sitting on the ground by the fire
## The walk in: from the dark behind you up to your spot by the fire, then you sit down.
const WALK_FROM := Vector3(0.25, 1.62, 2.9)
const STAND_EYE := 1.62
const FIRE_AT := Vector3(0.75, 0.0, -2.6)     # to one side: the middle of the screen stays dark
const TREE_AT := Vector3(-1.5, 0.0, -5.6)     # behind the fire, against the stars
const LOOK_AT := Vector3(0.1, 0.35, -5.0)    # level with the fire, the sky above the tree
const GROUND_TILE := 2.0                      # meters per repeat of the ground texture
const CLEARING := Vector2(0.2, -4.5)          # middle of the clearing (x, z): flat around it
const GROUND_SIZE := 130.0
const GROUND_CELLS := 200
## The same dead tree, far out in the dark: only its silhouette against the stars.
const FAR_TREES := [
	[Vector3(-9.5, 0, -15.0), 20.0, 0.95], [Vector3(7.0, 0, -19.5), 140.0, 1.15],
	[Vector3(-18.0, 0, -26.0), 260.0, 1.25], [Vector3(15.5, 0, -12.5), 80.0, 0.85],
	[Vector3(-3.5, 0, -30.0), 200.0, 1.3], [Vector3(22.0, 0, -27.0), 310.0, 1.1],
	[Vector3(-24.0, 0, -11.0), 45.0, 1.0],
	# two smaller ones at the edge of the firelight
	[Vector3(5.8, 0, -9.0), 120.0, 0.65], [Vector3(-7.0, 0, -8.5), 290.0, 0.75],
	# along the way in and around the clearing
	[Vector3(-3.4, 0, 2.8), 70.0, 0.55], [Vector3(3.9, 0, 4.6), 230.0, 0.62],
	[Vector3(-5.8, 0, -1.5), 160.0, 0.8], [Vector3(7.5, 0, -3.5), 15.0, 0.9],
	[Vector3(-11.0, 0, -5.0), 330.0, 1.05], [Vector3(11.5, 0, -15.0), 100.0, 1.0],
	[Vector3(-13.5, 0, -17.0), 250.0, 1.15], [Vector3(2.5, 0, -24.0), 40.0, 1.2],
	[Vector3(-6.0, 0, 7.0), 190.0, 0.7], [Vector3(6.5, 0, 9.0), 300.0, 0.75],
]

var viewport: SubViewport
var camera: Camera3D
var _world: Node3D
var _fire_light: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _n_small := FastNoiseLite.new()
var _n_big := FastNoiseLite.new()
var _n_fire := FastNoiseLite.new()
var _flame_mat: ShaderMaterial
var _flame_front_mat: ShaderMaterial
var _glow_light: OmniLight3D
var _ember_fx: GPUParticles3D
var _flare := 0.0          # a log settles, the fire flares up for a moment
var _flare_wait := 4.0
var _flare_goal := 0.0
var _time := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _want_yaw := 0.0
var _want_pitch := 0.0
var _dragging := false
var free_look := true
## 0..1 while walking in (see play_arrival); 1 = seated.
var _arrival := 0.0     # seconds into the walk in
var _arrival_on := false
signal arrived


func _ready() -> void:
	_rng.randomize()
	_n_small.seed = 7
	_n_small.frequency = 0.12
	_n_big.seed = 11
	_n_big.frequency = 0.022
	_n_big.fractal_octaves = 4
	_n_fire.seed = _rng.randi()
	_n_fire.frequency = 1.0
	_n_fire.fractal_octaves = 3
	_head_noise.seed = 3
	_head_noise.frequency = 0.35
	stretch = true
	stretch_shrink = PIXEL_SHRINK
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var dither := ShaderMaterial.new()
	dither.shader = preload("res://resources/shaders/pixel_dither.gdshader")
	dither.set_shader_parameter("black_crush", 0.03)
	material = dither
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.own_world_3d = true
	add_child(viewport)
	_world = Node3D.new()
	viewport.add_child(_world)
	_build_environment()
	_build_ground()
	_build_tree()
	_build_fire()
	_build_rocks()
	match circle:
		Circle.LIMBO:
			_build_far_trees(4)
			_world.add_child(_dust())
			_build_grass(260, Color(0.2, 0.38, 0.14), Color(0.42, 0.66, 0.28), 0.0)
			_build_brush(50)
			_build_limbo()
		Circle.LUST:
			_build_far_trees(0)
			_build_grass(90, Color(0.3, 0.24, 0.18), Color(0.48, 0.4, 0.3), 0.55)
			_build_brush(70)
			_build_lust()
		_:
			_build_far_trees(FAR_TREES.size())
			_world.add_child(_dust())
			_world.add_child(_fireflies())
			_build_grass(110, Color(0.55, 0.47, 0.3), Color(0.8, 0.7, 0.45), 0.0)
			_build_brush(180)
	_build_body()


# ------------------------------------------------------------------ the place
func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# starlight: a faint cold fill, just enough to tell the ground from the sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#56618a")
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.05
	# the clearing ends in darkness: everything far from the fire sinks into black
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#0b0c13")
	env.fog_density = 1.0
	env.fog_depth_begin = 5.0
	env.fog_depth_end = 26.0
	env.fog_depth_curve = 0.7
	env.fog_sky_affect = 0.0
	match circle:
		Circle.LIMBO:
			# no stars: a dome of pale, sourceless light, brighter overhead than at the horizon
			sky_mat.set_shader_parameter("zenith", Color(0.6, 0.66, 0.5))
			sky_mat.set_shader_parameter("horizon", Color(0.27, 0.33, 0.25))
			sky_mat.set_shader_parameter("band_color", Color(0, 0, 0))
			sky_mat.set_shader_parameter("brightness", 0.0)
			env.ambient_light_color = Color("#9fb38c")
			env.ambient_light_energy = 0.45
			env.fog_light_color = Color(0.36, 0.42, 0.32)
			env.fog_depth_begin = 10.0
			env.fog_depth_end = 85.0
			env.fog_depth_curve = 1.2
			var dome := DirectionalLight3D.new()
			dome.light_color = Color("#dfe8c8")
			dome.light_energy = 0.55
			dome.shadow_enabled = true
			dome.rotation_degrees = Vector3(-72, 20, 0)
			_world.add_child(dome)
		Circle.LUST:
			# clouds of dust: no sky, only a dirty brown glow low down
			sky_mat.set_shader_parameter("zenith", Color(0.02, 0.015, 0.018))
			sky_mat.set_shader_parameter("horizon", Color(0.11, 0.075, 0.055))
			sky_mat.set_shader_parameter("band_color", Color(0, 0, 0))
			sky_mat.set_shader_parameter("brightness", 0.0)
			# enough light to read the rock all round: a dull red glow, and the haze only
			# swallows what is beyond the walls
			env.ambient_light_color = Color("#8a5246")
			env.ambient_light_energy = 0.38
			env.fog_light_color = Color(0.12, 0.07, 0.06)
			env.fog_depth_begin = 9.0
			env.fog_depth_end = 34.0
			env.fog_depth_curve = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	camera = Camera3D.new()
	camera.fov = 66.0
	camera.far = 200.0
	_world.add_child(camera)
	camera.look_at_from_position(EYE, LOOK_AT)


func _toon(tex: Texture2D, tint := Color(1, 1, 1), outline := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	m.albedo_color = tint
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("grow", outline)
		m.next_pass = o
	return m


## Glb from Tripo (material "tx_..."): its own texture with the game's toon shading.
func _stylize(root: Node, tint: Color, outline: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s: int in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src != null:
				mi.set_surface_override_material(s, _toon(src.albedo_texture, tint, outline))


## Height of the ground: flat where you rest, small bumps and dips around the clearing,
## and low hills rising far out, whose ridges cut the line between ground and sky.
func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(CLEARING)
	var h := _n_small.get_noise_2d(x, z) * 0.45 * smoothstep(3.5, 9.0, d)
	h += _n_small.get_noise_2d(x * 3.1 + 40.0, z * 3.1) * 0.07 * smoothstep(1.5, 4.0, Vector2(x, z).distance_to(Vector2(FIRE_AT.x, FIRE_AT.z)))
	h += (_n_big.get_noise_2d(x, z) * 0.5 + 0.5) * 6.5 * smoothstep(16.0, 55.0, d)
	h += maxf(_n_big.get_noise_2d(x * 2.3, z * 2.3 + 90.0), 0.0) * 1.8 * smoothstep(10.0, 30.0, d)
	return h


func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := GROUND_CELLS
	var step := GROUND_SIZE / n
	var x0 := CLEARING.x - GROUND_SIZE * 0.5
	var z0 := CLEARING.y - GROUND_SIZE * 0.5
	for j: int in range(n + 1):
		for i: int in range(n + 1):
			var x := x0 + i * step
			var z := z0 + j * step
			var e := step * 0.5
			var nrm := Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z) / GROUND_TILE)
			st.add_vertex(Vector3(x, height_at(x, z), z))
	for j: int in range(n):
		for i: int in range(n):
			var a := j * (n + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + 1)
			st.add_index(a + n + 2)
			st.add_index(a + n + 1)
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	var tint := Color(0.85, 0.82, 0.8)
	if circle == Circle.LIMBO:
		tint = Color(0.5, 0.68, 0.4)          # grass all over
	elif circle == Circle.LUST:
		tint = Color(0.6, 0.5, 0.45)
	var m := _toon(GROUND_TEX, tint)
	m.texture_repeat = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = m
	_world.add_child(ground)


func _build_tree() -> void:
	var tree := TREE_SCENE.instantiate() as Node3D
	_world.add_child(tree)
	tree.position = Vector3(TREE_AT.x, height_at(TREE_AT.x, TREE_AT.z) - 0.05, TREE_AT.z)
	tree.rotation_degrees.y = 35.0      # the branches reach over the fire
	_stylize(tree, Color(0.95, 0.92, 0.9), 0.008)


func _build_far_trees(count: int) -> void:
	for t: Array in FAR_TREES.slice(0, count):
		var at: Vector3 = t[0]
		var tree := TREE_SCENE.instantiate() as Node3D
		_world.add_child(tree)
		tree.position = Vector3(at.x, height_at(at.x, at.z) - 0.1, at.z)
		tree.rotation_degrees = Vector3(_rng.randf_range(-4, 4), t[1], _rng.randf_range(-4, 4))
		tree.scale = Vector3.ONE * float(t[2])
		_stylize(tree, Color(0.8, 0.78, 0.76), 0.0)


func _build_fire() -> void:
	var pit := FIRE_SCENE.instantiate() as Node3D
	_world.add_child(pit)
	pit.position = FIRE_AT + Vector3(0, height_at(FIRE_AT.x, FIRE_AT.z), 0)
	_stylize(pit, Color(1, 1, 1), 0.004)
	# the light: warm, low, flickering; it throws the tree's shadow back into the dark
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color("#ff9248")
	_fire_light.light_energy = 2.2
	_fire_light.omni_range = 10.0
	_fire_light.omni_attenuation = 1.1
	_fire_light.shadow_enabled = true
	_fire_light.position = FIRE_AT + Vector3(0, 0.9, 0)
	_world.add_child(_fire_light)
	_world.add_child(_toon_fire())
	# a second, shadowless warm light low and wide: the cozy pool of light around you
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color("#ff8a3c")
	_glow_light.light_energy = 0.9
	_glow_light.omni_range = 6.0
	_glow_light.omni_attenuation = 0.8
	_glow_light.position = FIRE_AT + Vector3(0, 0.35, 0.6)
	_world.add_child(_glow_light)
	_ember_fx = _embers()
	_world.add_child(_ember_fx)


func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t


func _glow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	return m


## The flames, drawn (toon_flame.gdshader), in two layers: the tall one in the middle of the
## pit, and a lower one pushed toward the camera that wraps the bottom of the logs, so the
## fire burns around the wood (only the log tips stick out) instead of hiding behind it.
func _toon_fire() -> Node3D:
	var root := Node3D.new()
	var ground := height_at(FIRE_AT.x, FIRE_AT.z)
	_flame_mat = _flame_layer(root, Vector2(1.1, 1.15), ground + 0.62, 0.0, 0.0)
	_flame_front_mat = _flame_layer(root, Vector2(0.85, 0.72), ground + 0.4, 0.3, 0.53)
	return root


func _flame_layer(parent: Node3D, size: Vector2, center_y: float, push: float, phase: float) -> ShaderMaterial:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = FLAME_SHADER
	m.set_shader_parameter("push", push)
	m.set_shader_parameter("phase", phase)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(FIRE_AT.x, center_y, FIRE_AT.z)
	parent.add_child(mi)
	return m


## A rough low-poly rock: a squashed sphere with its vertices pushed in and out.
func _rock_mesh(seed: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 2.2
	for i: int in range(verts.size()):
		var v := verts[i]
		var k := 1.0 + noise.get_noise_3dv(v) * 0.45
		v = Vector3(v.x * k * 1.25, maxf(v.y * k * 0.7, -0.08), v.z * k)
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.deindex()
	st.generate_normals()      # faceted: every face flat, like the props
	return st.commit()


func _build_rocks() -> void:
	var meshes: Array[ArrayMesh] = []
	for s: int in range(4):
		meshes.append(_rock_mesh(31 + s * 17))
	# the same weathered stone as the fire ring (its texture, mapped from all sides),
	# lighter than the dirt so they read
	var stone: Texture2D = null
	var pit := FIRE_SCENE.instantiate()
	for node in pit.find_children("*", "MeshInstance3D", true, false):
		var src := (node as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		if src != null:
			stone = src.albedo_texture
	pit.free()
	if circle == Circle.LUST:
		stone = CAVE_TEX          # the same rock as the pit walls
	var m := _toon(stone, Color(1.15, 1.1, 1.05), 0.03)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var placed := 0
	while placed < 85:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(2.2, 16.0)
		var at := Vector2(CLEARING.x, CLEARING.y) + Vector2(cos(ang), sin(ang)) * dist
		if Vector2(at.x, at.y).distance_to(Vector2(0, 0)) < 1.6 or _on_path(at):
			continue        # not on the player or the way in
		if Vector2(at.x, at.y).distance_to(Vector2(FIRE_AT.x, FIRE_AT.z)) < 1.3:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[rng.randi() % meshes.size()]
		mi.material_override = m
		var size := rng.randf_range(0.35, 0.9) * (1.0 + smoothstep(4.0, 14.0, dist) * 1.4)
		mi.scale = Vector3.ONE * size
		mi.rotation.y = rng.randf() * TAU
		mi.position = Vector3(at.x, height_at(at.x, at.y) - size * 0.05, at.y)
		_world.add_child(mi)
		placed += 1


## A dead thorny shrub: stems fan out from a knot at the ground, fork two or three times and
## end in short twigs. Built from thin faceted prisms (dark, dry wood).
func _shrub_mesh(seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stems := rng.randi_range(5, 8)
	for i: int in range(stems):
		var ang := TAU * i / stems + rng.randf_range(-0.4, 0.4)
		var out := rng.randf_range(0.35, 0.8)
		var dir := Vector3(cos(ang) * out, 1.0, sin(ang) * out).normalized()
		_branch(st, rng, Vector3(cos(ang), 0, sin(ang)) * 0.04, dir, rng.randf_range(0.28, 0.4), 0.022, 3)
	st.index()
	st.generate_normals()
	return st.commit()


func _branch(st: SurfaceTool, rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	# a slight bend under its own weight
	dir = (dir + Vector3(0, -0.12, 0) * (3 - depth) * 0.3).normalized()
	var to := from + dir * length
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	var r2 := radius * 0.62
	var shade := rng.randf_range(0.8, 1.15)
	var col := Color(0.2 * shade, 0.16 * shade, 0.13 * shade)
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for k: int in range(3):
		var a := TAU * k / 3.0
		var off := side * cos(a) + up * sin(a)
		ring_a.append(from + off * radius)
		ring_b.append(to + off * r2)
	for k: int in range(3):
		var k2 := (k + 1) % 3
		for v: Vector3 in [ring_a[k], ring_b[k], ring_a[k2], ring_a[k2], ring_b[k], ring_b[k2]]:
			st.set_color(col)
			st.add_vertex(v)
	if depth <= 0:
		return
	var kids := rng.randi_range(2, 3)
	for c: int in range(kids):
		var turn := Basis(dir, rng.randf() * TAU) * Basis(side, rng.randf_range(0.35, 0.8))
		var d2 := (turn * dir).normalized()
		_branch(st, rng, to, d2, length * rng.randf_range(0.6, 0.8), r2, depth - 1)


func _build_brush(count: int) -> void:
	var meshes: Array[ArrayMesh] = []
	for s: int in range(3):
		meshes.append(_shrub_mesh(500 + s * 37))
	var spots: Array = [[], [], []]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var fire2 := Vector2(FIRE_AT.x, FIRE_AT.z)
	var tries := 0
	var placed := 0
	while placed < count and tries < 4000:
		tries += 1
		var at: Vector2
		if placed < mini(30, count / 3):
			# the brush you walk through on the way in: close on both sides of the path
			var u := rng.randf_range(0.05, 1.1)
			var off := rng.randf_range(0.95, 2.6) * (1.0 if rng.randf() < 0.5 else -1.0)
			at = Vector2(_path_x(minf(u, 1.0)) + off, u * WALK_FROM.z)
		else:
			# thicker at the edge of the clearing, thinning out into the dark
			var ang := rng.randf() * TAU
			var dist := 4.0 + pow(rng.randf(), 1.6) * 18.0
			at = Vector2(CLEARING.x, CLEARING.y) + Vector2(cos(ang), sin(ang)) * dist
		if at.distance_to(Vector2.ZERO) < 1.4 or at.distance_to(fire2) < 2.0 or _on_path(at):
			continue
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.9))
		spots[placed % 3].append(Transform3D(b, Vector3(at.x, height_at(at.x, at.y) - 0.03, at.y)))
		placed += 1
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i: int in range(3):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = spots[i].size()
		for j: int in range(spots[i].size()):
			mm.set_instance_transform(j, spots[i][j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		_world.add_child(mmi)


## Tufts of dry grass: thin straw blades fanning out, scattered in clumps.
func _grass_mesh(low: Color, high: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b: int in range(13):
		var ang := rng.randf() * TAU
		var lean := rng.randf_range(0.15, 0.6)
		var h := rng.randf_range(0.18, 0.42)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := dir.cross(Vector3.UP) * 0.012
		var base := dir * rng.randf_range(0.0, 0.05)
		var tip := base + dir * lean * h + Vector3.UP * h
		var shade := rng.randf_range(0.75, 1.0)
		st.set_color(low * shade)
		st.set_normal(Vector3.UP)
		st.add_vertex(base - side)
		st.set_normal(Vector3.UP)
		st.add_vertex(base + side)
		st.set_color(high * shade)
		st.set_normal(Vector3.UP)
		st.add_vertex(tip)
	return st.commit()


## lean: radians the blades are bent toward +x (the wind in Lust).
func _build_grass(clumps: int, low: Color, high: Color, lean: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _grass_mesh(Color(low, 1.0), Color(high, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var spots: Array[Transform3D] = []
	# clumps: a few centers, several tufts around each
	for c: int in range(clumps):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(2.0, 20.0)
		var center := Vector2(CLEARING.x, CLEARING.y) + Vector2(cos(ang), sin(ang)) * dist
		for k: int in range(rng.randi_range(3, 7)):
			var at := center + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
			if at.distance_to(Vector2(0, 0)) < 1.2 or at.distance_to(Vector2(FIRE_AT.x, FIRE_AT.z)) < 1.1 or _on_path(at):
				continue
			var b := Basis(Vector3.BACK, -lean * rng.randf_range(0.7, 1.2)) * Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
			spots.append(Transform3D(b, Vector3(at.x, height_at(at.x, at.y), at.y)))
	mm.instance_count = spots.size()
	for i: int in range(spots.size()):
		mm.set_instance_transform(i, spots[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mmi)


## The flames: soft blobs that rise from the logs, shrink and go from yellow to dark red.
func _flames() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 70
	p.lifetime = 0.7
	p.position = FIRE_AT + Vector3(0, 0.12, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.13
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.25
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.78, 0.35, 0.55))
	ramp.add_point(0.3, Color(1.0, 0.45, 0.1, 0.5))
	ramp.add_point(0.7, Color(0.7, 0.14, 0.03, 0.35))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.25, 0.04, 0.02, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 3.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	quad.material = _glow_material()
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Sparks that drift up into the dark and wink out.
func _embers() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 8
	p.lifetime = 5.0
	p.position = FIRE_AT + Vector3(0, 0.7, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.18
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0.02, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.12
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed_random = 0.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	ramp.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = _glow_material()
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Smoke from the fire: thin, it catches the firelight low and is lost against the stars.
func _smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 30
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.position = FIRE_AT + Vector3(0, 1.1, 0)
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 9, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.09, 0.04, -0.03)     # a breath of wind
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 2.5
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.06, 0.055, 0.06, 0.0))
	ramp.add_point(0.15, Color(0.06, 0.055, 0.06, 0.18))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.05, 0.05, 0.06, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # it must not glow in the firelight
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Fireflies at the edge of the light: they drift slowly and glow on and off, unhurried.
func _fireflies() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.position = Vector3(CLEARING.x, 1.0, CLEARING.y - 2.0)
	p.visibility_aabb = AABB(Vector3(-12, -2, -10), Vector3(24, 6, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(7.0, 0.7, 4.5)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.06
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_noise_speed = Vector3(0.02, 0.01, 0.02)
	# three slow glows over its life (about 5 s each), dark in between
	var ramp := Gradient.new()
	var glow := Color(0.85, 1.0, 0.45, 1.0)
	var off := Color(0.85, 1.0, 0.45, 0.0)
	ramp.set_color(0, off)
	for k: int in range(3):
		var a := k / 3.0
		ramp.add_point(a + 0.06, off)
		ramp.add_point(a + 0.14, glow)
		ramp.add_point(a + 0.22, glow)
		ramp.add_point(a + 0.3, off)
	ramp.set_color(ramp.get_point_count() - 1, off)
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	quad.material = _glow_material()
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Dust and bits of ash hanging in the air around the fire, lit by it.
func _dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.position = FIRE_AT + Vector3(-0.6, 0.9, -0.4)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.4, 0.8, 1.6)
	pm.gravity = Vector3(0.012, -0.004, 0.0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.02
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.05
	pm.turbulence_noise_scale = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.85, 0.75, 0.0))
	ramp.add_point(0.2, Color(0.9, 0.85, 0.75, 0.5))
	ramp.add_point(0.8, Color(0.9, 0.85, 0.75, 0.5))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.9, 0.85, 0.75, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	m.albedo_texture = _soft_dot()
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	_time += delta
	if _fire_light != null:
		_update_fire(delta)
	_update_camera(delta)


## A real campfire doesn't strobe: it swells and sinks slowly and unevenly, with a soft
## shiver on top, and every few seconds a log settles and it flares up, then calms down.
func _update_fire(delta: float) -> void:
	_flare_wait -= delta
	if _flare_wait <= 0.0:
		_flare_wait = _rng.randf_range(9.0, 18.0)
		_flare_goal = _rng.randf_range(0.3, 0.6)
	# it swells in (~0.4 s) and dies down slowly: never a jump
	_flare_goal = maxf(_flare_goal - delta * 0.45, 0.0)
	_flare = lerpf(_flare, _flare_goal, 1.0 - exp(-delta * (6.0 if _flare_goal > _flare else 2.0)))
	var slow := _n_fire.get_noise_1d(_time * 0.2)            # breathing, ~5 s
	var mid := _n_fire.get_noise_1d(_time * 0.7 + 50.0)      # the flames leaning
	var shiver := _n_fire.get_noise_1d(_time * 2.5 + 90.0)   # small, never a strobe
	var level := 1.0 + slow * 0.32 + mid * 0.12 + shiver * 0.035 + _flare * 0.35
	_fire_light.light_energy = 2.1 * level
	_glow_light.light_energy = 0.6 * (0.85 + slow * 0.15 + _flare * 0.2)
	var flame_level := clampf(0.92 + slow * 0.1 + _flare * 0.14, 0.8, 1.15)
	_flame_mat.set_shader_parameter("intensity", flame_level)
	_flame_front_mat.set_shader_parameter("intensity", flame_level)
	# the light's center leans with the flames, so shadows sway instead of jumping
	_fire_light.position = FIRE_AT + Vector3(mid * 0.08, 0.7 + slow * 0.06 + _flare * 0.1, _n_fire.get_noise_1d(_time * 0.6 + 20.0) * 0.05)
	_ember_fx.amount_ratio = clampf(0.6 + _flare * 0.6, 0.0, 1.0)
	if circle == Circle.LUST:
		# the gusts beat the fire down and it flares back up between them
		_gust = clampf(_n_fire.get_noise_1d(_time * 0.35 + 300.0) * 1.4 + 0.45, 0.0, 1.0)
		_fire_light.light_energy *= 1.0 - _gust * 0.3 + shiver * 0.15
		_fire_light.position.x += _gust * 0.25
		_ember_fx.amount_ratio = 1.0
		for w: GPUParticles3D in _wind_fx: w.speed_scale = 0.75 + _gust * 0.6
		for s: GPUParticles3D in _souls_fx: s.speed_scale = 0.8 + _gust * 0.4


func _on_path(at: Vector2) -> bool:
	var u := clampf(at.y / WALK_FROM.z, 0.0, 1.0)
	return absf(at.x - _path_x(u)) < 0.9 and at.y > -0.6 and at.y < WALK_FROM.z + 1.0


## The way in bends a little around the brush (u: 0 at your seat, 1 where you start).
func _path_x(u: float) -> float:
	return lerpf(EYE.x, WALK_FROM.x, u) + sin(u * PI) * 0.55


# ------------------------------------------------------------------ the walk in
## A tired walk: uneven steps, a stop halfway to get your breath back, a heavy sit.
## The body follows a planned path; the eyes follow a list of things to look at, through
## a soft spring (they lag, overshoot a little and settle), plus a slow unsteady drift.
var _steps: Array = []          # [start, duration, from_m, to_m, side]
var _walk_end := 0.0
var _sit_start := 0.0
const SIT_TIME := 2.1
var _gazes: Array = []          # [time, point]
var _look_p := Vector3.ZERO
var _look_v := Vector3.ZERO
var _head_noise := FastNoiseLite.new()


func _plan_walk() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var length := Vector2(WALK_FROM.x, WALK_FROM.z).distance_to(Vector2(EYE.x, EYE.z))
	_steps.clear()
	var t := 0.35             # a beat standing still, getting your bearings
	var m := 0.0
	var side := 1.0
	var paused := false
	var pause_at := 0.0
	while m < length - 0.01:
		if not paused and m > length * 0.4:
			paused = true
			pause_at = t
			_steps.append([t, 0.7, m, m, 0.0])    # a short stop: his eyes go to the tree
			t += 0.7
			continue
		var step := minf(rng.randf_range(0.42, 0.58), length - m)
		var dur := (0.42 + step * 0.45) * rng.randf_range(0.9, 1.15)
		_steps.append([t, dur, m, m + step, side])
		t += dur
		m += step
		side = -side
	_walk_end = t
	_sit_start = t + 0.15
	_head_noise.seed = rng.randi()
	_head_noise.frequency = 0.35
	# where the eyes go: the ground ahead, the fire, the tree while resting, the dark
	# on the right, the ground again, the fire, and down to the ground by it to sit
	var fire := FIRE_AT + Vector3(0, 0.55, 0)
	_gazes = [
		[0.0, _walk_point(0.3) + Vector3(0.2, -1.5, -1.6)],
		[0.7, fire + Vector3(0, 0.3, 0)],
		[pause_at, TREE_AT + Vector3(0.3, 2.4, 0)],
		[pause_at + 0.75, fire],
		[_sit_start - 0.1, Vector3(0.05, -0.15, -0.7)],
		[_sit_start + SIT_TIME * 0.72, LOOK_AT],
	]


## Where the body is after walking `m` meters along the way in.
func _walk_point(frac: float) -> Vector3:
	var u := 1.0 - frac
	return Vector3(_path_x(u), STAND_EYE, lerpf(EYE.z, WALK_FROM.z, u))


## Walks in from the dark and sits down by the fire; emits `arrived` at the end.
func play_arrival() -> void:
	free_look = false
	_plan_walk()
	_arrival = 0.0
	_arrival_on = true
	_look_p = (_gazes[0][1] as Vector3)
	_look_v = Vector3.ZERO


## Click or key during the walk: straight to the seat.
func skip_arrival() -> void:
	if _arrival_on:
		_arrival = _sit_start + SIT_TIME
		_look_p = LOOK_AT
		_look_v = Vector3.ZERO


func is_arriving() -> bool:
	return _arrival_on


## A log settles: the fire swells for a moment (a choice was made at the fire).
func flare(strength := 0.8) -> void:
	_flare_goal = maxf(_flare_goal, strength)


## 1 inside [a, b], easing in and out over the first and last 40 %.
func _bump(x: float, a: float, b: float) -> float:
	var r := (b - a) * 0.4
	return smoothstep(a, a + r, x) * (1.0 - smoothstep(b - r, b, x))


## Body position (eye height included) and roll at time t of the walk in.
func _body_at(t: float) -> Array:
	var length := Vector2(WALK_FROM.x, WALK_FROM.z).distance_to(Vector2(EYE.x, EYE.z))
	var m := 0.0
	var dip := 0.0
	var lateral := 0.0
	for s: Array in _steps:
		var start: float = s[0]
		var dur: float = s[1]
		if t < start:
			break
		var u := clampf((t - start) / dur, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		m = lerpf(s[2], s[3], e)
		if float(s[4]) != 0.0 and u < 1.0:
			# heavy footfalls: the body drops at each landing and rises mid-step,
			# and leans over the foot that carries it
			dip = (sin(u * PI) - 0.75) * 0.05
			lateral = float(s[4]) * sin(u * PI) * 0.045
	var pos := _walk_point(m / length)
	pos.y += dip
	pos.x += lateral
	var roll := -lateral * 0.5
	# breathing hard while stopped, then easing
	var winded := 1.0 - smoothstep(_walk_end, _walk_end + 3.0, t)
	pos.y += sin(t * 3.2) * 0.012 * winded
	# sitting down: knees bend (lean forward, look down), then you let yourself drop
	if t > _sit_start:
		var k := (t - _sit_start) / SIT_TIME
		var kneel := smoothstep(0.0, 0.38, k)
		var drop := smoothstep(0.38, 0.72, k)
		pos.y = lerpf(STAND_EYE + dip, 1.3, kneel)
		pos.y = lerpf(pos.y, EYE.y, drop) - _bump(k, 0.7, 1.0) * 0.035
		pos.z -= _bump(k, 0.0, 0.75) * 0.18
		roll += _bump(k, 0.35, 0.85) * 0.045
	return [pos, roll]


# ------------------------------------------------------------------ your body
## Not much of a model, just enough to feel it: you sit on the ground with one leg stretched
## out and the other knee up, forearms resting on that knee, hands loosely together.
## Dark cloth like the stickmen, lit only by the fire. It appears as you drop to the ground.
var _limbs := {}
var _body_root: Node3D
var _seat := 1.0     # 0 = still standing / kneeling, 1 = sitting


func _build_body() -> void:
	_body_root = Node3D.new()
	_world.add_child(_body_root)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("#2a2320")
	cloth.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	cloth.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	o.set_shader_parameter("grow", 0.006)
	cloth.next_pass = o
	var leather := cloth.duplicate() as StandardMaterial3D
	leather.albedo_color = Color("#1c1412")
	var skin := cloth.duplicate() as StandardMaterial3D
	skin.albedo_color = Color("#3a2c26")
	for n: String in ["thigh_L", "shin_L", "thigh_R", "shin_R"]:
		_limbs[n] = _cylinder(0.075 if n.begins_with("thigh") else 0.06, cloth)
	for n: String in ["upper_L", "fore_L", "upper_R", "fore_R"]:
		_limbs[n] = _cylinder(0.05 if n.begins_with("upper") else 0.045, cloth)
	for n: String in ["knee_L", "knee_R", "elbow_L", "elbow_R"]:
		_limbs[n] = _ball(0.07 if n.begins_with("knee") else 0.05, cloth)
	for n: String in ["boot_L", "boot_R"]:
		_limbs[n] = _ball(0.075, leather)
		(_limbs[n] as MeshInstance3D).scale = Vector3(1.0, 0.8, 1.9)
	for n: String in ["hand_L", "hand_R"]:
		_limbs[n] = _ball(0.05, skin)
		(_limbs[n] as MeshInstance3D).scale = Vector3(1.0, 0.75, 1.3)


func _cylinder(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 1.0
	c.radial_segments = 8
	c.rings = 1
	mi.mesh = c
	mi.material_override = m
	_body_root.add_child(mi)
	return mi


func _ball(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	mi.mesh = s
	mi.material_override = m
	_body_root.add_child(mi)
	return mi


func _bone(name: String, a: Vector3, b: Vector3) -> void:
	var mi := _limbs[name] as MeshInstance3D
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x, y * d.length(), z), (a + b) * 0.5)


## Key poses of sitting down (joint positions above the ground under you):
## S standing (legs under you, out of sight) -> A knees down on the ground, hands on the thighs
## -> B sat, both knees up, hands holding the shins -> C the left leg slides out, forearms
## settle on the right knee.
const POSES := {
	"S": {"hip_l": Vector3(-0.11, 0.9, 0.05), "knee_l": Vector3(-0.12, 0.48, -0.03), "ankle_l": Vector3(-0.12, 0.07, 0.05),
		"hip_r": Vector3(0.11, 0.9, 0.05), "knee_r": Vector3(0.12, 0.48, -0.03), "ankle_r": Vector3(0.12, 0.07, 0.05),
		"hand_l": Vector3(-0.24, 0.85, 0.0), "hand_r": Vector3(0.24, 0.85, 0.0),
		"elbow_l": Vector3(-0.24, 1.1, 0.05), "elbow_r": Vector3(0.24, 1.1, 0.05)},
	"A": {"hip_l": Vector3(-0.11, 0.5, 0.02), "knee_l": Vector3(-0.13, 0.07, -0.32), "ankle_l": Vector3(-0.13, 0.07, 0.14),
		"hip_r": Vector3(0.11, 0.5, 0.02), "knee_r": Vector3(0.13, 0.07, -0.32), "ankle_r": Vector3(0.13, 0.07, 0.14),
		"hand_l": Vector3(-0.13, 0.33, -0.26), "hand_r": Vector3(0.13, 0.33, -0.26),
		"elbow_l": Vector3(-0.23, 0.55, -0.05), "elbow_r": Vector3(0.23, 0.55, -0.05)},
	"B": {"hip_l": Vector3(-0.11, 0.13, -0.08), "knee_l": Vector3(-0.15, 0.55, -0.5), "ankle_l": Vector3(-0.16, 0.08, -0.74),
		"hip_r": Vector3(0.11, 0.13, -0.08), "knee_r": Vector3(0.17, 0.6, -0.6), "ankle_r": Vector3(0.15, 0.08, -0.78),
		"hand_l": Vector3(-0.15, 0.36, -0.62), "hand_r": Vector3(0.16, 0.38, -0.7),
		"elbow_l": Vector3(-0.26, 0.5, -0.22), "elbow_r": Vector3(0.27, 0.52, -0.25)},
	"C": {"hip_l": Vector3(-0.11, 0.13, -0.08), "knee_l": Vector3(-0.15, 0.14, -0.55), "ankle_l": Vector3(-0.2, 0.08, -1.02),
		"hip_r": Vector3(0.11, 0.13, -0.08), "knee_r": Vector3(0.17, 0.6, -0.6), "ankle_r": Vector3(0.15, 0.08, -0.78),
		"hand_l": Vector3(0.055, 0.67, -0.7), "hand_r": Vector3(0.145, 0.68, -0.71),
		"elbow_l": Vector3(-0.05, 0.55, -0.44), "elbow_r": Vector3(0.29, 0.58, -0.48)},
}


func _pose_at(k: float) -> Dictionary:
	var keys := [["S", 0.0], ["A", 0.38], ["B", 0.7], ["C", 1.0]]
	for i: int in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if k <= float(b[1]) or i == keys.size() - 2:
			var u := clampf((k - float(a[1])) / (float(b[1]) - float(a[1])), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			var pa: Dictionary = POSES[a[0]]
			var pb: Dictionary = POSES[b[0]]
			var out := {}
			for j: String in pa.keys():
				out[j] = (pa[j] as Vector3).lerp(pb[j], u)
			return out
	return POSES["C"]


func _update_body() -> void:
	if _body_root == null:
		return
	_body_root.visible = _seat > 0.0
	if not _body_root.visible:
		return
	var g := height_at(0.0, 0.0)
	var pose := _pose_at(_seat)
	var lift := Vector3(0, g, 0)
	var settled := smoothstep(0.85, 1.0, _seat)
	var breath := Vector3(0, sin(_time * 1.3) * 0.006, _head_noise.get_noise_1d(_time * 0.3 + 7.0) * 0.012) * settled
	var hip_l: Vector3 = pose["hip_l"] + lift
	var hip_r: Vector3 = pose["hip_r"] + lift
	var knee_l: Vector3 = pose["knee_l"] + lift
	var knee_r: Vector3 = pose["knee_r"] + lift
	var ankle_l: Vector3 = pose["ankle_l"] + lift
	var ankle_r: Vector3 = pose["ankle_r"] + lift
	var hand_l: Vector3 = pose["hand_l"] + lift + breath
	var hand_r: Vector3 = pose["hand_r"] + lift + breath
	var elbow_l: Vector3 = pose["elbow_l"] + lift + breath * 0.5
	var elbow_r: Vector3 = pose["elbow_r"] + lift + breath * 0.5
	# the shoulders go with your head
	var cam := camera.global_position
	var sh_l := Vector3(cam.x - 0.19, cam.y - 0.24, cam.z + 0.02)
	var sh_r := Vector3(cam.x + 0.19, cam.y - 0.24, cam.z + 0.02)
	_bone("thigh_L", hip_l, knee_l)
	_bone("shin_L", knee_l, ankle_l)
	_bone("thigh_R", hip_r, knee_r)
	_bone("shin_R", knee_r, ankle_r)
	_bone("upper_L", sh_l, elbow_l)
	_bone("fore_L", elbow_l, hand_l)
	_bone("upper_R", sh_r, elbow_r)
	_bone("fore_R", elbow_r, hand_r)
	(_limbs["knee_L"] as Node3D).global_position = knee_l
	(_limbs["knee_R"] as Node3D).global_position = knee_r
	(_limbs["elbow_L"] as Node3D).global_position = elbow_l
	(_limbs["elbow_R"] as Node3D).global_position = elbow_r
	(_limbs["boot_L"] as Node3D).global_position = ankle_l + Vector3(0, 0.0, -0.06)
	(_limbs["boot_R"] as Node3D).global_position = ankle_r + Vector3(0, 0.0, -0.06)
	(_limbs["hand_L"] as Node3D).global_position = hand_l
	(_limbs["hand_R"] as Node3D).global_position = hand_r


func _gaze_target(t: float) -> Vector3:
	var target: Vector3 = _gazes[0][1]
	for g: Array in _gazes:
		if t >= float(g[0]):
			target = g[1]
	return target


func _update_camera(delta: float) -> void:
	var k := 1.0 - exp(-delta * 8.0)
	_yaw = lerpf(_yaw, _want_yaw, k)
	_pitch = lerpf(_pitch, _want_pitch, k)
	var eye := EYE
	var roll := 0.0
	var target: Vector3
	if _arrival_on:
		_arrival += delta
		var body := _body_at(_arrival)
		eye = body[0]
		roll = body[1]
		target = _gaze_target(_arrival)
		_seat = clampf((_arrival - _sit_start) / SIT_TIME, 0.0, 1.0) if _arrival > _sit_start else 0.0
		if _arrival >= _sit_start + SIT_TIME:
			_arrival_on = false
			arrived.emit()
	else:
		_seat = 1.0
		# seated (or free look in the viewer): where the yaw/pitch point
		var base := Basis.looking_at(LOOK_AT - EYE, Vector3.UP)
		var b := Basis(Vector3.UP, _yaw) * base * Basis(Vector3.RIGHT, _pitch)
		target = EYE - b.z * EYE.distance_to(LOOK_AT)
		# slow, deep breathing while you sit
		eye.y += sin(_time * 1.3) * 0.008 + sin(_time * 0.47) * 0.004
	# the eyes: a soft, slightly underdamped spring (they lag, overshoot a touch, settle)
	var stiff := 10.0 if _arrival_on else 30.0
	var damp := 2.0 * sqrt(stiff) * (0.72 if _arrival_on else 1.0)
	_look_v += ((target - _look_p) * stiff - _look_v * damp) * delta
	_look_p += _look_v * delta
	if _look_p == Vector3.ZERO:
		_look_p = target
	# a slow, unsteady drift of the head: never perfectly still, never mechanical
	var tired := 1.0 if _arrival_on else 0.45
	var drift := Vector3(
		_head_noise.get_noise_1d(_time * 0.8) * 0.12,
		_head_noise.get_noise_1d(_time * 0.6 + 40.0) * 0.07,
		0.0) * tired
	roll += _head_noise.get_noise_1d(_time * 0.5 + 90.0) * 0.012 * tired
	if circle == Circle.LUST:
		# the wind shoves you a little
		drift += Vector3(_head_noise.get_noise_1d(_time * 3.0 + 7.0), _head_noise.get_noise_1d(_time * 2.6 + 70.0) * 0.5, 0) * 0.03 * _gust
		roll += _head_noise.get_noise_1d(_time * 2.2 + 140.0) * 0.012 * _gust
	var look := _look_p + drift
	var fwd := (look - eye).normalized()
	var b2 := Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.FORWARD, roll)
	camera.global_transform = Transform3D(b2, eye)
	_update_body()


func _gui_input(event: InputEvent) -> void:
	if not free_look:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_want_yaw -= event.relative.x * 0.004
		_want_pitch = clampf(_want_pitch - event.relative.y * 0.004, -0.9, 1.1)


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.pressed and event is InputEventKey and event.keycode == KEY_R:
		_want_yaw = 0.0
		_want_pitch = 0.0


# ------------------------------------------------------------------ fire colours
## Each circle burns its own fire: the Mesquite's warm orange, Limbo's cold pale flame (a
## light without heat), Lust's feverish crimson.
func _tint_fire(heart: Color, body: Color, ember: Color, soot: Color, light: Color, glow: Color) -> void:
	for fm: ShaderMaterial in [_flame_mat, _flame_front_mat]:
		fm.set_shader_parameter("heart", heart)
		fm.set_shader_parameter("body", body)
		fm.set_shader_parameter("ember", ember)
		fm.set_shader_parameter("soot", soot)
	_fire_light.light_color = light
	_glow_light.light_color = glow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(heart, 1.0))
	ramp.set_color(1, Color(body, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	(_ember_fx.process_material as ParticleProcessMaterial).color_ramp = rt


# ------------------------------------------------------------------ Limbo
## Inside the first circle, Dante's "noble castle" seven times walled: the castle on a rise far
## off in the haze, ringed by seven walls, each higher than the one outside it. Toward the
## edges, the doc's burnt frontier: a broken railway crossing the meadow and a gallows.
const CASTLE_SCENE := preload("res://assets/models/zones/limbo/lb_castle.glb")
const WALL_TEX := preload("res://assets/textures/zones/castle_wall.png")
const CAVE_TEX := preload("res://assets/textures/zones/cave_rock.png")


func _build_limbo() -> void:
	_tint_fire(Color(0.92, 1.0, 0.92), Color(0.5, 0.78, 0.66), Color(0.16, 0.34, 0.3), Color(0.04, 0.08, 0.08),
		Color("#cfeedd"), Color("#a8d8c0"))
	var center := Vector3(9.0, 0.0, -64.0)
	center.y = height_at(center.x, center.z) - 0.5
	var wall := _toon(WALL_TEX, Color(0.95, 0.95, 0.9), 0.0)
	wall.uv1_triplanar = true
	wall.uv1_scale = Vector3(0.25, 0.25, 0.25)
	var walls: Array[Transform3D] = []
	var towers: Array[Transform3D] = []
	for ring: int in range(7):
		var r := 34.0 - ring * 2.6
		var h := 3.0 + ring * 0.9
		var lift := ring * 0.9          # each ring stands on a higher terrace
		var segs := 40 - ring * 3
		for s: int in range(segs):
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var p0 := Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := Vector3(cos(a1), 0, sin(a1)) * r
			var along := p1 - p0
			var b := Basis.looking_at(along.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1.0, h, along.length() + 0.1))
			walls.append(Transform3D(b, center + (p0 + p1) * 0.5 + Vector3(0, lift + h * 0.5, 0)))
			if s % 5 == 0:
				var th := h + 2.2
				towers.append(Transform3D(Basis.from_scale(Vector3(1.6, th, 1.6)), center + p0 + Vector3(0, lift + th * 0.5, 0)))
	_multi(BoxMesh.new(), walls, wall)
	_multi(BoxMesh.new(), towers, wall)
	# the castle itself (Tripo), standing on the top terrace
	var castle := CASTLE_SCENE.instantiate() as Node3D
	_world.add_child(castle)
	castle.scale = Vector3.ONE * 30.0
	castle.position = center + Vector3(0, 7 * 0.9 - 0.5, 0)
	castle.rotation_degrees.y = -20.0
	_stylize(castle, Color(0.95, 0.97, 0.9), 0.0)
	_build_inner_wall()
	_build_rails()
	_build_gallows(Vector3(-8.5, 0.0, -13.5))


## The innermost wall, all round you: the meadow is inside the castle (in Dante you pass seven
## gates to reach it). Battlements on top, towers, and the open gate behind you, where you
## came in.
const INNER_R := 17.0
const INNER_H := 7.0


func _build_inner_wall() -> void:
	var wall := _toon(WALL_TEX, Color(0.95, 0.95, 0.9), 0.0)
	wall.uv1_triplanar = true
	wall.uv1_scale = Vector3(0.3, 0.3, 0.3)
	var c := Vector3(CLEARING.x, 0, CLEARING.y)
	var segs := 72
	var gate := PI * 0.5 - TAU / segs * 0.5        # the segment straight behind you
	var blocks: Array[Transform3D] = []
	var merlons: Array[Transform3D] = []
	var towers: Array[Transform3D] = []
	for s: int in range(segs):
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var mid := (a0 + a1) * 0.5
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * INNER_R
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * INNER_R
		var along := p1 - p0
		var base := minf(height_at(p0.x, p0.z), height_at(p1.x, p1.z)) - 0.5
		var basis := Basis.looking_at(along.normalized(), Vector3.UP)
		var centre := (p0 + p1) * 0.5
		var is_gate := absf(angle_difference(mid, gate)) < TAU / segs * 1.1
		if is_gate:
			# the arch over the open gate
			blocks.append(Transform3D(basis * Basis.from_scale(Vector3(1.4, 2.0, along.length() + 0.1)), Vector3(centre.x, base + INNER_H - 1.0, centre.z)))
		else:
			blocks.append(Transform3D(basis * Basis.from_scale(Vector3(1.4, INNER_H, along.length() + 0.1)), Vector3(centre.x, base + INNER_H * 0.5, centre.z)))
		# two merlons per stretch
		for k: float in [0.25, 0.75]:
			var q := p0.lerp(p1, k)
			merlons.append(Transform3D(basis * Basis.from_scale(Vector3(1.4, 0.8, 0.55)), Vector3(q.x, base + INNER_H + 0.4, q.z)))
		if s % 9 == 0 or absf(angle_difference(a0, gate - TAU / segs)) < 0.01 or absf(angle_difference(a0, gate + TAU / segs * 2.0)) < 0.01:
			towers.append(Transform3D(Basis.from_scale(Vector3(2.6, (INNER_H + 3.0) * 0.5, 2.6)), Vector3(p0.x, base + (INNER_H + 3.0) * 0.5, p0.z)))
	_multi(BoxMesh.new(), blocks, wall)
	_multi(BoxMesh.new(), merlons, wall)
	var tower := CylinderMesh.new()
	tower.top_radius = 0.5
	tower.bottom_radius = 0.55
	tower.radial_segments = 10
	_multi(tower, towers, wall)


func _multi(mesh: Mesh, at: Array[Transform3D], mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i: int in range(at.size()):
		mm.set_instance_transform(i, at[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	_world.add_child(mmi)
	return mmi


func _rail_z(x: float) -> float:
	return -12.5 + sin(x * 0.05) * 2.5


## A railway across the meadow, left to right in front of the castle: rusted rails, rotten
## ties, with gaps where it is torn up and a few rails bent loose.
func _build_rails() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1879
	var rail := BoxMesh.new()
	rail.size = Vector3(1.0, 0.09, 0.07)
	var tie := BoxMesh.new()
	tie.size = Vector3(0.22, 0.08, 1.9)
	var rails: Array[Transform3D] = []
	var ties: Array[Transform3D] = []
	var x := -14.0
	while x < 14.0:
		var broken := absf(x - 5.0) < 2.0 or absf(x + 9.0) < 1.5     # torn up here
		var z := _rail_z(x)
		var dir := Vector3(1.0, 0, _rail_z(x + 1.0) - z).normalized()
		var side := dir.cross(Vector3.UP)
		var yaw := atan2(-dir.z, dir.x)
		if not broken:
			ties.append(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.15, 0.15)), Vector3(x, height_at(x, z) + 0.02, z)))
			for k: float in [-0.72, 0.72]:
				var p := Vector3(x + 0.5, 0, z) + side * k
				var b := Basis(Vector3.UP, yaw)
				if rng.randf() < 0.06:
					b = b * Basis(Vector3.FORWARD, rng.randf_range(0.2, 0.5))      # bent up, loose
				rails.append(Transform3D(b, Vector3(p.x, height_at(p.x, p.z) + 0.1, p.z)))
		x += 1.0
	_multi(rail, rails, _toon(null, Color(0.32, 0.2, 0.14), 0.0))
	_multi(tie, ties, _toon(null, Color(0.26, 0.2, 0.15), 0.0))


func _build_gallows(at: Vector3) -> void:
	at.y = height_at(at.x, at.z)
	var wood := _toon(null, Color(0.22, 0.17, 0.13), 0.0)
	var root := Node3D.new()
	root.position = at
	root.rotation_degrees.y = 25.0
	_world.add_child(root)
	for part: Array in [
			[Vector3(0.35, 5.0, 0.35), Vector3(0, 2.5, 0), 0.0],          # the post
			[Vector3(2.6, 0.3, 0.3), Vector3(1.15, 4.9, 0), 0.0],          # the beam
			[Vector3(0.22, 1.5, 0.22), Vector3(0.5, 4.3, 0), -45.0],       # the brace
			[Vector3(0.04, 1.2, 0.04), Vector3(2.2, 4.15, 0), 0.0],        # the rope
			[Vector3(2.4, 0.3, 2.0), Vector3(1.4, 0.15, 0), 0.0]]:         # the platform
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		mi.mesh = b
		mi.material_override = wood
		mi.position = part[1]
		mi.rotation_degrees.z = part[2]
		root.add_child(mi)
	var noose := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.14
	ring.outer_radius = 0.19
	noose.mesh = ring
	noose.material_override = wood
	noose.position = Vector3(2.2, 3.4, 0)
	noose.rotation_degrees.x = 90.0
	root.add_child(noose)


# ------------------------------------------------------------------ Lust
## "A place mute of all light": you rest at the bottom of a pit of rock. The walls rise close
## all round and lean in over you until only a ragged hole of dirty sky is left, and inside
## it the gale goes round and round without end, sand and ash and the souls with it.
var _gust := 0.0
var _wind_fx: Array[GPUParticles3D] = []
var _souls_fx: Array[GPUParticles3D] = []
const PIT_CENTER := Vector2(0.2, -3.2)
const PIT_R := 8.5            # the walls stand this far from the middle (the way in fits)
const PIT_H := 6.2           # the roof: low, right over you


func _build_lust() -> void:
	_tint_fire(Color(1.0, 0.6, 0.62), Color(0.78, 0.08, 0.2), Color(0.36, 0.02, 0.08), Color(0.1, 0.0, 0.03),
		Color("#ff3c58"), Color("#e0284a"))
	var em := _ember_fx.process_material as ParticleProcessMaterial
	em.gravity = Vector3(2.2, 0.25, 0.3)
	em.initial_velocity_min = 0.5
	em.initial_velocity_max = 1.2
	_ember_fx.amount = 26
	_ember_fx.lifetime = 2.5
	for fm: ShaderMaterial in [_flame_mat, _flame_front_mat]:
		fm.set_shader_parameter("speed", 1.7)          # whipped, not calm
	_build_pit_walls()
	_fire_light.omni_range = 15.0          # the fire reaches the walls
	# dirty light falling through the hole above, grazing the walls
	var hole := SpotLight3D.new()
	hole.light_color = Color("#c9a08c")
	hole.light_energy = 3.0
	hole.spot_range = 30.0
	hole.spot_angle = 48.0
	hole.spot_attenuation = 0.6
	hole.shadow_enabled = true
	hole.position = Vector3(PIT_CENTER.x + 1.5, PIT_H + 3.0, PIT_CENTER.y - 1.0)
	hole.rotation_degrees = Vector3(-90, 0, 0)
	_world.add_child(hole)
	# the gale goes round the pit: emitters all the way round, each blowing along the wall
	for k: int in range(8):
		var w := _wind(TAU * k / 8.0, 5.5)
		_world.add_child(w)
		_wind_fx.append(w)
	for k: int in range(5):
		var s := _souls(TAU * k / 5.0 + 0.3)
		_world.add_child(s)
		_souls_fx.append(s)


## The pit: a ring of rock (cave_rock.png from all sides) bumped in and out by noise, leaning
## in as it rises, so the opening above is far narrower than the floor.
func _build_pit_walls() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 66
	noise.frequency = 0.18
	noise.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na := 96
	var nh := 26
	var verts: Array[Vector3] = []
	for j: int in range(nh + 1):
		var v := float(j) / nh
		for i: int in range(na + 1):
			var a := TAU * i / na
			var dir := Vector3(cos(a), 0, sin(a))
			# a low vault: the wall rises a little, then bends over into a roof that comes
			# in over your head, leaving only a small ragged hole in the middle
			var phi := v * deg_to_rad(80.0)
			var p := dir * PIT_R
			var bump := noise.get_noise_3d(p.x * 1.4, v * 9.0, p.z * 1.4)
			var r := PIT_R * cos(phi) + bump * 1.6 * (1.0 - v * 0.5)
			var y := PIT_H * sin(phi) - 0.6 + bump * 1.1 * v + noise.get_noise_2d(a * 9.0, 50.0) * 0.4
			verts.append(Vector3(PIT_CENTER.x, 0, PIT_CENTER.y) + dir * r + Vector3(0, y, 0))
	for j: int in range(nh):
		for i: int in range(na):
			var a0 := j * (na + 1) + i
			for idx: int in [a0, a0 + na + 1, a0 + 1, a0 + 1, a0 + na + 1, a0 + na + 2]:
				st.add_vertex(verts[idx])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_build_stalactites()
	var m := _toon(CAVE_TEX, Color(1.0, 0.86, 0.82), 0.0)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.18, 0.18, 0.18)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	_world.add_child(mi)


## One stretch of the gale: sand and ash blowing round the pit at angle `a`, `r` meters from
## the middle, along the wall (counter-clockwise seen from above).
func _wind(a: float, r: float) -> GPUParticles3D:
	# not lines: veils of sand and ash, big and faint, sweeping round
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 1.4
	p.preprocess = 2.0
	p.position = Vector3(PIT_CENTER.x + cos(a) * r, 1.8, PIT_CENTER.y + sin(a) * r)
	p.rotation.y = -a          # local -z points along the wall
	p.visibility_aabb = AABB(Vector3(-6, -4, -12), Vector3(14, 14, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.0, 2.5, 1.0)
	pm.direction = Vector3(0, 0.05, -1)      # tangent to the circle at this angle
	pm.spread = 10.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -0.2, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 1.0
	pm.scale_max = 2.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.3))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.45, 0.34, 0.3, 0.0))
	ramp.add_point(0.3, Color(0.45, 0.34, 0.3, 0.22))
	ramp.add_point(0.7, Color(0.38, 0.28, 0.26, 0.18))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.3, 0.22, 0.2, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED       # lit red by the fire when close
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 1.3)
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _cross_streak(size: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := size.x * 0.5
	var h := size.y * 0.5
	for side: Vector3 in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
		for v: Vector3 in [-side + Vector3(0, -h, 0), side + Vector3(0, -h, 0), side + Vector3(0, h, 0),
				-side + Vector3(0, -h, 0), side + Vector3(0, h, 0), -side + Vector3(0, h, 0)]:
			st.set_color(Color.WHITE)
			st.add_vertex(v)
	return st.commit()


## The souls in the storm: pale figures, arms flung back, carried round the pit high up and
## low, rising and falling on the wind.
func _souls(a: float) -> GPUParticles3D:
	var rows := [
		"....xx....",
		"...xxxx...",
		"....xx....",
		"xx..xx....",
		".xxxxxx...",
		"...xxxxxx.",
		"...xxx..xx",
		"...xxx....",
		"..xx.xx...",
		".xx...xx..",
		"xx.....xx.",
	]
	var img := Image.create(10, 11, false, Image.FORMAT_RGBA8)
	for y: int in range(rows.size()):
		var row: String = rows[y]
		for x: int in range(10):
			img.set_pixel(x, y, Color(1, 1, 1, 1) if row[x] == "x" else Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var p := GPUParticles3D.new()
	p.amount = 5
	p.lifetime = 1.6
	p.preprocess = 2.0
	var r := PIT_R * 0.7
	p.position = Vector3(PIT_CENTER.x + cos(a) * r, 2.6, PIT_CENTER.y + sin(a) * r)
	p.rotation.y = -a
	p.visibility_aabb = AABB(Vector3(-6, -6, -16), Vector3(16, 16, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.0, 1.4, 1.0)
	pm.direction = Vector3(0, 0.1, -1)
	pm.spread = 12.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0      # tossed up and down
	pm.turbulence_noise_scale = 7.0
	pm.angle_min = -35.0
	pm.angle_max = 35.0
	pm.angular_velocity_min = -80.0
	pm.angular_velocity_max = 80.0
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.7, 0.7, 0.0))
	ramp.add_point(0.2, Color(0.75, 0.7, 0.7, 0.6))
	ramp.add_point(0.8, Color(0.75, 0.7, 0.7, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.75, 0.7, 0.7, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.1)
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Teeth of rock hanging from the roof, so you see it is right over you.
func _build_stalactites() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 0.0
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	var at: Array[Transform3D] = []
	while at.size() < 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, PIT_R * 0.85)
		var q := Vector2(PIT_CENTER.x, PIT_CENTER.y) + Vector2(cos(a), sin(a)) * r
		if q.distance_to(Vector2(FIRE_AT.x, FIRE_AT.z)) < 1.2:
			continue          # not over the flames
		# the roof's height there (the vault: r = R cos(phi), y = H sin(phi))
		var phi := acos(clampf(r / PIT_R, 0.0, 1.0))
		var roof := PIT_H * sin(phi) - 0.6
		var length := rng.randf_range(0.4, 1.8) * (0.6 + 0.4 * (1.0 - r / PIT_R))
		var b := Basis.from_scale(Vector3(rng.randf_range(0.7, 1.6), length, rng.randf_range(0.7, 1.6)))
		at.append(Transform3D(b, Vector3(q.x, roof - length * 0.5 + 0.3, q.y)))
	var m := _toon(CAVE_TEX, Color(0.95, 0.8, 0.76), 0.0)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_multi(cone, at, m)
