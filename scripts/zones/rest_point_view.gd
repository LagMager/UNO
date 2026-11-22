class_name RestPointView
extends SubViewportContainer

## The Rest Point (world design doc v0.4): a dark, silent clearing under a starry sky
## with four-pointed stars, a dry twisted tree beside a lit campfire. The fire and the
## sky are the only lights. It is always night.
## Seen in first person, with the same pixelated, dithered look as the duel and the shop.
## In the viewer the camera can be turned by dragging the mouse (R recenters it).

const TREE_SCENE := preload("res://assets/models/zones/rest_point/rp_tree.glb")
const FIRE_SCENE := preload("res://assets/models/zones/rest_point/rp_campfire.glb")
const GROUND_TEX := preload("res://assets/textures/zones/rest_ground.png")
const SKY_SHADER := preload("res://resources/shaders/night_sky.gdshader")
const OUTLINE := preload("res://resources/shaders/outline.gdshader")
const FLAME_SHADER := preload("res://resources/shaders/toon_flame.gdshader")

const PIXEL_SHRINK := 3
const EYE := Vector3(0.0, 1.12, 0.0)     # sitting on the ground by the fire
const FIRE_AT := Vector3(0.75, 0.0, -2.6)     # to one side: the middle of the screen stays dark
const TREE_AT := Vector3(-1.5, 0.0, -5.6)     # behind the fire, against the stars
const LOOK_AT := Vector3(0.1, 0.95, -5.0)    # a little up, so the sky reads
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
	_build_far_trees()
	_build_fire()
	_world.add_child(_dust())
	_world.add_child(_fireflies())
	_build_rocks()
	_build_grass()


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
	env.ambient_light_color = Color("#5c6890")
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.05
	# the clearing ends in darkness: everything far from the fire sinks into black
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#14151f")
	env.fog_density = 1.0
	env.fog_depth_begin = 5.0
	env.fog_depth_end = 26.0
	env.fog_depth_curve = 0.7
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	camera = Camera3D.new()
	camera.fov = 62.0
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
	var m := _toon(GROUND_TEX, Color(0.85, 0.82, 0.8))
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


func _build_far_trees() -> void:
	for t: Array in FAR_TREES:
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
	_fire_light.light_color = Color("#ffa257")
	_fire_light.light_energy = 2.8
	_fire_light.omni_range = 12.0
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
	_flame_mat = _flame_layer(root, Vector2(1.15, 1.6), ground + 0.85, 0.0, 0.0)
	_flame_front_mat = _flame_layer(root, Vector2(0.9, 0.95), ground + 0.5, 0.3, 0.53)
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
	var m := _toon(stone, Color(1.15, 1.1, 1.05), 0.03)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var placed := 0
	while placed < 55:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(2.2, 16.0)
		var at := Vector2(CLEARING.x, CLEARING.y) + Vector2(cos(ang), sin(ang)) * dist
		if Vector2(at.x, at.y).distance_to(Vector2(0, 0)) < 1.6:
			continue        # not on the player
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


## Tufts of dry grass: thin straw blades fanning out, scattered in clumps.
func _grass_mesh() -> ArrayMesh:
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
		st.set_color(Color(shade * 0.55, shade * 0.47, shade * 0.3))
		st.set_normal(Vector3.UP)
		st.add_vertex(base - side)
		st.set_normal(Vector3.UP)
		st.add_vertex(base + side)
		st.set_color(Color(shade * 0.8, shade * 0.7, shade * 0.45))
		st.set_normal(Vector3.UP)
		st.add_vertex(tip)
	return st.commit()


func _build_grass() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _grass_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var spots: Array[Transform3D] = []
	# clumps: a few centers, several tufts around each
	for c: int in range(26):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(2.0, 15.0)
		var center := Vector2(CLEARING.x, CLEARING.y) + Vector2(cos(ang), sin(ang)) * dist
		for k: int in range(rng.randi_range(3, 7)):
			var at := center + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
			if at.distance_to(Vector2(0, 0)) < 1.2 or at.distance_to(Vector2(FIRE_AT.x, FIRE_AT.z)) < 1.1:
				continue
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
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
	_fire_light.light_energy = 2.6 * level
	_glow_light.light_energy = 0.9 * (0.85 + slow * 0.15 + _flare * 0.2)
	var flame_level := clampf(0.92 + slow * 0.1 + _flare * 0.14, 0.8, 1.15)
	_flame_mat.set_shader_parameter("intensity", flame_level)
	_flame_front_mat.set_shader_parameter("intensity", flame_level)
	# the light's center leans with the flames, so shadows sway instead of jumping
	_fire_light.position = FIRE_AT + Vector3(mid * 0.08, 0.85 + slow * 0.06 + _flare * 0.1, _n_fire.get_noise_1d(_time * 0.6 + 20.0) * 0.05)
	_ember_fx.amount_ratio = clampf(0.6 + _flare * 0.6, 0.0, 1.0)


func _update_camera(delta: float) -> void:
	var k := 1.0 - exp(-delta * 8.0)
	_yaw = lerpf(_yaw, _want_yaw, k)
	_pitch = lerpf(_pitch, _want_pitch, k)
	# breathing: barely there
	var breath := Vector3(0, sin(_time * 1.4) * 0.006, 0)
	var base := Basis.looking_at(LOOK_AT - EYE, Vector3.UP)
	var b := Basis(Vector3.UP, _yaw) * base * Basis(Vector3.RIGHT, _pitch)
	camera.global_transform = Transform3D(b, EYE + breath)


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
