class_name ShopView
extends SubViewportContainer

## The shop: a trading post counter with a teller's cage. The player stands at the
## counter; behind the bars the shopkeeper (a hare in a waistcoat and apron, bunny.glb)
## leans on his glass display case. The cards for sale lie on a leather mat on the
## player's side, with a bottle of whisky and the player's coins. Coins are pushed under
## the bars onto his glass; he picks them up, bites one and pockets them.
## A kerosene lantern lights the counter and moonlight from a back window throws the
## shadow of the bars across it. His ears, blinks and glances live in shopkeeper_face.gd.
## Same look as the duel (fat pixels, dithering, toon shading), different place.
## The player's arms are real 3D: a fist travels to an item, closes on it and the
## item moves with the fist from then on.

const CardViewScript = preload("res://scripts/game/card_view.gd")
const BUNNY_SCENE := preload("res://assets/models/bunny.glb")
const ShopkeeperFace := preload("res://scripts/run/ui/shopkeeper_face.gd")
const PROPS_SCENE := preload("res://assets/models/table_set.glb")
const WALL_TEX := preload("res://assets/textures/saloon_wall.jpg")
const WOOD_TEX := preload("res://assets/textures/wood_grain.png")
const FABRIC_TEX := preload("res://assets/textures/fabric_noise.png")
const GRIME_TEX := preload("res://assets/textures/grime.png")
const OUTLINE := preload("res://resources/shaders/outline.gdshader")

const PIXEL_SHRINK := 3
const CARD_SIZE := Vector2(0.088, 0.124)
const COIN_VALUE := 5
const COUNTER_TOP := 1.0
const CAM_AT := Vector3(0.0, 1.56, 0.95)
const LOOK_AT := Vector3(0.0, 1.16, -0.3)
const ITEM_Z := 0.29
const ITEM_GAP := 0.13
const PURSE := Vector3(-0.29, COUNTER_TOP, 0.36)
const BOTTLE_AT := Vector3(0.34, COUNTER_TOP, 0.32)
const SLOT := Vector3(0.0, COUNTER_TOP, 0.1)     # the gap under the bars
const BARS_Z := 0.04
const CANDLE_AT := Vector3(0.5, COUNTER_TOP, -0.3)
const MERCHANT_AT := Vector3(0.0, 0.0, -0.62)   # the shopkeeper stands behind his display case
const CASE_NEAR := -0.42                        # the case's edge on his side (its other edge is at the bars)
const COIN_SPOT := Vector3(0.006, COUNTER_TOP, -0.174)   # where pushed coins stop on his glass (he picks them there)
# between his thumb and index tips, in Godot's hand.R bone space. Measured IN GODOT (the glTF
# import gives the bones other local axes than Blender's, so Blender's offset does not carry over)
const PINCH := Vector3(0.0230, 0.1167, 0.0659)
# when things happen in his clips (seconds, 30 fps)
const TAKE_GRAB := 32.0 / 30.0
const TAKE_POCKET := 123.0 / 30.0
const FIDGETS := ["sniff", "scratch", "polish", "yawn", "drum", "listen", "ear_fix", "drum"]
const INK := Color("#141010")
const ARM := Color("#2a2422")
const UPPER_LEN := 0.4
const FORE_LEN := 0.4

## Index under the mouse: 0..n-1 the cards, n the bottle, -1 nothing.
var hover := -1
var bottle_index := 0
var viewport: SubViewport
var camera: Camera3D

var _world: Node3D
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _toon_cache := {}
var _items := {}           # index -> card node (on the counter or in a fist)
var _item_rest := {}       # index -> resting transform on the mat
var _item_lift := {}       # index -> 0..1 hover
var _bottle: Node3D
var _bottle_rest := Transform3D()
var _bottle_len := 0.26
var _bottle_lift := 0.0
var _bottle_enabled := true
var _coin_mesh: Mesh
var _coin_mat: Material
var _coin_h := 0.003
var _purse: Array[Node3D] = []
var _anim: AnimationPlayer
var _merchant_clip := "idle"
var _fidget_wait := 6.0
var _face: Node            # shopkeeper_face.gd (ears, blinks, glances)
var _skeleton: Skeleton3D
var _hand_r: BoneAttachment3D
var _offer_cool := 0.0
var _last_hover := -1
var _mood_stamp := 0
var _lantern: OmniLight3D
var _flame: StandardMaterial3D
var _flicker := 0.0
var _fx := {"flash": 0.0, "wobble": 0.0, "aberration": 0.0, "desaturate": 0.0, "blackout": 0.0}
var _shake := 0.0
# hands: fist node (items get parented to it), arm meshes, whether a move owns it
var _fist := {}
var _parts := {}
var _hand_busy := {"L": false, "R": false}


func _ready() -> void:
	_rng.randomize()
	stretch = true
	stretch_shrink = PIXEL_SHRINK
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var dither := ShaderMaterial.new()
	dither.shader = preload("res://resources/shaders/pixel_dither.gdshader")
	material = dither
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.own_world_3d = true
	add_child(viewport)
	_world = Node3D.new()
	viewport.add_child(_world)
	_build_environment()
	_build_room()
	_build_counter()
	_build_props()
	_build_merchant()
	_build_hands()


# ------------------------------------------------------------------ materials
func _mat(color: Color, tex: Texture2D = null, outline := 0.0, uv := 3.0) -> StandardMaterial3D:
	var key := [color, tex, outline, uv]
	if _toon_cache.has(key):
		return _toon_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(uv, uv, uv)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("grow", outline)
		m.next_pass = o
	_toon_cache[key] = m
	return m


## Glb materials -> the game's toon look (textured wood, grimy everything else).
func _stylize(root: Node, outline: float, tints := {}) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s: int in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var n := src.resource_name
			if n.contains("ember"):
				var ember := StandardMaterial3D.new()
				ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				ember.albedo_color = Color("#ff8a3a")
				ember.emission_enabled = true
				ember.emission = Color("#ff6a1a")
				ember.emission_energy_multiplier = 4.0
				mi.set_surface_override_material(s, ember)
				continue
			if n == "stickman" or n.contains("ink"):
				var ink := StandardMaterial3D.new()
				ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				ink.albedo_color = INK
				mi.set_surface_override_material(s, ink)
				continue
			var col: Color = tints.get(n, src.albedo_color)
			var tex: Texture2D = GRIME_TEX
			var gain := 1.15
			if n.begins_with("wood"):
				tex = WOOD_TEX
				gain = 2.1
			elif n.contains("hat"):
				tex = FABRIC_TEX
			mi.set_surface_override_material(s, _mat(Color(col.r * gain, col.g * gain, col.b * gain), tex, outline))


func _box(size: Vector3, at: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = at
	(parent if parent != null else _world).add_child(mi)
	return mi


func _cyl(radius: float, height: float, at: Vector3, m: Material, parent: Node3D = null, top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius if top < 0.0 else top
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = m
	mi.position = at
	(parent if parent != null else _world).add_child(mi)
	return mi


# ------------------------------------------------------------------ the place
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#050404")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#4a4c56")
	env.ambient_light_energy = 0.07
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color("#aab2c0")
	env.volumetric_fog_anisotropy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	camera = Camera3D.new()
	camera.fov = 58.0
	_world.add_child(camera)
	camera.look_at_from_position(CAM_AT, LOOK_AT)

	# moonlight through the back window: a cold shaft that lays the bars' shadow on the counter
	var moon := SpotLight3D.new()
	moon.light_color = Color("#8ea6cc")
	moon.light_energy = 2.6
	moon.spot_range = 5.0
	moon.spot_angle = 16.0
	moon.spot_angle_attenuation = 0.8
	moon.shadow_enabled = true
	moon.light_volumetric_fog_energy = 3.0
	_world.add_child(moon)
	moon.look_at_from_position(Vector3(-1.05, 2.45, -1.62), Vector3(0.05, COUNTER_TOP, 0.32))
	# the shopkeeper's own candle, on the corner of his case: warm light on his face from below
	var candle := OmniLight3D.new()
	candle.light_color = Color("#ff9a48")
	candle.light_energy = 1.1
	candle.omni_range = 1.2
	candle.position = CANDLE_AT + Vector3(0, 0.12, 0)
	_world.add_child(candle)
	# cold rim from the back window: the ears read against the dark wall
	var rim := SpotLight3D.new()
	rim.light_color = Color("#9fb2c8")
	rim.light_energy = 2.0
	rim.spot_range = 2.6
	rim.spot_angle = 28.0
	_world.add_child(rim)
	rim.look_at_from_position(MERCHANT_AT + Vector3(-0.5, 2.1, -0.7), MERCHANT_AT + Vector3(0.0, 1.45, 0.0))
	# a soft warm fill on his face (from the lantern's side), so the eyes and ears read
	var fill := SpotLight3D.new()
	fill.light_color = Color("#ffcf9a")
	fill.light_energy = 0.9
	fill.spot_range = 2.6
	fill.spot_angle = 18.0
	fill.spot_angle_attenuation = 1.4
	_world.add_child(fill)
	fill.look_at_from_position(Vector3(-0.45, 1.75, 0.6), MERCHANT_AT + Vector3(0.0, 1.35, 0.12))


func _build_room() -> void:
	var wall := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(5.0, 5.0 * WALL_TEX.get_height() / WALL_TEX.get_width())
	wall.mesh = q
	var wm := StandardMaterial3D.new()
	wm.albedo_texture = WALL_TEX
	wm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	wm.albedo_color = Color(0.32, 0.28, 0.26)
	wall.material_override = wm
	wall.position = Vector3(0.0, q.size.y * 0.5, -1.7)
	_world.add_child(wall)
	# the window the moon comes through
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("#6f86ad")
	_box(Vector3(0.5, 0.62, 0.01), Vector3(-1.05, 2.35, -1.69), glow)
	var frame := _mat(Color("#1d1512"), WOOD_TEX)
	_box(Vector3(0.04, 0.66, 0.03), Vector3(-1.05, 2.35, -1.67), frame)
	_box(Vector3(0.54, 0.04, 0.03), Vector3(-1.05, 2.35, -1.67), frame)
	# shelves of bottles behind the merchant
	var plank := _mat(Color("#5a3a22"), WOOD_TEX, 0.004)
	var glass := [Color("#2f4a2a"), Color("#5a3218"), Color("#3a2a1a"), Color("#6a5a3a"), Color("#2a2e3a")]
	for row: int in range(3):
		var y := 1.18 + row * 0.38
		_box(Vector3(1.3, 0.03, 0.22), Vector3(0.85, y, -1.58), plank)
		var x := 0.26
		while x < 1.45:
			var h := _rng.randf_range(0.16, 0.3)
			var r := _rng.randf_range(0.025, 0.04)
			var m := _mat(glass[_rng.randi() % glass.size()], GRIME_TEX, 0.003)
			_cyl(r, h, Vector3(x, y + 0.015 + h * 0.5, -1.58 + _rng.randf_range(-0.04, 0.04)), m)
			_cyl(r * 0.35, h * 0.35, Vector3(x, y + 0.015 + h + h * 0.17, -1.58), m)
			x += r * 2.0 + _rng.randf_range(0.01, 0.06)
	# floor (barely seen)
	var floor := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(8, 8)
	floor.mesh = p
	floor.material_override = _mat(Color("#2a1c14"), WOOD_TEX, 0.0, 1.0)
	_world.add_child(floor)


func _build_counter() -> void:
	var wood := _mat(Color("#7a4a2a"), WOOD_TEX, 0.004)
	var dark := _mat(Color("#3a2416"), WOOD_TEX, 0.004)
	# top slab and front panel (the player's side)
	_box(Vector3(2.6, 0.06, 0.57), Vector3(0.0, COUNTER_TOP - 0.03, 0.285), wood)
	_box(Vector3(2.6, COUNTER_TOP - 0.06, 0.04), Vector3(0.0, (COUNTER_TOP - 0.06) * 0.5, 0.55), dark)
	# leather mat where the stock is laid out
	_box(Vector3(0.52, 0.004, 0.22), Vector3(0.0, COUNTER_TOP + 0.002, ITEM_Z), _mat(Color("#3a2a20"), FABRIC_TEX, 0.0, 6.0))
	# the cage: rails and bars; the gap under the bottom rail is where money and goods pass
	var brass := _mat(Color("#8a6a34"), GRIME_TEX, 0.003)
	var iron := _mat(Color("#2b2a2a"), GRIME_TEX, 0.003)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.04, 0.155, 0.04), Vector3(side * 0.62, COUNTER_TOP + 0.078, BARS_Z), brass)
	_box(Vector3(2.6, 0.03, 0.05), Vector3(0.0, COUNTER_TOP + 0.155, BARS_Z), brass)
	_box(Vector3(2.6, 0.03, 0.05), Vector3(0.0, 2.05, BARS_Z), brass)
	var x := -1.28
	while x <= 1.29:
		_cyl(0.008, 2.4 - COUNTER_TOP - 0.17, Vector3(x, (COUNTER_TOP + 0.17 + 2.4) * 0.5, BARS_Z), iron)
		x += 0.085
	# kerosene lantern on the counter: the warm key light on the stock
	var lantern := Node3D.new()
	lantern.position = Vector3(-0.58, COUNTER_TOP, 0.22)
	_world.add_child(lantern)
	_cyl(0.06, 0.03, Vector3(0, 0.015, 0), iron, lantern)
	var chimney := StandardMaterial3D.new()
	chimney.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chimney.albedo_color = Color(0.9, 0.75, 0.5, 0.28)
	chimney.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cyl(0.035, 0.13, Vector3(0, 0.095, 0), chimney, lantern, 0.022)
	_cyl(0.045, 0.02, Vector3(0, 0.17, 0), iron, lantern, 0.02)
	_flame = StandardMaterial3D.new()
	_flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame.albedo_color = Color("#ffd27a")
	_flame.emission_enabled = true
	_flame.emission = Color("#ffb04a")
	_flame.emission_energy_multiplier = 5.0
	var flame := _cyl(0.008, 0.03, Vector3(0, 0.07, 0), _flame, lantern, 0.002)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lantern = OmniLight3D.new()
	_lantern.light_color = Color("#ffb468")
	_lantern.light_energy = 1.7
	_lantern.omni_range = 1.7
	_lantern.omni_attenuation = 1.4
	_lantern.shadow_enabled = true
	_lantern.position = Vector3(0, 0.08, 0)
	lantern.add_child(_lantern)


## Borrows the bottle, the glass and a coin from the props model; the rest is dropped.
func _build_props() -> void:
	var props := PROPS_SCENE.instantiate()
	_world.add_child(props)
	_stylize(props, 0.0045)
	var body := props.find_child("Prop_Bottle", true, false) as Node3D
	var label := props.find_child("Prop_Label", true, false) as Node3D
	var coin := props.find_child("Prop_Coin0", true, false) as MeshInstance3D
	_bottle = Node3D.new()
	_world.add_child(_bottle)
	if body != null:
		_bottle.global_position = body.global_position
		body.reparent(_bottle, true)
		var aabb := (body as MeshInstance3D).get_aabb() if body is MeshInstance3D else AABB()
		if aabb.size.y > 0.0:
			_bottle_len = aabb.size.y * body.global_basis.get_scale().y
	if label != null:
		label.reparent(_bottle, true)
	# placed on this counter
	_bottle.global_position = BOTTLE_AT
	_bottle.rotation.y = 0.4
	_bottle_rest = _bottle.global_transform
	if coin != null:
		_coin_mesh = coin.mesh
		_coin_mat = coin.get_active_material(0)
		_coin_h = maxf(coin.mesh.get_aabb().size.y, 0.002)
	else:
		var c := CylinderMesh.new()
		c.top_radius = 0.014
		c.bottom_radius = 0.014
		c.height = 0.003
		_coin_mesh = c
		_coin_mat = _mat(Color("#c9954f"))
	props.queue_free()


func _build_merchant() -> void:
	_build_case()
	var m := BUNNY_SCENE.instantiate() as Node3D
	m.position = MERCHANT_AT
	_world.add_child(m)
	_stylize_bunny(m)
	_anim = m.find_children("*", "AnimationPlayer", true, false)[0]
	for n: String in _anim.get_animation_list():
		if n.ends_with("idle"):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim.animation_finished.connect(func(_n: StringName) -> void: _merchant_play("idle", 0.45))
	_skeleton = m.find_children("*", "Skeleton3D", true, false)[0]
	_face = ShopkeeperFace.new()
	_skeleton.add_child(_face)
	_hand_r = BoneAttachment3D.new()
	_hand_r.bone_name = "hand.R"
	_skeleton.add_child(_hand_r)
	_merchant_play("idle", 0.0)


## His display case: a wooden base and a glass box, its glass top flush with the counter
## (the money slides under the bars straight onto it). A few wares inside.
func _build_case() -> void:
	var wood := _mat(Color("#5a3820"), WOOD_TEX, 0.004)
	var dark := _mat(Color("#2a1a10"), WOOD_TEX)
	var depth := -CASE_NEAR
	var cz := CASE_NEAR * 0.5
	var glass_h := 0.2
	var base_h := COUNTER_TOP - glass_h - 0.02
	_box(Vector3(1.5, base_h, depth), Vector3(0.0, base_h * 0.5, cz), dark)
	# the floor of the glass box (the wares lie on it) and the wooden frame
	_box(Vector3(1.46, 0.02, depth - 0.02), Vector3(0.0, base_h + 0.01, cz), _mat(Color("#4a2a1c"), FABRIC_TEX, 0.0, 5.0))
	for x: float in [-0.74, 0.0, 0.74]:
		for z: float in [CASE_NEAR + 0.015, -0.015]:
			_box(Vector3(0.025, glass_h, 0.025), Vector3(x, base_h + glass_h * 0.5, z), wood)
	_box(Vector3(1.5, 0.02, 0.025), Vector3(0.0, COUNTER_TOP - 0.01, CASE_NEAR + 0.0125), wood)
	# the glass must READ as a surface (his paws rest on it): a tinted pane, a wooden rim all
	# round and a couple of pale streaks of the lantern's reflection
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.7, 0.74, 0.32)
	glass.metallic_specular = 1.0
	glass.roughness = 0.15
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var top := _box(Vector3(1.48, 0.006, depth), Vector3(0.0, COUNTER_TOP - 0.003, cz), glass)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x: float in [-0.75, 0.75]:
		_box(Vector3(0.03, 0.02, depth), Vector3(x, COUNTER_TOP - 0.008, cz), wood)
	_box(Vector3(1.53, 0.02, 0.03), Vector3(0.0, COUNTER_TOP - 0.008, -0.012), wood)
	var streak := StandardMaterial3D.new()
	streak.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.albedo_color = Color(0.95, 0.92, 0.85, 0.22)
	for k: int in range(2):
		var st := _box(Vector3(0.5 - k * 0.22, 0.001, 0.018 + k * 0.01), Vector3(-0.3 + k * 0.62, COUNTER_TOP + 0.0005, cz + 0.06 - k * 0.12), streak)
		st.rotation.y = 0.55
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# wares: cartridge boxes, a pocket watch, a knife, small bottles of tonic
	var rng := RandomNumberGenerator.new()
	rng.seed = 1879
	var floor_y := base_h + 0.02
	var boxes := [Color("#7a2a1e"), Color("#3e4a2c"), Color("#8a6a34")]
	for k: int in range(5):
		var x := -0.62 + k * 0.29 + rng.randf_range(-0.03, 0.03)
		var z := cz + rng.randf_range(-0.08, 0.08)
		match k % 3:
			0:
				var b := _box(Vector3(0.09, 0.045, 0.06), Vector3(x, floor_y + 0.0225, z), _mat(boxes[k % boxes.size()], GRIME_TEX, 0.003))
				b.rotation.y = rng.randf_range(-0.4, 0.4)
			1:
				var bottle := _mat(Color("#2f4a2a"), GRIME_TEX, 0.003)
				for j: int in range(2):
					var h := rng.randf_range(0.1, 0.13)
					var bx := x + j * 0.06
					_cyl(0.022, h, Vector3(bx, floor_y + h * 0.5, z), bottle)
					_cyl(0.009, 0.03, Vector3(bx, floor_y + h + 0.015, z), bottle)
			2:
				var watch := _cyl(0.026, 0.01, Vector3(x, floor_y + 0.005, z), _mat(Color("#c9954f"), GRIME_TEX, 0.002))
				watch.rotation.x = 0.1
				var blade := _box(Vector3(0.16, 0.006, 0.022), Vector3(x + 0.1, floor_y + 0.003, z + 0.05), _mat(Color("#8a8f94"), GRIME_TEX, 0.002))
				blade.rotation.y = 0.5
	# his candle on the corner of the case
	var wax := _mat(Color("#d8c8a0"))
	_cyl(0.03, 0.012, CANDLE_AT + Vector3(0, 0.006, 0), _mat(Color("#8a6a34"), GRIME_TEX, 0.002))
	_cyl(0.014, 0.08, CANDLE_AT + Vector3(0, 0.052, 0), wax)
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.albedo_color = Color("#ffd27a")
	var f := _cyl(0.005, 0.02, CANDLE_AT + Vector3(0, 0.102, 0), flame, null, 0.001)
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## His materials: the painted texture with hard pixels, glossy dark eyes with a glint
## that never shades, a dark mouth and ivory teeth.
func _stylize_bunny(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s: int in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var n := src.resource_name
			var m := StandardMaterial3D.new()
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.roughness = 1.0
			if n.begins_with("tx_"):
				m.albedo_texture = src.albedo_texture
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				m.albedo_color = Color(0.9, 0.86, 0.84)
				var o := ShaderMaterial.new()
				o.shader = OUTLINE
				o.set_shader_parameter("grow", 0.004)
				m.next_pass = o
			elif n.contains("glint"):
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.albedo_color = Color(1, 0.97, 0.9)
			elif n.contains("eye"):
				m.albedo_color = Color("#120a07")
				m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
				m.roughness = 0.25
			elif n.contains("mouth"):
				m.albedo_color = Color("#2a0e0c")
			elif n.contains("teeth"):
				m.albedo_color = Color("#cfc4a4")
			else:
				m.albedo_color = src.albedo_color
			mi.set_surface_override_material(s, m)


func _merchant_play(clip: String, blend := 0.35) -> void:
	for n: String in _anim.get_animation_list():
		if n == clip or n.ends_with("/" + clip):
			_merchant_clip = clip
			_anim.play(n, blend)
			return


# ------------------------------------------------------------------ the player's arms
func _build_hands() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = ARM
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for side: String in ["L", "R"]:
		var sgn := -1.0 if side == "L" else 1.0
		var fist := Node3D.new()
		_world.add_child(fist)
		fist.global_transform = _rest_pose(side)
		_fist[side] = fist
		var ball := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 2.0
		ball.mesh = sph
		ball.material_override = m
		ball.scale = Vector3(0.033, 0.036, 0.04)
		fist.add_child(ball)
		# thumb, wrapped over the top toward the inside
		var thumb := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.011
		cap.height = 0.05
		thumb.mesh = cap
		thumb.material_override = m
		thumb.position = Vector3(-sgn * 0.016, 0.026, -0.012)
		thumb.rotation = Vector3(-1.1, 0.0, sgn * 0.9)
		fist.add_child(thumb)
		for part: String in ["upper", "fore", "elbow"]:
			var mi := MeshInstance3D.new()
			if part == "elbow":
				var e := SphereMesh.new()
				e.radius = 0.024
				e.height = 0.048
				mi.mesh = e
			else:
				var c := CylinderMesh.new()
				c.top_radius = 1.0
				c.bottom_radius = 1.0
				c.height = 1.0
				c.radial_segments = 10
				mi.mesh = c
			mi.material_override = m
			_world.add_child(mi)
			_parts[side + part] = mi


func _rest_pose(side: String) -> Transform3D:
	var sgn := -1.0 if side == "L" else 1.0
	return Transform3D(Basis(Vector3.UP, -sgn * 0.25), Vector3(sgn * 0.2, COUNTER_TOP + 0.05, 0.47))


func _shoulder(side: String) -> Vector3:
	var sgn := -1.0 if side == "L" else 1.0
	return camera.global_transform * Vector3(sgn * 0.2, -0.3, 0.05)


func _limb(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var y := b - a
	var x := y.cross(camera.global_basis.z)
	if x.length() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized() * r
	var z := x.cross(y).normalized() * r
	mi.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _update_arms() -> void:
	for side: String in ["L", "R"]:
		var sgn := -1.0 if side == "L" else 1.0
		var s := _shoulder(side)
		var f := (_fist[side] as Node3D).global_position
		var d := clampf(s.distance_to(f), 0.05, UPPER_LEN + FORE_LEN - 0.001)
		var dir := (f - s).normalized()
		var a := (UPPER_LEN * UPPER_LEN - FORE_LEN * FORE_LEN + d * d) / (2.0 * d)
		var h := sqrt(maxf(UPPER_LEN * UPPER_LEN - a * a, 0.0))
		# elbows point out and down
		var pole := (camera.global_basis.x * sgn - camera.global_basis.y * 0.8)
		pole = (pole - dir * pole.dot(dir)).normalized()
		var elbow := s + dir * a + pole * h
		_limb(_parts[side + "upper"], s, elbow, 0.022)
		_limb(_parts[side + "fore"], elbow, f, 0.02)
		(_parts[side + "elbow"] as Node3D).global_position = elbow


## Moves a fist to a pose along a small arc (hands lift a little as they travel).
func _move(side: String, to: Transform3D, dur: float, arc := 0.04) -> void:
	_hand_busy[side] = true
	var fist := _fist[side] as Node3D
	var from := fist.global_transform
	var t := create_tween()
	t.tween_method(func(u: float) -> void:
		var e := _smooth(u)
		var xf := from.interpolate_with(to, e)
		xf.origin += Vector3.UP * sin(u * PI) * arc
		fist.global_transform = xf, 0.0, 1.0, dur)
	await t.finished


func _home(side: String, dur: float) -> void:
	await _move(side, _rest_pose(side), dur, 0.03)
	_hand_busy[side] = false


## Where the fist must be so the item it holds ends up at `item_xf`.
func _fist_for(item: Node3D, item_xf: Transform3D) -> Transform3D:
	return item_xf * item.transform.affine_inverse()


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


# ------------------------------------------------------------------ stock
func clear_items() -> void:
	for node in _items.values():
		if is_instance_valid(node):
			(node as Node).queue_free()
	_items.clear()
	_item_rest.clear()
	_item_lift.clear()
	hover = -1


func _card_node(card: Card) -> Node3D:
	var root := Node3D.new()
	for side: int in [0, 1]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = CARD_SIZE
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_texture = CardViewScript.face_for(card) if side == 0 else CardViewScript.back_texture()
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mi.material_override = m
		if side == 1:
			mi.rotation.y = PI
		mi.position.z = 0.0006 if side == 0 else -0.0006
		root.add_child(mi)
	return root


## Lays the cards for sale on the mat (sold ones are gone); cards already there stay put.
func set_items(cards: Array, sold: Array) -> void:
	bottle_index = cards.size()
	var n := cards.size()
	for i: int in range(n):
		var gone := sold.has(i)
		if gone and _items.has(i):
			if (_items[i] as Node3D).get_parent() == _world:
				(_items[i] as Node).queue_free()
			_items.erase(i)
		elif not gone and not _items.has(i):
			var node := _card_node(cards[i])
			var x := (i - (n - 1) * 0.5) * ITEM_GAP
			var b := Basis(Vector3.UP, _rng.randf_range(-0.08, 0.08)) * Basis(Vector3.RIGHT, -PI * 0.5)
			var rest := Transform3D(b, Vector3(x, COUNTER_TOP + 0.006, ITEM_Z + _rng.randf_range(-0.012, 0.012)))
			_world.add_child(node)
			node.global_transform = rest
			_items[i] = node
			_item_rest[i] = rest
			_item_lift[i] = 0.0


func set_bottle_enabled(on: bool) -> void:
	_bottle_enabled = on


func has_item(i: int) -> bool:
	if i == bottle_index:
		return _bottle_enabled and _bottle.get_parent() == _world
	return _items.has(i) and (_items[i] as Node3D).get_parent() == _world


func _screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p) * PIXEL_SHRINK


func item_screen_pos(i: int) -> Vector2:
	if i == bottle_index:
		return _screen(_bottle_rest.origin + Vector3(0, 0.12, 0))
	return _screen((_item_rest[i] as Transform3D).origin) if _item_rest.has(i) else Vector2(-999, -999)


## Where an item's price is written: on the counter, just in front of it.
func price_screen_pos(i: int) -> Vector2:
	if i == bottle_index:
		return _screen(_bottle_rest.origin + Vector3(0, 0, 0.07))
	if not _item_rest.has(i):
		return Vector2(-999, -999)
	return _screen((_item_rest[i] as Transform3D).origin + Vector3(0, 0, CARD_SIZE.y * 0.5 + 0.035))


func purse_screen_pos() -> Vector2:
	return _screen(PURSE + Vector3(-0.085, 0.0, 0.02))


func pick(screen: Vector2) -> int:
	for i: int in _items.keys():
		if not has_item(i):
			continue
		var rest := _item_rest[i] as Transform3D
		var poly := PackedVector2Array()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			poly.append(_screen(rest * Vector3(c.x * CARD_SIZE.x * 0.6, c.y * CARD_SIZE.y * 0.6, 0)))
		if Geometry2D.is_point_in_polygon(screen, poly):
			return i
	if has_item(bottle_index):
		var top := _screen(_bottle_rest.origin + Vector3(0, _bottle_len, 0))
		var bottom := _screen(_bottle_rest.origin)
		if Rect2(Vector2(bottom.x - 30, top.y), Vector2(60, bottom.y - top.y + 8)).has_point(screen):
			return bottle_index
	return -1


# ------------------------------------------------------------------ coins
func set_gold(gold: int) -> void:
	for c in _purse:
		c.queue_free()
	_purse.clear()
	var count := clampi(int(ceil(gold / float(COIN_VALUE))), 0, 48)
	var spots := [Vector2(0, 0), Vector2(0.034, 0.01), Vector2(-0.03, 0.018), Vector2(0.01, 0.04), Vector2(0.046, 0.046), Vector2(-0.02, 0.056)]
	for k: int in range(count):
		var stack := k / 7
		var spot: Vector2 = spots[stack % spots.size()] + Vector2(0.006, -0.004) * (stack / spots.size())
		var coin := MeshInstance3D.new()
		coin.mesh = _coin_mesh
		coin.material_override = _coin_mat
		coin.rotation.y = _rng.randf() * TAU
		_world.add_child(coin)
		coin.global_position = PURSE + Vector3(spot.x + _rng.randf_range(-0.0015, 0.0015), _coin_h * (0.5 + (k % 7) * 1.02), spot.y)
		_purse.append(coin)


## The left hand scoops coins off the purse and pushes them through the slot;
## they slide into the dark and the merchant takes them.
func pay(price: int) -> void:
	var n := clampi(int(ceil(price / float(COIN_VALUE))), 1, maxi(_purse.size(), 1))
	var coins: Array[Node3D] = []
	for k: int in range(n):
		if not _purse.is_empty():
			coins.append(_purse.pop_back())
	var top := PURSE + Vector3(0, _coin_h * 7.0, 0)
	if not coins.is_empty():
		top = coins[0].global_position
	var grab := Transform3D(Basis(Vector3.UP, 0.2) * Basis(Vector3.RIGHT, -0.5), top + Vector3(0, 0.02, 0.012))
	await _move("L", grab, 0.34, 0.05)
	for c in coins:
		c.reparent(_fist["L"], true)
	await _move("L", grab.translated(Vector3(0, 0.04, 0)), 0.12, 0.0)
	var at_slot := Transform3D(Basis(Vector3.RIGHT, -0.6), SLOT + Vector3(0.0, 0.03, 0.06))
	await _move("L", at_slot, 0.42, 0.06)
	# lets them go: they drop on the counter in a little heap
	for k: int in range(coins.size()):
		var c := coins[k]
		c.reparent(_world, true)
		var land := SLOT + Vector3(_rng.randf_range(-0.03, 0.03), _coin_h * (0.5 + (k % 3)), _rng.randf_range(0.0, 0.03))
		var t := create_tween()
		t.tween_property(c, "global_position", land, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.12).timeout
	# a push with the fingertips under the bars: they slide onto his glass and stop in a heap
	await _move("L", at_slot.translated(Vector3(0, -0.012, -0.08)), 0.22, 0.0)
	for k: int in range(coins.size()):
		var c := coins[k]
		var a := k * 2.4
		var to := COIN_SPOT + Vector3(cos(a) * 0.012 * minf(k, 1.0), _coin_h * (0.5 + (k % 4)), sin(a) * 0.01 * minf(k, 1.0))
		var t := create_tween()
		t.tween_property(c, "global_position", to, 0.5 + k * 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_home("L", 0.45)
	await get_tree().create_timer(0.35).timeout
	_shopkeeper_takes(coins)


## The clink on the glass: he picks the coins up between thumb and fingers, bites one and
## pockets them. They are in his hand from the grab until the pocket (never flying).
func _shopkeeper_takes(coins: Array[Node3D]) -> void:
	_merchant_play("take_coins", 0.25)
	_ear_mood(-14.0, -6.0, 1.2)
	await _at_clip("take_coins", TAKE_GRAB - 0.05)
	for k: int in range(coins.size()):
		var c := coins[k]
		if not is_instance_valid(c):
			continue
		c.reparent(_hand_r, true)
		# into the pinch, stacked edge-on between thumb and fingers
		var t := create_tween()
		t.tween_property(c, "position", PINCH + Vector3(0, k * _coin_h * 1.05, 0), 0.07)
		t.parallel().tween_property(c, "quaternion", Quaternion(Vector3.RIGHT, PI * 0.5), 0.07)
	await _at_clip("take_coins", TAKE_POCKET)
	for c in coins:
		if is_instance_valid(c):
			c.queue_free()


## Waits until his current clip reaches `t` seconds (or he is doing something else).
func _at_clip(clip: String, t: float) -> void:
	while is_inside_tree() and _merchant_clip == clip and _anim.current_animation_position < t:
		await get_tree().process_frame


## The ears' mood for a while (degrees: + back = pinned, - = pricked; + out = splayed).
func _ear_mood(back: float, out: float, hold: float) -> void:
	if _face == null:
		return
	_face.ear_back = back
	_face.ear_out = out
	var stamp := Time.get_ticks_msec()
	_mood_stamp = stamp
	await get_tree().create_timer(hold).timeout
	if _mood_stamp == stamp and _face != null:
		_face.ear_back = 0.0
		_face.ear_out = 0.0


## Not enough coins: the hand goes to the purse, finds it short, and he just stares.
func refuse() -> void:
	if _hand_busy["L"]:
		return
	# two ways to say no: the head shake with a wag, or arms crossed in an X, eyes shut
	_merchant_play("refuse_cross" if _rng.randf() < 0.5 else "refuse", 0.25)
	_ear_mood(26.0, 10.0, 3.0)
	var over := Transform3D(Basis(Vector3.RIGHT, -0.5), PURSE + Vector3(0, 0.05, 0.02))
	await _move("L", over, 0.3, 0.04)
	for c in _purse:
		var base := c.position
		var t := create_tween()
		t.tween_property(c, "position", base + Vector3(0, 0.004, 0), 0.05)
		t.tween_property(c, "position", base, 0.12).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await _move("L", over.translated(Vector3(0, -0.02, 0)), 0.08, 0.0)
	await _home("L", 0.4)


# ------------------------------------------------------------------ buying
## The right fist reaches the card's near edge, pinches it, lifts it, turns it to
## look at it and puts it away.
func buy_card(i: int) -> void:
	if not _items.has(i):
		return
	var card := _items[i] as Node3D
	var rest := _item_rest[i] as Transform3D
	var edge := rest.origin + Vector3(0, 0.0, CARD_SIZE.y * 0.42)
	var grip := Transform3D(Basis(Vector3.RIGHT, -0.35), edge + Vector3(0, 0.022, 0.012))
	await _move("R", grip.translated(Vector3(0, 0.06, 0.03)), 0.38, 0.05)
	await _move("R", grip, 0.12, 0.0)
	card.reparent(_fist["R"], true)                   # closed on it
	await _move("R", grip.translated(Vector3(0, 0.07, 0)), 0.16, 0.0)
	# up in front of the eyes, face to the player
	var cb := camera.global_basis
	var look := Transform3D(cb.rotated(cb.x, -0.12), camera.global_transform * Vector3(0.07, -0.1, -0.36))
	await _move("R", _fist_for(card, look), 0.5, 0.03)
	await get_tree().create_timer(0.55).timeout
	# into the vest pocket (down, out of view)
	await _move("R", _fist_for(card, Transform3D(cb.rotated(cb.x, -1.0), camera.global_transform * Vector3(0.24, -0.5, -0.25))), 0.34, 0.0)
	card.queue_free()
	_items.erase(i)
	_nod_later()
	await _home("R", 0.45)


## The right fist takes the bottle by the body, drinks from it and puts it back.
func buy_drink() -> void:
	var grip_at := _bottle_rest.origin + Vector3(0.0, _bottle_len * 0.32, 0.034)
	var grip := Transform3D(Basis(Vector3.UP, 0.2), grip_at)
	await _move("R", grip.translated(Vector3(0.02, 0.04, 0.05)), 0.36, 0.05)
	await _move("R", grip, 0.1, 0.0)
	_bottle.reparent(_fist["R"], true)
	await _move("R", grip.translated(Vector3(0, 0.08, 0)), 0.18, 0.0)
	# neck to the mouth: the bottom tips up, the neck comes down toward the player
	var cam := camera.global_transform
	var mouth := cam * Vector3(0.0, -0.2, -0.12)
	var up := (mouth - cam * Vector3(0.04, -0.06, -0.5)).normalized()
	var z := camera.global_basis.x.cross(up).normalized()
	var xb := up.cross(z).normalized()
	var drink_xf := Transform3D(Basis(xb, up, z), mouth - up * _bottle_len)
	await _move("R", _fist_for(_bottle, drink_xf), 0.5, 0.0)
	# the long pull: warmth, the picture loosens for a moment
	_fx_to("flash", 0.16, 0.25, 0.7)
	_fx_to("wobble", 0.5, 0.35, 1.4)
	var gulp := create_tween()
	for k: int in range(3):
		gulp.tween_property(_fist["R"], "global_position", (_fist["R"] as Node3D).global_position + Vector3(0, 0.006, 0), 0.16)
		gulp.tween_property(_fist["R"], "global_position", (_fist["R"] as Node3D).global_position, 0.18)
	await gulp.finished
	await _move("R", grip.translated(Vector3(0, 0.08, 0)), 0.5, 0.02)
	await _move("R", grip, 0.14, 0.0)
	_bottle.reparent(_world, true)
	_bottle.global_transform = _bottle_rest
	_shake = 0.2
	_nod_later()
	await _home("R", 0.4)


## For the test buttons: every clip he has, and playing one by name (take_coins puts a few
## coins on his glass first so the whole pick-up, bite and pocket can be seen).
func clip_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in _anim.get_animation_list():
		out.append(n.get_slice("/", n.get_slice_count("/") - 1))
	return out


func debug_play(clip: String) -> void:
	if clip == "take_coins":
		var coins: Array[Node3D] = []
		for k: int in range(3):
			var c := MeshInstance3D.new()
			c.mesh = _coin_mesh
			c.material_override = _coin_mat
			_world.add_child(c)
			c.global_position = COIN_SPOT + Vector3(k * 0.006, _coin_h * (0.5 + k), k * 0.004)
			coins.append(c)
		_shopkeeper_takes(coins)
	elif clip == "refuse" or clip == "refuse_cross":
		_merchant_play(clip, 0.25)
		_ear_mood(26.0, 10.0, 3.0)
	else:
		_merchant_play(clip, 0.25)


func merchant_glance() -> void:
	if _merchant_clip == "idle":
		_merchant_play("sniff")


## After the sale he is pleased: as soon as he has pocketed the money, a little nod.
func _nod_later() -> void:
	while is_inside_tree() and _merchant_clip == "take_coins":
		await get_tree().process_frame
	if _merchant_clip == "idle":
		_merchant_play("nod", 0.3)
		_ear_mood(-8.0, 4.0, 1.0)


# ------------------------------------------------------------------ fx
func _fx_to(key: String, peak: float, rise: float, fall: float) -> void:
	var t := create_tween()
	t.tween_method(func(v: float) -> void: _fx[key] = v, _fx[key], peak, rise)
	t.tween_method(func(v: float) -> void: _fx[key] = v, peak, 0.0, fall).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	_time += delta
	var k := 1.0 - exp(-delta * 9.0)
	# stock: the card under the mouse rises off the mat and tilts up to the player
	for i: int in _items.keys():
		var node := _items[i] as Node3D
		if node.get_parent() != _world:
			continue
		_item_lift[i] = lerpf(_item_lift[i], 1.0 if i == hover else 0.0, k)
		var rest := _item_rest[i] as Transform3D
		var u := _smooth(_item_lift[i])
		var xf := rest.rotated_local(Vector3.RIGHT, 0.5 * u)
		xf.origin += Vector3(0, 0.025 * u + sin(_time * 2.3 + i) * 0.0012 * u, 0)
		node.global_transform = xf
	if _bottle.get_parent() == _world:
		_bottle_lift = lerpf(_bottle_lift, 1.0 if hover == bottle_index and _bottle_enabled else 0.0, k)
		_bottle.global_transform = _bottle_rest.rotated_local(Vector3.FORWARD, sin(_time * 3.0) * 0.04 * _bottle_lift)
	# idle hands: they breathe, and the right one leans toward what the eye is on
	var breath := Vector3(0, sin(_time * TAU / 3.8) * 0.003, 0)
	for side: String in ["L", "R"]:
		if _hand_busy[side]:
			continue
		var want := _rest_pose(side)
		want.origin += breath
		if side == "R" and hover >= 0:
			var target := _bottle_rest.origin if hover == bottle_index else ((_item_rest.get(hover, want) as Transform3D).origin)
			want.origin = want.origin.lerp(target + Vector3(0, 0.04, 0.1), 0.18)
		var fist := _fist[side] as Node3D
		fist.global_transform = fist.global_transform.interpolate_with(want, 1.0 - exp(-delta * 5.0))
	_update_arms()
	# shopkeeper: leaning on his case, a habit now and then; he watches what you look at
	_fidget_wait -= delta
	_offer_cool -= delta
	if _fidget_wait <= 0.0:
		_fidget_wait = _rng.randf_range(7.0, 13.0)
		if _merchant_clip == "idle" and hover < 0:
			_merchant_play(FIDGETS[_rng.randi() % FIDGETS.size()])
	if _face != null:
		if hover >= 0:
			var hp := _bottle_rest.origin if hover == bottle_index else ((_item_rest.get(hover, Transform3D()) as Transform3D).origin)
			# while he offers the goods he looks at YOU (not at the goods or his own paw)
			_face.look_target = camera.global_position if _merchant_clip == "offer" else hp
			_face.look_weight = 0.7 if _merchant_clip == "offer" else 1.0
			if hover != _last_hover:
				# the ears prick toward the goods, and the first look gets his pitch
				_face.ear_back = -12.0
				_face.ear_out = 5.0
				if _offer_cool <= 0.0 and _merchant_clip == "idle":
					_offer_cool = 9.0
					_merchant_play("offer", 0.3)
		else:
			_face.look_target = camera.global_position
			_face.look_weight = 0.6
			if _last_hover >= 0:
				_face.ear_back = 0.0
				_face.ear_out = 0.0
	_last_hover = hover
	# the lantern breathes and gutters
	_flicker -= delta
	var level := 1.0 - 0.06 * sin(_time * 23.0) * sin(_time * 2.7)
	if _flicker <= 0.0:
		_flicker = _rng.randf_range(3.0, 9.0)
		level = 0.7
	_lantern.light_energy = 1.7 * level
	_flame.emission_energy_multiplier = 5.0 * level
	# camera: a slow, handheld drift; looks a touch toward what is hovered
	var drift := Vector3(sin(_time * 0.31) * 0.008 + sin(_time * 1.13) * 0.002, sin(_time * 0.47 + 1.0) * 0.005, 0.0)
	if _shake > 0.0:
		drift += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake * 0.02
		_shake = maxf(_shake - delta * 2.0, 0.0)
	var look := LOOK_AT
	if hover >= 0:
		var hp := _bottle_rest.origin if hover == bottle_index else ((_item_rest.get(hover, Transform3D(Basis.IDENTITY, LOOK_AT)) as Transform3D).origin)
		look = LOOK_AT.lerp(hp, 0.12)
	_look = _look.lerp(look, 1.0 - exp(-delta * 2.5))
	camera.look_at_from_position(CAM_AT + drift, _look + drift * 0.3)
	var m := material as ShaderMaterial
	for key: String in _fx.keys():
		m.set_shader_parameter(key, _fx[key])


var _look := LOOK_AT


## Kept for the menu/map screens that reset the scene.
func rival_reset() -> void:
	# either he greets you, or you catch him dozing on the glass and he jumps
	_merchant_play("greet_startle" if _rng.randf() < 0.5 else "greet", 0.0)
	_fidget_wait = _rng.randf_range(8.0, 12.0)
	_hand_busy = {"L": false, "R": false}
	if _bottle.get_parent() != _world:
		_bottle.reparent(_world, true)
	_bottle.global_transform = _bottle_rest
