class_name DuelView
extends SubViewportContainer

## The duel as a real 3D scene, seen from the player's chair: one camera, so the
## wall, floor, table, chair, cards and the rival all share the same perspective.
## Rendered live at the window resolution. The rival is a rigged stickman whose
## animations (made in Blender) are blended by the AnimationPlayer, so switching
## from one to another never pops.
## Units are meters. The rival sits at -Z (behind the table), the camera at +Z.

signal rival_event(name: String)

const CardViewScript = preload("res://scripts/game/card_view.gd")
const RIVAL_SCENE := preload("res://assets/models/rival.glb")
## Who sits across the table, by kind (see set_rival).
const RIVALS := {
	"tahur": preload("res://assets/models/rival.glb"),
	"matasanos": preload("res://assets/models/matasanos.glb"),
	"gila": preload("res://assets/models/yorkie.glb"),
}
const TABLE_SCENE := preload("res://assets/models/table_set.glb")
const WALL_TEX := preload("res://assets/textures/saloon_wall.jpg")
const FLOOR_TEX := preload("res://assets/textures/floor_planks.png")
const OUTLINE := preload("res://resources/shaders/outline.gdshader")

const TABLE_TOP := 0.782
const PILE := Vector3(0.0, TABLE_TOP, 0.3)
const DECK := Vector3(0.27, TABLE_TOP, 0.28)
const CARD_SIZE := Vector2(0.088, 0.124)
const CAMERA_AT := Vector3(0.0, 1.34, 1.5)
const LOOK_AT := Vector3(0.0, 0.84, 0.05)
const BLEND := 0.32
const PIXEL_SHRINK := 3   # the 3D is rendered at 1/3 of the screen and shown with visible pixels
const WOOD_TEX := preload("res://assets/textures/wood_grain.png")
const FABRIC_TEX := preload("res://assets/textures/fabric_noise.png")
const GRIME_TEX := preload("res://assets/textures/grime.png")
const FIDGETS := ["check", "check", "smoke", "stare", "impatient"]
## Event times (seconds) inside each clip, from the Blender keys at 30 fps.
const EVENTS := {
	"play": {"grab": 6.0 / 30.0, "release": 31.0 / 30.0},
	"draw": {"grab": 11.0 / 30.0, "tuck": 34.0 / 30.0},
	"shoot": {"draw": 14.0 / 30.0, "fire": 30.0 / 30.0, "twirl": 58.0 / 30.0, "twirl_end": 59.0 / 30.0, "holster": 60.0 / 30.0},
	"smoke": {"exhale": 33.0 / 30.0},
	"play_toss": {"grab": 5.0 / 30.0, "release": 16.0 / 30.0},
	"play_place": {"grab": 7.0 / 30.0, "release": 31.0 / 30.0},
}
## The Mixamo rivals' own clips: the hands arrive a few frames later.
const EVENTS_MIXAMO := {
	"play_toss": {"grab": 8.0 / 30.0, "release": 19.0 / 30.0},
	"play_place": {"grab": 10.0 / 30.0, "release": 34.0 / 30.0},
	"draw": {"grab": 14.0 / 30.0, "tuck": 37.0 / 30.0},
	"play_free": {"grab": 17.0 / 30.0, "release": 27.0 / 30.0},
	"play_free_place": {"grab": 17.0 / 30.0, "release": 36.0 / 30.0},
	"shoot": {"draw": 17.0 / 30.0, "fire": 33.0 / 30.0, "twirl": 61.0 / 30.0, "twirl_end": 62.0 / 30.0, "holster": 63.0 / 30.0},
}
const ACTIVE_COLORS := {
	Card.CardColor.RED: Color("#d2402f"),
	Card.CardColor.YELLOW: Color("#e2a83a"),
	Card.CardColor.GREEN: Color("#5aa04a"),
	Card.CardColor.BLUE: Color("#3f78c8"),
}

var viewport: SubViewport
var camera: Camera3D
var _world: Node3D
var _rival: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _fan: Node3D
var _held: Node3D
var _gun: Node3D
var _flash: OmniLight3D
var _pile_root: Node3D
var _deck_root: Node3D
var _ring: MeshInstance3D
var _hand_count := 5
var _current := "idle"
var _clip_time := 0.0
var _fidget_wait := 7.0
var _gun_mode := 0        # 0 hidden, 1 aimed at the player, 2 twirling
var _held_visible := false
var _rng := RandomNumberGenerator.new()
var _toon_cache := {}
var _smoke: GPUParticles3D
var _hat_collider: GPUParticlesCollisionSphere3D
var _ember_local := Transform3D.IDENTITY
# camera director: base framing, an optional focus target blended in, sway and shake
var _focus_w := 0.0
var _focus_pos := CAMERA_AT
var _focus_look := LOOK_AT
var _shake := 0.0
var _time := 0.0
var _eyes: Node3D
var _eye_local := Transform3D.IDENTITY
var _eye_open := 1.0          # 1 normal, <1 squint, >1 wide
var _blink_wait := 2.5
var _grin := 1.0             # 0 closed, 1 normal, >1 wide
## Material name -> color, to dress the same stickman as someone else.
var tint_overrides := {}
## Idle gestures this character picks from.
var fidgets: Array = FIDGETS
var _dt := 0.016
var _hand_vel := Vector3.ZERO
var _last_hand := Vector3.ZERO


func _ready() -> void:
	_setup_view()
	_build_environment()
	_build_room()
	_build_table()
	_build_rival()
	_build_smoke()
	_build_cards()


## The pixelated SubViewport every 3D scene of the game is drawn into.
func _setup_view() -> void:
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


# ------------------------------------------------------------------ scene
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#070403")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#5a5650")
	env.ambient_light_energy = 0.06
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.18
	env.glow_bloom = 0.05
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color("#b8b4ac")
	env.volumetric_fog_anisotropy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	camera = Camera3D.new()
	camera.fov = 50.0
	_world.add_child(camera)
	camera.look_at_from_position(CAMERA_AT, LOOK_AT)

	# one hard lamp straight above the table: the table and the rival pop out of the dark
	_build_lamp()
	# a weak top light on the rival: his silhouette reads, the room stays black
	var dealer := SpotLight3D.new()
	dealer.light_color = Color("#ffe2b8")
	dealer.light_energy = 1.1
	dealer.spot_range = 2.4
	dealer.spot_angle = 22.0
	dealer.spot_angle_attenuation = 1.4
	_world.add_child(dealer)
	dealer.look_at_from_position(Vector3(0.0, 2.1, 0.35), Vector3(0.0, 0.95, -0.2))
	var rim := SpotLight3D.new()
	rim.light_color = Color("#9fb2c8")
	rim.light_energy = 1.4
	rim.spot_range = 2.5
	rim.spot_angle = 30.0
	_world.add_child(rim)
	rim.look_at_from_position(Vector3(0.35, 1.7, -1.1), Vector3(0.0, 0.95, -0.2))
	var fill := OmniLight3D.new()
	fill.light_color = Color("#d8c8b0")
	fill.light_energy = 0.35
	fill.omni_range = 2.2
	fill.position = Vector3(0.0, 1.3, 1.2)
	_world.add_child(fill)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ff9a5c")
	sun.light_energy = 0.1
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 2.5
	_world.add_child(sun)
	sun.look_at_from_position(Vector3(2.4, 2.6, -1.6), Vector3(0.0, 0.7, 0.4))

	_flash = OmniLight3D.new()
	_flash.light_color = Color("#ffd27a")
	_flash.light_energy = 0.0
	_flash.omni_range = 2.5
	_world.add_child(_flash)


func _build_room() -> void:
	var wall := MeshInstance3D.new()
	var q := QuadMesh.new()
	var w := 6.4
	q.size = Vector2(w, w * WALL_TEX.get_height() / WALL_TEX.get_width())
	wall.mesh = q
	var wm := StandardMaterial3D.new()
	wm.albedo_texture = WALL_TEX
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.albedo_color = Color(0.2, 0.17, 0.155)  # the room sinks into shadow
	wall.material_override = wm
	wall.position = Vector3(0.0, q.size.y * 0.5, -1.6)
	_world.add_child(wall)

	var floor := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(10, 10)
	floor.mesh = p
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = FLOOR_TEX
	fm.uv1_scale = Vector3(5.2, 5.2, 1)
	fm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	fm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	fm.roughness = 1.0
	floor.material_override = fm
	floor.position = Vector3(0, 0, 3.4)
	_world.add_child(floor)


func _toon(source: Material, outline: float, unshaded_black := false) -> Material:
	var key := [source, outline, unshaded_black]
	if _toon_cache.has(key):
		return _toon_cache[key]
	var m := StandardMaterial3D.new()
	if source is BaseMaterial3D:
		m.albedo_color = source.albedo_color
		m.albedo_texture = source.albedo_texture
		var n := source.resource_name
		if tint_overrides.has(source.resource_name):
			m.albedo_color = tint_overrides[source.resource_name]
		var tex: Texture2D = null
		var gain := 1.15
		if n.begins_with("tx_"):
			# a model with its own painted texture (made small in Blender): keep it,
			# with hard pixels, a little darker
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			m.albedo_color = Color(0.82, 0.78, 0.76)
		elif n.begins_with("wood"):
			tex = WOOD_TEX
			gain = 2.1
		elif n.contains("hat"):
			tex = FABRIC_TEX
		elif not n.contains("ink") and not n.contains("ember"):
			tex = GRIME_TEX
		if tex != null:
			m.albedo_texture = tex
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
			var base: Color = tint_overrides.get(source.resource_name, source.albedo_color)
			m.albedo_color = Color(base.r * gain, base.g * gain, base.b * gain)
	if unshaded_black:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color("#141010")
	else:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 1.0
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("grow", outline)
		m.next_pass = o
	_toon_cache[key] = m
	return m


func _stylize(root: Node, outline: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s: int in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s)
			var black := src != null and src.resource_name == "stickman"
			if src != null and src.resource_name.contains("ember"):
				var ember := StandardMaterial3D.new()
				ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				ember.albedo_color = Color("#ff8a3a")
				ember.emission_enabled = true
				ember.emission = Color("#ff6a1a")
				ember.emission_energy_multiplier = 4.0
				mi.set_surface_override_material(s, ember)
				continue
			# the inside of the Gila's mouth (lining with inward normals, teeth, tongue): no
			# outline, or the hull would draw black streaks inside the mouth
			var inner := src != null and src.resource_name in ["mouth_in", "teeth", "tongue"]
			mi.set_surface_override_material(s, _toon(src, 0.0 if black or inner else outline, black))


func _build_table() -> void:
	var t := TABLE_SCENE.instantiate()
	_world.add_child(t)
	_stylize(t, 0.0045)


var rival_kind := "tahur"
var _mixamo := false     # rigged in Mixamo with our own clips: one-hand plays, own timings
var _fist_reach := 0.11  # wrist to the middle of the closed hand
var _brute_light: SpotLight3D   # his skin is charcoal: a low warm light from the front keeps him readable
var _tail_light: SpotLight3D    # the Gila's tail, beside the chair


## Changes who sits across the table (see RIVALS): "tahur" (the cold card sharp, smokes)
## or one of the Mixamo-rigged rivals.
func set_rival(kind: String) -> void:
	if not RIVALS.has(kind) or kind == rival_kind:
		return
	rival_kind = kind
	_mixamo = kind != "tahur"
	_fist_reach = 0.06
	_gun_scale = 0.8 if kind == "gila" else 0.75   # Gila: 29 cm (it was 36, too big)
	if _rival != null:
		_world.remove_child(_rival)
		_rival.queue_free()
	_build_rival()
	if _brute_light != null:
		_brute_light.queue_free()
		_brute_light = null
	if _mixamo:
		_brute_light = SpotLight3D.new()
		_brute_light.light_color = Color("#ffd2a0")
		_brute_light.light_energy = 1.0 if kind == "gila" else 0.7
		_brute_light.spot_range = 2.6
		_brute_light.spot_angle = 24.0
		_brute_light.spot_angle_attenuation = 1.2
		_world.add_child(_brute_light)
		_brute_light.look_at_from_position(Vector3(0.15, 1.2, 0.9), Vector3(0.0, 1.0, -0.15))
	if _tail_light != null:
		_tail_light.queue_free()
		_tail_light = null
	if kind == "gila":
		# his tail rises beside the chair, out of the front light's cone: a narrow, dim
		# warm light just for it, so its silhouette reads in the dark
		_tail_light = SpotLight3D.new()
		_tail_light.light_color = Color("#ffc890")
		_tail_light.light_energy = 1.4
		_tail_light.spot_range = 2.4
		_tail_light.spot_angle = 17.0
		_tail_light.spot_angle_attenuation = 1.4
		_world.add_child(_tail_light)
		_tail_light.look_at_from_position(Vector3(-0.15, 1.3, 0.55), Vector3(-0.57, 0.78, -0.42))
	_build_glints()
	_build_lizard_eyes()
	var smokes := kind == "tahur"
	if smokes:
		fidgets = FIDGETS
	elif kind == "gila":
		# a predator: long stares, the tail doing the talking
		fidgets = ["tail_curl", "stare", "check", "impatient", "knuckles", "neck", "lean", "tail_curl", "stare"]
	else:
		fidgets = ["glasses", "check", "stare", "impatient", "knuckles", "neck", "lean", "glasses", "check"]
	if _smoke != null:
		_smoke.visible = smokes
		_smoke.emitting = smokes


var _tics: SkeletonModifier3D


func _build_rival() -> void:
	_rival = (RIVALS[rival_kind] as PackedScene).instantiate()
	_world.add_child(_rival)
	_stylize(_rival, 0.006)
	_skeleton = _rival.find_children("*", "Skeleton3D", true, false)[0]
	_anim = _rival.find_children("*", "AnimationPlayer", true, false)[0]
	var idle := _anim.get_animation(_anim_name("idle"))
	idle.loop_mode = Animation.LOOP_LINEAR
	_anim.animation_finished.connect(_on_anim_finished)
	_tics = preload("res://scripts/game/ui/rival_tics.gd").new()
	_skeleton.add_child(_tics)
	_anim.speed_scale = 1.0
	_play("idle", 0.0)


func _anim_name(clip: String) -> String:
	for n: String in _anim.get_animation_list():
		if n == clip or n.ends_with("/" + clip):
			return n
	return clip


func _card_node(face: Texture2D, back: Texture2D) -> Node3D:
	var root := Node3D.new()
	for side: int in [0, 1]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = CARD_SIZE
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_texture = face if side == 0 else back
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 1.0
		mi.material_override = m
		if side == 1:
			mi.rotation.y = PI
		mi.position.z = 0.0006 if side == 0 else -0.0006
		root.add_child(mi)
	return root


func _lying(card: Node3D) -> void:
	card.rotation = Vector3(-PI * 0.5, 0.0, 0.0)


func _build_cards() -> void:
	_pile_root = Node3D.new()
	_pile_root.position = PILE
	_world.add_child(_pile_root)
	_deck_root = Node3D.new()
	_deck_root.position = DECK
	_world.add_child(_deck_root)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.108
	_ring.mesh = torus
	_ring.position = PILE + Vector3(0, 0.001, 0)
	_ring.scale = Vector3(1, 0.05, 1)
	_world.add_child(_ring)
	_fan = Node3D.new()
	_world.add_child(_fan)
	_held = _card_node(CardViewScript.back_texture(), CardViewScript.back_texture())
	_held.visible = false
	_world.add_child(_held)
	_gun = _make_gun()
	_gun.visible = false
	_world.add_child(_gun)
	set_hand_count(5)


## The revolver (Tripo model, optimized in Blender: modelos_tripo/revolver/). Its origin
## is the middle of the palm on the grip, the barrel runs along -Z and the top is +Y;
## 0.365 m long, sized for the Gila's big hands (others use it at _gun_scale 0.75).
const REVOLVER := preload("res://assets/models/revolver.glb")
const GUN_MUZZLE := Vector3(0.0, 0.088, -0.33)
var _gun_scale := 0.75


func _make_gun() -> Node3D:
	var g := REVOLVER.instantiate() as Node3D
	_stylize(g, 0.003)
	return g


# ------------------------------------------------------------------ per frame
var _speed_target := 1.0
var _speed_wait := 0.0


func _update_tempo(delta: float) -> void:
	_speed_wait -= delta
	if _speed_wait <= 0.0:
		_speed_wait = _rng.randf_range(0.12, 0.45)
		var r := _rng.randf()
		if r < 0.16:
			_speed_target = _rng.randf_range(1.25, 1.45)  # a quicker beat
		elif r < 0.28:
			_speed_target = _rng.randf_range(0.5, 0.7)    # slows for a beat
		else:
			_speed_target = _rng.randf_range(0.92, 1.12)
	# eased, so a change of pace never shows up as a stutter
	_anim.speed_scale = lerpf(_anim.speed_scale, _speed_target, 1.0 - exp(-delta * 4.0))


func _process(delta: float) -> void:
	_dt = maxf(delta, 0.0001)
	_update_tempo(delta)
	_clip_time += delta * _anim.speed_scale
	_time += delta
	_place_props()
	_update_camera(delta)
	_update_lamp(delta)
	_update_wild(delta)
	_update_fx(delta)
	_update_glints(delta)
	_update_lizard_eyes(delta)
	if _smoke != null and _smoke.visible:
		var head := _skeleton.find_bone("head")
		var head_xf := _skeleton.global_transform * _skeleton.get_bone_global_pose(head)
		_smoke.global_position = (head_xf * _ember_local).origin
	if _current == "smoke" and not _puffed and _clip_time >= EVENTS["smoke"]["exhale"]:
		_puffed = true
		_puff()
	if _current == "idle":
		_fidget_wait -= delta
		if _fidget_wait <= 0.0:
			_fidget_wait = _rng.randf_range(5.0, 11.0)
			_play(fidgets[_rng.randi() % fidgets.size()])


func _bone_pos(bone: String) -> Vector3:
	var i := _skeleton.find_bone(bone)
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(i).origin


func _facing_camera(at: Vector3) -> Basis:
	var t := Transform3D.IDENTITY.looking_at(camera.global_position - at, Vector3.UP)
	return t.basis.rotated(t.basis.y, PI)  # card front away from the player: we see its back


## Middle of a closed fist: down the hand bone from the wrist (the brute's hands are big).
func _fist_center(bone: String) -> Vector3:
	var i := _skeleton.find_bone(bone)
	var xf := _skeleton.global_transform * _skeleton.get_bone_global_pose(i)
	return xf.origin + xf.basis.y.normalized() * _fist_reach


func _ev(clip: String, key: String) -> float:
	if _mixamo and EVENTS_MIXAMO.has(clip):
		return EVENTS_MIXAMO[clip][key]
	return EVENTS[clip][key]


## Which hand holds the card being played or drawn ("L" or "R").
var _held_side := "L"


## Where a hand with real fingers pinches a card: between the thumb tip and the index.
## Hands without finger bones fall back to the middle of the fist.
func _pinch(side: String) -> Vector3:
	if rival_kind == "gila":
		# long lizard fingers: the card is held between the very tips (measured in
		# Blender: thumb tip against the index tip, ~1 cm, right on the deck card)
		return (_bone_pos("thumb4." + side) + _bone_pos("index4." + side)) * 0.5
	if _skeleton.find_bone("index2." + side) >= 0:
		return (_bone_pos("thumb3." + side) + _bone_pos("index2." + side)) * 0.5
	return _fist_center("hand." + side)


## Inside a closed hand: between the fingers' middle joints and the thumb.
func _fist_grip(side: String) -> Vector3:
	var fingers := (_bone_pos("index2." + side) + _bone_pos("middle2." + side) + _bone_pos("ring2." + side) + _bone_pos("pinky2." + side)) * 0.25
	return fingers.lerp(_bone_pos("thumb3." + side), 0.35)


func _place_props() -> void:
	# fan of cards in the rival's left hand (screen left): we see the backs
	var fan_at := _bone_pos("hand.R") + Vector3(0, 0, 0.02)
	if _mixamo:
		# the fan comes out of the middle of the fist, its bottom hidden
		# behind the knuckles (so it reads as held, not stuck on)
		fan_at = _fist_center("hand.R") + Vector3(-0.03, 0.035, 0.0)
		if _skeleton.find_bone("index2.R") >= 0:
			# real fingers: the cards sit in the pinch between thumb tip and index,
			# a little behind the fingers so they wrap the bottom edge
			var pinch := _pinch("R")
			fan_at = pinch - (camera.global_position - pinch).normalized() * 0.008 - Vector3.UP * 0.02
		if rival_kind == "gila":
			# (8/11) held in the web between thumb and index: the cards' bottom sits
			# halfway between his thumb tip (his side of the cards) and his curled
			# fingers (our side), so the cards are really pinched between them
			# (gila_probe.py fan_web_at; it used to sit inside the closed fist)
			var web := (_bone_pos("index1.R") + _bone_pos("thumb2.R")) * 0.5
			var fing := (_bone_pos("index2.R") + _bone_pos("index3.R") + _bone_pos("middle2.R")) / 3.0
			var tc := (CAMERA_AT - web).normalized()
			fan_at = web + tc * ((fing + _bone_pos("thumb4.R")) * 0.5 - web).dot(tc)
	# the Mixamo rivals hold the fan tipped out to their side, away from the face
	_fan.global_transform = Transform3D(_facing_camera(fan_at).rotated(Vector3.FORWARD, -0.3 if _mixamo else 0.0), fan_at)
	var n := _fan.get_child_count()
	for i: int in range(n):
		var c := _fan.get_child(i) as Node3D
		var u := 0.0 if n == 1 else float(i) / (n - 1) - 0.5
		c.rotation = Vector3(0, 0, -u * 0.9)
		c.scale = Vector3.ONE * 0.8
		c.position = Vector3(0, 0, 0.0015 * i).rotated(Vector3.FORWARD, -u * 0.9) + Vector3(0, CARD_SIZE.y * (0.42 if _mixamo else 0.38), 0).rotated(Vector3.FORWARD, -u * 0.9)
	var hand := _bone_pos("hand." + _held_side)
	_hand_vel = _hand_vel.lerp((hand - _last_hand) / _dt, 1.0 - exp(-_dt * 14.0))
	_last_hand = hand
	_held.visible = _held_visible
	if _held_visible:
		_held.global_transform = _held_now()
	_gun.visible = _gun_mode != 0
	if _gun_mode == 1:
		var side := _held_side
		if rival_kind == "gila":
			# held for real: fixed in his hand (grip in the hollow of the fingers, index
			# on the trigger, thumb along the frame), so it never slides through the fist.
			# The clip aims the hand; measured in Blender (gila_probe.py)
			_gun.global_transform = _gun_grip(side)
			_flash.position = _gun.global_transform * GUN_MUZZLE
		elif _skeleton.find_bone("index1." + side) >= 0:
			# gripped like a real revolver: the barrel runs along the hand, out past the
			# knuckles, and the butt goes down into the closed fingers. It aims wherever
			# the hand aims (the clip points the hand at the player).
			var wrist := _bone_pos("hand." + side)
			var knuckles := (_bone_pos("index1." + side) + _bone_pos("pinky1." + side)) * 0.5
			var grip := wrist.lerp(knuckles, 0.75)
			# the wrist bends to aim: mostly at the player, a little along the hand
			var fwd := ((knuckles - wrist).normalized() * 0.3 + (camera.global_position - grip).normalized() * 0.7).normalized()
			# the hand is on its edge: the gun's top is the index side, the butt goes
			# down through the closed fingers
			var top := _bone_pos("index1." + side) - _bone_pos("pinky1." + side)
			var up := (top - fwd * top.dot(fwd)).normalized()
			grip += up * 0.03
			_gun.global_transform = Transform3D(Basis.looking_at(fwd, up).scaled(Vector3.ONE * _gun_scale), grip)
		else:
			var aim := Transform3D.IDENTITY.looking_at(camera.global_position - hand, Vector3.UP)
			_gun.global_transform = Transform3D(aim.basis.scaled(Vector3.ONE * _gun_scale), hand)
	elif _gun_mode == 2:
		var span: float = _ev("shoot", "twirl_end") - _ev("shoot", "twirl")
		var u := clampf((_clip_time - _ev("shoot", "twirl")) / span, 0.0, 1.0)
		var spin := (1.0 - pow(1.0 - u, 2.0)) * TAU * 2.0
		var b := Basis(Vector3.UP, PI * 0.5).rotated(Vector3.FORWARD, 0.0) * Basis(Vector3.RIGHT, spin)
		_gun.global_transform = Transform3D(b.scaled(Vector3.ONE * _gun_scale), hand)
	if not (_gun_mode == 1 and rival_kind == "gila"):
		_flash.position = hand + Vector3(0, 0.02, 0.15)


## The Gila's revolver, fixed in his hand. A frame built from the joints only
## (F: wrist to knuckles, S: toward the index, N = F x S), the same math as
## gila_probe.py in Blender; GILA_GUN_GRIP = (along F, along S, along N, pitch, roll).
const GILA_GUN_GRIP := [0.1171, 0.0797, 0.045, 0.0, 12.76]   # refit for _gun_scale 0.8


func _gun_grip(side: String) -> Transform3D:
	var wrist := _bone_pos("hand." + side)
	var i1 := _bone_pos("index1." + side)
	var p1 := _bone_pos("pinky1." + side)
	var f := ((i1 + p1) * 0.5 - wrist).normalized()
	var s := i1 - p1
	s = (s - f * s.dot(f)).normalized()
	var n := f.cross(s)
	var pitch := deg_to_rad(GILA_GUN_GRIP[3])
	var roll := deg_to_rad(GILA_GUN_GRIP[4])
	var fwd := (f * cos(pitch) + n * sin(pitch)).normalized()
	var up := (s - fwd * s.dot(fwd)).normalized().rotated(fwd, roll)
	var o := wrist + f * GILA_GUN_GRIP[0] + s * GILA_GUN_GRIP[1] + n * GILA_GUN_GRIP[2]
	return Transform3D(Basis.looking_at(fwd, up).scaled(Vector3.ONE * _gun_scale), o)


# ------------------------------------------------------------------ the card in the rival's hand
var _held_show := false          # true: he shows you its face
var _held_from := Transform3D()   # where the card was when he took it (fan or deck)
var _held_take := 1.0             # 0..1 from _held_from into his fingers
var _held_tuck := -1.0            # 0..1 from his fingers into the fan (-1: not tucking)


## Pinched between the fingers of his left hand: it sticks out past the fingers,
## follows the forearm and the wrist, and trails the hand a little when it moves.
func _held_pose() -> Transform3D:
	var hand := _bone_pos("hand." + _held_side)
	var along := (hand - _bone_pos("forearm." + _held_side)).normalized()
	var up := along.lerp(Vector3.UP, 0.45).normalized()
	var to_cam := (camera.global_position - hand).normalized()
	var z := to_cam if _held_show else -to_cam
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	var b := Basis(x, y, z)
	# air drag: the top of the card lags behind the hand's motion
	var v := _hand_vel.limit_length(1.5)
	b = b.rotated(x, clampf(-v.y * 0.22 + v.z * 0.12, -0.35, 0.35))
	b = b.rotated(z, clampf(v.x * 0.25, -0.3, 0.3))
	if _mixamo:
		# held up out of the fist: its lower part is inside his fingers
		if rival_kind == "gila":
			# (8/11) the card sits IN the pinch: its plane runs between the thumb tip and
			# the index tip (60 % the pinch axis, 40 % facing the camera so it still
			# reads) and it comes out of the fingers along their direction, the way a
			# pinched card really hangs (it used to stand up facing the camera above the
			# tips whatever the fingers did). Same math as gila_probe.py held().
			var s := _held_side
			var t4 := _bone_pos("thumb4." + s)
			var i4 := _bone_pos("index4." + s)
			var tips := (t4 + i4) * 0.5
			var front := -(camera.global_position - tips).normalized()
			if _held_show:
				front = -front
			var axis := (i4 - t4).normalized()
			if axis.dot(front) < 0.0:
				axis = -axis
			var gz := (axis * 0.6 + front * 0.4).normalized()
			var fdir := (i4 - _bone_pos("index2." + s)).normalized()
			var gy := fdir.lerp(Vector3.UP, 0.3)
			gy = (gy - gz * gy.dot(gz)).normalized()
			var gx := gy.cross(gz).normalized()
			var gb := Basis(gx, gy, gz)
			gb = gb.rotated(gx, clampf(-v.y * 0.15 + v.z * 0.08, -0.2, 0.2))
			return Transform3D(gb, tips + gy * CARD_SIZE.y * 0.38)
		# its bottom edge in the pinch, the rest standing out of the hand
		return Transform3D(b, _pinch(_held_side) + y * CARD_SIZE.y * 0.42 - to_cam * 0.006)
	return Transform3D(b, hand + along * 0.035 + y * CARD_SIZE.y * 0.28 + to_cam * 0.01)


func _held_now() -> Transform3D:
	var xf := _held_pose()
	if _held_take < 1.0:
		if _held_attach:
			# (8/11) stuck to the fingers from the moment they touch it: the card keeps
			# where it was relative to the hand and only settles into the pinch while
			# the hand moves on (it used to slide through the air into the fingers)
			xf = xf * _held_rel.interpolate_with(Transform3D.IDENTITY, _smooth(_held_take))
		else:
			xf = _held_from.interpolate_with(xf, _smooth(_held_take))
	if _placing:
		# laying it down: as the hand comes down the card turns face up and lies flat
		# on the wood under his finger tips (no flight to the pile: it is slid there)
		var k := _smooth((_clip_time - 22.0 / 30.0) / (9.0 / 30.0))
		if k > 0.0:
			var tips := (_bone_pos("thumb4.L") + _bone_pos("index4.L")) * 0.5
			var flat := Transform3D(_place_rest.basis, Vector3(tips.x, TABLE_TOP + 0.004, tips.z))
			xf = xf.interpolate_with(flat, k)
	if _held_tuck >= 0.0 and _fan.get_child_count() > 0:
		var slot := (_fan.get_child(_fan.get_child_count() - 1) as Node3D).global_transform
		xf = xf.interpolate_with(slot, _smooth(_held_tuck))
	return xf


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


## He takes a card: it slides out of where it was into his fingers.
var _held_attach := false        # the card rides on the fingers from the touch (fingered rigs)
var _held_rel := Transform3D.IDENTITY
var _placing := false            # laying the card flat on the table (play_free_place)
var _place_rest := Transform3D.IDENTITY


func _take_card(from: Transform3D, face: Texture2D, reveal: bool, dur: float) -> void:
	_held_from = from
	_held_show = reveal
	_set_held_face(face)
	_held_attach = rival_kind == "gila"
	if _held_attach:
		_held_rel = _held_pose().affine_inverse() * from
		dur = maxf(dur, 0.34)
	_held_take = 0.0
	_held_tuck = -1.0
	_held_visible = true
	_held.global_transform = from
	var t := create_tween()
	t.tween_property(self, "_held_take", 1.0, dur)


# ------------------------------------------------------------------ cards on the table
var _pile_pose := {}   # card instance id -> [yaw, offset]: each card keeps how it fell


func _pile_local(card: Card, slot: int) -> Transform3D:
	var id := card.get_instance_id()
	if not _pile_pose.has(id):
		_pile_pose[id] = [_rng.randf_range(-0.42, 0.42), Vector2(_rng.randf_range(-0.012, 0.012), _rng.randf_range(-0.01, 0.01))]
	var pose: Array = _pile_pose[id]
	var off: Vector2 = pose[1]
	var b := Basis(Vector3.UP, pose[0]) * Basis(Vector3.RIGHT, -PI * 0.5)
	return Transform3D(b, Vector3(off.x, 0.002 + slot * 0.0015, off.y))


## Exactly where a card that lands now will rest on the pile.
func pile_landing(card: Card) -> Transform3D:
	var slot := mini(_pile_root.get_child_count(), 2)
	return Transform3D(Basis.IDENTITY, PILE) * _pile_local(card, slot)


## Slides a card that lies on the table onto the pile, flat on the wood: pushed, it
## starts quick and drags to a stop (no flight).
func _slide_to_pile(node: Node3D, card: Card, start: Transform3D) -> void:
	var rest := pile_landing(card)
	var p0 := Vector3(start.origin.x, TABLE_TOP + 0.004, start.origin.z)
	var q0 := start.basis.orthonormalized().get_rotation_quaternion()
	var q1 := rest.basis.get_rotation_quaternion()
	var s0 := start.basis.get_scale()
	var dur := clampf(p0.distance_to(rest.origin) * 2.2, 0.14, 0.4)
	var t := create_tween()
	t.tween_method(func(u: float) -> void:
		var e := 1.0 - pow(1.0 - u, 2.6)   # pushed, then friction
		var p := p0.lerp(rest.origin, e)
		p.y = lerpf(p0.y, rest.origin.y, e)
		var b := Basis(q0.slerp(q1, e)).scaled_local(s0.lerp(Vector3.ONE, e))
		node.global_transform = Transform3D(b, p), 0.0, 1.0, dur)
	await t.finished
	node.global_transform = rest
	node.queue_free()
	land_fx(card)


## Flies a card from where it is to its place on the pile: it leaves with the
## speed of the hand that let it go, flips over in the air, lands and slides a bit.
func _fly_to_pile(node: Node3D, card: Card, start: Transform3D, launch: Vector3, duration: float, spin: float) -> void:
	var rest := pile_landing(card)
	var slide := Vector3(rest.origin.x - start.origin.x, 0.0, rest.origin.z - start.origin.z).normalized() * 0.012
	var touch := rest.origin - slide
	var p0 := start.origin
	var m0 := launch * duration
	var m1 := Vector3((touch - p0).x, -0.12, (touch - p0).z) * 0.7
	var s0 := start.basis.get_scale()
	var q0 := start.basis.orthonormalized().get_rotation_quaternion()
	var q1 := rest.basis.get_rotation_quaternion()
	var t := create_tween()
	t.tween_method(func(u: float) -> void:
		var u2 := u * u
		var u3 := u2 * u
		var p := p0 * (2 * u3 - 3 * u2 + 1) + m0 * (u3 - 2 * u2 + u) + touch * (-2 * u3 + 3 * u2) + m1 * (u3 - u2)
		var r := q0.slerp(q1, _smooth(u * 1.08))
		var b := Basis(r).rotated(Vector3.UP, spin * (1.0 - u) * u * 4.0)
		b = b.scaled_local(s0.lerp(Vector3.ONE, _smooth(u)))
		node.global_transform = Transform3D(b, p), 0.0, 1.0, duration)
	# it doesn't stop dead: a short slide on the wood
	t.tween_property(node, "global_position", rest.origin, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	node.global_transform = rest
	node.queue_free()
	land_fx(card)


func set_hand_count(count: int) -> void:
	_hand_count = clampi(count, 0, 8)
	if _fan == null:
		return
	while _fan.get_child_count() > _hand_count:
		var c := _fan.get_child(_fan.get_child_count() - 1)
		_fan.remove_child(c)
		c.queue_free()
	while _fan.get_child_count() < _hand_count:
		_fan.add_child(_card_node(CardViewScript.back_texture(), CardViewScript.back_texture()))


func show_piles(discard: Array, draw_count: int, active: Card.CardColor) -> void:
	for c in _pile_root.get_children():
		_pile_root.remove_child(c)
		c.queue_free()
	var shown := discard.slice(maxi(discard.size() - 3, 0))
	for i: int in range(shown.size()):
		var card := _card_node(CardViewScript.face_for(shown[i]), CardViewScript.back_texture())
		card.transform = _pile_local(shown[i], i)
		_pile_root.add_child(card)
	for c in _deck_root.get_children():
		_deck_root.remove_child(c)
		c.queue_free()
	var stack := clampi(int(ceil(draw_count / 8.0)), 0, 7)
	for i: int in range(stack):
		var card := _card_node(CardViewScript.back_texture(), CardViewScript.back_texture())
		_lying(card)
		card.rotation.y = 0.3 + (i % 2) * 0.03
		card.position = Vector3(0, 0.002 + i * 0.0035, 0)
		# face down: flip
		card.rotation.x = PI * 0.5
		_deck_root.add_child(card)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = ACTIVE_COLORS.get(active, Color("#c9954f"))
	ring_mat.emission_enabled = true
	ring_mat.emission = ring_mat.albedo_color
	ring_mat.emission_energy_multiplier = 1.5
	_ring.material_override = ring_mat


func pile_screen_pos() -> Vector2:
	return camera.unproject_position(PILE) * PIXEL_SHRINK


func deck_screen_pos() -> Vector2:
	return camera.unproject_position(DECK) * PIXEL_SHRINK


func head_screen_pos() -> Vector2:
	return camera.unproject_position(_bone_pos("head") + Vector3(0, 0.25, 0)) * PIXEL_SHRINK


## The card the rival lets go flies from his fingers to the pile.
func throw_to_pile(card: Card, duration := 0.32, arc := 0.08, spin := 0.0) -> void:
	var node := _card_node(CardViewScript.face_for(card), CardViewScript.back_texture())
	_world.add_child(node)
	var start := _held_now() if _held_visible else Transform3D(_facing_camera(_bone_pos("hand." + _held_side)), _bone_pos("hand." + _held_side))
	node.global_transform = start
	var launch := _hand_vel.limit_length(2.2) * 0.8 + Vector3(0, arc * 3.0, 0)
	await _fly_to_pile(node, card, start, launch, duration, spin)


## The player's card: appears at the pile, coming down from above as it lands.
func land_player_card(card: Card) -> void:
	var node := _card_node(CardViewScript.face_for(card), CardViewScript.back_texture())
	_world.add_child(node)
	var b := Basis(Vector3.RIGHT, -PI * 0.5).rotated(Vector3.UP, _rng.randf_range(-0.3, 0.3))
	var t := create_tween()
	t.tween_method(func(u: float) -> void:
		node.global_transform = Transform3D(b, PILE + Vector3(0, 0.012 + (1.0 - u) * 0.06, 0.05 * (1.0 - u))), 0.0, 1.0, 0.14)
	await t.finished
	node.queue_free()
	land_fx(card)


# ------------------------------------------------------------------ rival animation
func _play(clip: String, blend := BLEND) -> void:
	_puffed = false
	_current = clip
	_clip_time = 0.0
	_anim.play(_anim_name(clip), blend)


func _on_anim_finished(name: StringName) -> void:
	if String(name).ends_with("defeat"):
		return
	_play("idle", 0.45)


## Waits until the clip reaches `seconds` of ITS OWN time. (8/11: it used to wait real
## seconds, but the erratic tempo speeds the clip up and slows it down, so cards were
## taken and let go a few frames off the hand: they seemed to fly.)
func _at(seconds: float) -> void:
	var clip := _current
	while _clip_time < seconds and _current == clip:
		await get_tree().process_frame


func rival_play_card(card: Card) -> void:
	# no two plays alike: mostly a careless toss or a slow, deliberate placing;
	# only now and then he shows you the card first
	var r := _rng.randf()
	var clip := "play_toss" if r < 0.45 else ("play_place" if r < 0.85 else "play")
	_held_side = "R" if _mixamo else "L"
	if _mixamo:
		# sometimes the fan hand plays, sometimes the free hand plucks the card out
		if rival_kind == "gila":
			# (8/11) always the free hand: it plucks the card out of the fan and either
			# throws it or lays it on the table. The fan hand never plays on its own
			# (holding the fan and flicking a card with the same fingers read as inhuman)
			clip = "play_free" if r < 0.6 else "play_free_place"
			_held_side = "L"
		elif r < 0.4:
			clip = "play_free"
			_held_side = "L"
		else:
			clip = "play_toss" if r < 0.7 else "play_place"
	_play(clip)
	await _at(_ev(clip, "grab"))
	# he pulls the card out of the fan in his other hand
	var from := _held_pose()
	if _fan.get_child_count() > 0:
		from = (_fan.get_child(_fan.get_child_count() - 1) as Node3D).global_transform
	set_hand_count(_hand_count - 1)
	_take_card(from, CardViewScript.face_for(card), clip == "play", 0.1 if _mixamo else 0.2)
	if clip == "play_free_place":
		_place_rest = pile_landing(card)
		_placing = true
	await _at(_ev(clip, "release"))
	var start := _held_now()
	_held_visible = false
	_placing = false
	rival_event.emit("release")
	var node := _card_node(CardViewScript.face_for(card), CardViewScript.back_texture())
	_world.add_child(node)
	node.global_transform = start
	match clip:
		"play_free_place":
			# it already lies on the wood under his fingers: he pushes it onto the pile
			await _slide_to_pile(node, card, start)
		"play_free" when rival_kind == "gila":
			# a low flick off his fingers: short, quick, it lands and skids (no floating)
			await _fly_to_pile(node, card, start, _hand_vel.limit_length(1.6) * 0.7, 0.2, _rng.randf_range(-0.8, 0.8))
		"play_toss", "play_free":
			await _fly_to_pile(node, card, start, _hand_vel.limit_length(2.4) * 0.85 + Vector3(0, 0.12, 0), 0.34, _rng.randf_range(-1.4, 1.4))
		"play_place":
			# laid down: the hand is already over the pile, the card just settles
			await _fly_to_pile(node, card, start, _hand_vel.limit_length(0.6) * 0.5, 0.26, 0.0)
		_:
			await _fly_to_pile(node, card, start, _hand_vel.limit_length(2.0) * 0.8 + Vector3(0, 0.2, 0), 0.38, _rng.randf_range(-0.6, 0.6))


## He draws `count` cards: his free hand takes them off the deck (a small stack when
## there are several: a penalty, a fresh hand after emptying his) and slides them into
## the fan. Cards never just appear in his hand.
func rival_draw_card(count := 1) -> void:
	count = maxi(count, 1)
	_held_side = "L"
	_set_held_stack(count)
	_play("draw")
	await _at(_ev("draw", "grab"))
	# the top card comes off the deck, face down, into his fingers
	var from := _held_pose()
	if _deck_root.get_child_count() > 0:
		from = (_deck_root.get_child(_deck_root.get_child_count() - 1) as Node3D).global_transform
		from.origin.y += 0.003
	_take_card(from, CardViewScript.back_texture(), false, 0.12 if _mixamo else 0.22)
	await _at(_ev("draw", "tuck") - 0.18)
	# and slides into the fan
	var first := _fan.get_child_count()
	set_hand_count(_hand_count + count)
	var slots: Array[Node3D] = []
	for i: int in range(first, _fan.get_child_count()):
		var slot := _fan.get_child(i) as Node3D
		slot.visible = false
		slots.append(slot)
	_held_tuck = 0.0
	var t := create_tween()
	t.tween_property(self, "_held_tuck", 1.0, 0.22)
	await t.finished
	_held_visible = false
	_held_tuck = -1.0
	_set_held_stack(1)
	for slot in slots:
		if is_instance_valid(slot):
			slot.visible = true


## The card in his fingers becomes a small, slightly messy stack of `count` backs.
func _set_held_stack(count: int) -> void:
	for c in _held.get_children():
		if c.has_meta("stack"):
			_held.remove_child(c)
			c.queue_free()
	for i: int in range(1, mini(count, 8)):
		var extra := _card_node(CardViewScript.back_texture(), CardViewScript.back_texture())
		extra.set_meta("stack", true)
		extra.position = Vector3(_rng.randf_range(-0.003, 0.003), _rng.randf_range(-0.004, 0.002), 0.0016 * i)
		extra.rotation.z = _rng.randf_range(-0.05, 0.05)
		_held.add_child(extra)


func rival_hurt() -> void:
	_play("hurt", 0.08)
	_expression(1.7, 0.5)
	_grin_to(0.3, 0.6)


func rival_shoot() -> void:
	_held_side = "L"   # the gun is in his left hand
	_play("shoot")
	await _at(_ev("shoot", "draw"))
	_gun_mode = 1
	_expression(0.35, 1.6)
	_grin_to(1.45, 1.8)
	await _at(_ev("shoot", "fire"))
	_flash.light_energy = 6.0
	_lamp_kick = 1.0
	_gunshot()
	var t := create_tween()
	t.tween_property(_flash, "light_energy", 0.0, 0.18)
	rival_event.emit("fire")
	_twirl_later()


## The shot: a violent, close blast (sfx_disparo.py), never twice exactly the same.
const GUNSHOT := preload("res://assets/sfx/gunshot.wav")
var _shot_player: AudioStreamPlayer


func _gunshot() -> void:
	if _shot_player == null:
		_shot_player = AudioStreamPlayer.new()
		_shot_player.stream = GUNSHOT
		add_child(_shot_player)
	_shot_player.pitch_scale = _rng.randf_range(0.9, 1.05)
	_shot_player.volume_db = 0.0
	_shot_player.play()
	_muzzle_fx()


## The shot, seen: a star-shaped muzzle flash that lives for a few frames, sparks
## thrown forward, a burst of smoke out of the barrel and a thin thread of smoke that
## keeps rising from the muzzle while he holds the gun up.
func _muzzle_fx() -> void:
	if _gun == null:
		return
	var xf := _gun.global_transform
	var muzzle := xf * GUN_MUZZLE
	var fwd := -xf.basis.z.normalized()
	var root := Node3D.new()
	_world.add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), muzzle)
	# the flash: a camera-facing burst plus two long tongues of fire along the barrel
	var flash := Node3D.new()
	root.add_child(flash)
	var core := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.26, 0.26)
	core.mesh = q
	core.material_override = _fire_mat(true)
	flash.add_child(core)
	for k: int in range(2):
		var tongue := MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(0.09, 0.42)
		tongue.mesh = tq
		tongue.material_override = _fire_mat(false)
		# lies along the barrel (-Z), the two crossed at right angles
		tongue.rotation = Vector3(-PI * 0.5, 0.0, k * PI * 0.5)
		tongue.position = Vector3(0, 0, -0.17)
		flash.add_child(tongue)
	flash.scale = Vector3.ONE * 0.2
	var t := create_tween()
	t.tween_property(flash, "scale", Vector3.ONE * _rng.randf_range(1.0, 1.25), 0.025)
	t.tween_property(flash, "scale", Vector3.ONE * 0.05, 0.07).set_ease(Tween.EASE_IN)
	t.tween_callback(flash.queue_free)
	root.add_child(_shot_particles(true))
	root.add_child(_shot_particles(false))
	# the barrel keeps smoking while he holds the gun on you
	var wisp := _shot_wisp()
	_world.add_child(wisp)
	var follow := func() -> void:
		var left := 1.6
		while left > 0.0 and is_instance_valid(wisp) and _gun_mode == 1:
			wisp.global_position = _gun.global_transform * GUN_MUZZLE
			await get_tree().process_frame
			left -= get_process_delta_time()
		if is_instance_valid(wisp):
			wisp.emitting = false
			await get_tree().create_timer(2.5).timeout
			if is_instance_valid(wisp):
				wisp.queue_free()
	follow.call()
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(root):
		root.queue_free()


func _fire_mat(round_core: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if round_core:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5) if round_core else Vector2(0.5, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.98, 0.85, 1.0))
	g.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	g.add_point(0.35, Color(1.0, 0.75, 0.25, 0.95))
	tex.gradient = g
	m.albedo_texture = tex
	return m


## Sparks (true): hot bits thrown forward that fall. Smoke (false): a grey burst out of
## the barrel that spreads, slows and drifts up.
func _shot_particles(sparks: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0 if sparks else 0.85
	p.local_coords = false
	p.direction = Vector3(0, 0, -1)
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var fade := Gradient.new()
	if sparks:
		p.amount = 22
		p.lifetime = 0.35
		p.spread = 16.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.5
		p.gravity = Vector3(0, -4.0, 0)
		p.damping_min = 2.0
		p.damping_max = 4.0
		q.size = Vector2(0.014, 0.014)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fade.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
		fade.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	else:
		p.amount = 26
		p.lifetime = 2.2
		p.spread = 24.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.8
		p.damping_min = 2.5
		p.damping_max = 3.5
		p.gravity = Vector3(0, 0.12, 0)
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.5
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.25))
		grow.add_point(Vector2(1, 2.6))
		p.scale_amount_curve = grow
		q.size = Vector2(0.07, 0.07)
		fade.set_color(0, Color(0.85, 0.82, 0.78, 0.55))
		fade.set_color(1, Color(0.6, 0.58, 0.56, 0.0))
		var puff := GradientTexture2D.new()
		puff.fill = GradientTexture2D.FILL_RADIAL
		puff.fill_from = Vector2(0.5, 0.5)
		puff.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		puff.gradient = g
		m.albedo_texture = puff
	p.color_ramp = fade
	q.material = m
	p.mesh = q
	p.emitting = true
	return p


func _shot_wisp() -> CPUParticles3D:
	var p := _shot_particles(false)
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = 24
	p.lifetime = 2.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 8.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.1
	p.damping_min = 0.0
	p.damping_max = 0.05
	p.gravity = Vector3(0, 0.08, 0)
	(p.mesh as QuadMesh).size = Vector2(0.025, 0.025)
	var fade := Gradient.new()
	fade.set_color(0, Color(0.8, 0.78, 0.75, 0.0))
	fade.set_color(1, Color(0.7, 0.68, 0.66, 0.0))
	fade.add_point(0.1, Color(0.8, 0.78, 0.75, 0.35))
	p.color_ramp = fade
	return p


## What his attack is called on screen.
func attack_caption(damage: int) -> String:
	return "Rival shoots! -%d HP" % damage


func _twirl_later() -> void:
	await _at(_ev("shoot", "holster"))
	_gun_mode = 0


# ------------------------------------------------------------------ the doctor's glasses
## He has no eyes to act with: the reflection on his smoked lenses does it. A faint
## lamp reflection that slides across the glass now and then; a hard flash when he
## turns cold (squints: aims, taunts, wins); a flicker when he gets hurt (wide).
## Lens centers in the world with his idle pose at its first frame (measured in Blender).
const LENSES := [Vector3(-0.042, 1.107, 0.156), Vector3(0.041, 1.103, 0.16)]
const GLINT_SPOT := Vector3(-0.004, 0.018, 0.002)   # where the lamp catches the glass: high, toward the light
var _glints: Array[MeshInstance3D] = []
var _glint_root: Node3D
var _glint_local := Transform3D.IDENTITY
var _glint_sweep := -1.0
var _glint_wait := 4.0


func _build_glints() -> void:
	if _glint_root != null:
		_glint_root.get_parent().queue_free()
		_glint_root = null
	_glints.clear()
	if rival_kind != "matasanos":
		return
	var head := _skeleton.find_bone("head")
	# anchor them to the head as it is at the first frame of his idle
	_anim.play(_anim_name("idle"), 0.0)
	_anim.seek(0.0, true)
	_glint_local = (_skeleton.global_transform * _skeleton.get_bone_global_pose(head)).affine_inverse()
	# hung from the head bone itself, so they follow the head tics too
	var attach := BoneAttachment3D.new()
	attach.bone_name = "head"
	_skeleton.add_child(attach)
	_glint_root = Node3D.new()
	attach.add_child(_glint_root)
	_glint_root.transform = _glint_local
	for at: Vector3 in LENSES:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.013, 0.013)   # a soft, round reflection
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.95, 0.85, 0.0)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.9, 0.75)
		var dot := GradientTexture2D.new()
		dot.fill = GradientTexture2D.FILL_RADIAL
		dot.fill_from = Vector2(0.5, 0.5)
		dot.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		dot.gradient = g
		m.albedo_texture = dot
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = at + GLINT_SPOT
		_glint_root.add_child(mi)
		_glints.append(mi)


func _update_glints(delta: float) -> void:
	if _glint_root == null:
		return
	# now and then the lamp's reflection slides across the lenses
	_glint_wait -= delta
	if _glint_wait <= 0.0 and _glint_sweep < 0.0:
		_glint_sweep = 0.0
		_glint_wait = _rng.randf_range(3.0, 8.0)
	var sweep := 0.0
	var slide := 0.0
	if _glint_sweep >= 0.0:
		_glint_sweep += delta / 0.5
		sweep = sin(clampf(_glint_sweep, 0.0, 1.0) * PI)
		slide = lerpf(-0.012, 0.012, clampf(_glint_sweep, 0.0, 1.0))
		if _glint_sweep >= 1.0:
			_glint_sweep = -1.0
	var cold := clampf((1.0 - _eye_open) * 2.0, 0.0, 1.0)   # squint = he means it
	var shaken := clampf((_eye_open - 1.0) * 2.0, 0.0, 1.0)  # wide = it hurt
	var level := 0.18 + sweep * 0.6 + cold * 1.4
	if shaken > 0.0 and _rng.randf() < 0.5:
		level = _rng.randf_range(0.0, 0.3)
	for i: int in range(_glints.size()):
		var g := _glints[i]
		var m := g.material_override as StandardMaterial3D
		m.albedo_color.a = clampf(level, 0.0, 1.0)
		m.emission_energy_multiplier = level * 3.0
		g.position = LENSES[i] + GLINT_SPOT + Vector3(slide, -slide * 0.5, 0.0)
		# while the reflection slides across it stretches into a streak
		g.scale = Vector3(1.0 + sweep * 1.4 + cold * 0.4, 1.0 - sweep * 0.4 + cold * 0.4, 1.0)
		g.rotation.z = 0.5 * sweep


# ------------------------------------------------------------------ the Gila's eyes
## Two amber eyes that glow in the dark under his hat brim, with a reptile's slit
## pupil. They blink now and then (a slow lizard blink), narrow to slits when he
## means it (aims, taunts), go wide and flicker when he is hurt, and die out when
## he loses. Each throws a faint warm light on his snout and the brim.
## Eye centers in the world with his idle pose at its first frame (measured in Blender).
const GILA_EYES := [Vector3(-0.082, 1.2345, 0.0546), Vector3(0.118, 1.2369, 0.046)]
const GILA_LOOK := Vector3(0.034, 0.41, 0.911)    # where his snout points in that pose
const GILA_UP := Vector3(-0.029, 0.912, -0.409)
var _lizard_root: Node3D
var _lizard_eyes: Array[Node3D] = []
var _lizard_lights: Array[OmniLight3D] = []
var _lizard_mat: StandardMaterial3D
var _lizard_blink := 3.0


func _build_lizard_eyes() -> void:
	if _lizard_root != null:
		_lizard_root.get_parent().queue_free()
		_lizard_root = null
	_lizard_eyes.clear()
	_lizard_lights.clear()
	if rival_kind != "gila":
		return
	var head := _skeleton.find_bone("head")
	_anim.play(_anim_name("idle"), 0.0)
	_anim.seek(0.0, true)
	var attach := BoneAttachment3D.new()
	attach.bone_name = "head"
	_skeleton.add_child(attach)
	_lizard_root = Node3D.new()
	attach.add_child(_lizard_root)
	_lizard_root.transform = (_skeleton.global_transform * _skeleton.get_bone_global_pose(head)).affine_inverse()
	_lizard_mat = StandardMaterial3D.new()
	_lizard_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lizard_mat.albedo_color = Color("#ffc23a")
	_lizard_mat.emission_enabled = true
	_lizard_mat.emission = Color("#ff9a1c")
	_lizard_mat.emission_energy_multiplier = 5.0
	var slit := StandardMaterial3D.new()
	slit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slit.albedo_color = Color("#120604")
	var look := GILA_LOOK.normalized()
	var up := GILA_UP.normalized()
	for i: int in range(GILA_EYES.size()):
		var side := -1.0 if i == 0 else 1.0
		var eye := Node3D.new()
		# each eye looks forward and a little out to its own side, like a lizard's
		var fwd := (look + up.cross(look).normalized() * side * -0.35).normalized()
		eye.transform = Transform3D(Basis.looking_at(fwd, up), GILA_EYES[i] + fwd * 0.004)
		_lizard_root.add_child(eye)
		var ball := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.017
		s.height = 0.026
		s.radial_segments = 12
		s.rings = 6
		ball.mesh = s
		ball.material_override = _lizard_mat
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.scale = Vector3(1.25, 1.0, 0.7)   # an almond, wider than tall
		eye.add_child(ball)
		var pupil := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.0045, 0.022, 0.002)
		pupil.mesh = b
		pupil.material_override = slit
		pupil.position = Vector3(0, 0, -0.0112)   # on the front of the eye (-Z looks forward)
		pupil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.add_child(pupil)
		_lizard_eyes.append(eye)
		var glow := OmniLight3D.new()
		glow.light_color = Color("#ff9a2a")
		glow.light_energy = 0.35
		glow.omni_range = 0.22
		glow.shadow_enabled = false
		glow.position = Vector3(0, 0.0, -0.03)
		eye.add_child(glow)
		_lizard_lights.append(glow)


func _update_lizard_eyes(delta: float) -> void:
	if _lizard_root == null:
		return
	# a slow lizard blink: the lid comes down, holds a beat, lifts
	_lizard_blink -= delta
	var lid := 1.0
	if _lizard_blink < 0.0:
		var u := -_lizard_blink
		lid = clampf(absf(u - 0.12) / 0.12, 0.04, 1.0) if u < 0.24 else 1.0
		if u > 0.24:
			_lizard_blink = _rng.randf_range(2.5, 7.0)
	var cold := clampf((1.0 - _eye_open) * 2.0, 0.0, 1.0)     # squint = he means it
	var shaken := clampf((_eye_open - 1.0) * 2.0, 0.0, 1.0)   # wide = it hurt
	var open := clampf(_eye_open, 0.0, 1.4)
	var energy := 5.0 + cold * 4.0
	if shaken > 0.0 and _rng.randf() < 0.45:
		energy = _rng.randf_range(0.6, 2.5)    # the glow stutters
	if _eye_open <= 0.05:
		energy = 0.0                           # beaten: the light goes out
	_lizard_mat.emission_energy_multiplier = lerpf(_lizard_mat.emission_energy_multiplier, energy, 1.0 - exp(-delta * 18.0))
	for i: int in range(_lizard_eyes.size()):
		var eye := _lizard_eyes[i]
		# narrowed: the lid closes to a slit; wide: a little rounder
		var h := maxf(lid * lerpf(1.0, 0.35, cold) * (1.0 + shaken * 0.25) * minf(open * 2.0, 1.0), 0.04)
		eye.scale = Vector3(1.0 + shaken * 0.15, h, 1.0)
		_lizard_lights[i].light_energy = 0.35 * clampf(_lizard_mat.emission_energy_multiplier / 5.0, 0.0, 1.6) * h


func rival_taunt() -> void:
	_play("taunt")
	_expression(0.4, 1.8)
	_grin_to(1.5, 2.0)


func rival_defeat() -> void:
	_play("defeat", 0.15)
	var t := create_tween()
	t.tween_property(self, "_eye_open", 0.0, 0.8)
	t.parallel().tween_property(self, "_grin", 0.0, 0.8)


func rival_settle() -> void:
	while _current != "idle":
		await get_tree().process_frame


func rival_reset() -> void:
	wild_clear()
	hidden_hand_index = -1
	_eye_open = 1.0
	_grin = 1.0
	_held_visible = false
	_held_tuck = -1.0
	_held_take = 1.0
	_placing = false
	_hidden_ids.clear()
	if _player_held != null and is_instance_valid(_player_held):
		_player_held.queue_free()
	_player_held = null
	_gun_mode = 0
	_play("idle", 0.0)


# ------------------------------------------------------------------ cigar smoke
func _build_smoke() -> void:
	# where the ember sits (from the Blender model), kept in the head bone's space
	var head := _skeleton.find_bone("head")
	var ember_model := Vector3(0.078, 1.011, -0.044)
	var rest := _skeleton.get_bone_global_rest(head)
	# model positions are world-space; bones live in the skeleton's own space
	_ember_local = Transform3D(Basis.IDENTITY, rest.affine_inverse() * (_skeleton.global_transform.affine_inverse() * ember_model))
	_smoke = GPUParticles3D.new()
	_smoke.amount = 70
	_smoke.lifetime = 3.6
	_smoke.local_coords = false
	var pm := ParticleProcessMaterial.new()
	# a thin thread: leaves the cigar forward and to the side, slips out past the
	# edge of the brim, and only then rises and curls (it never meets the hat)
	pm.direction = Vector3(0.55, 0.15, 0.82)
	pm.spread = 6.0
	pm.initial_velocity_min = 0.07
	pm.initial_velocity_max = 0.09
	pm.damping_min = 0.05
	pm.damping_max = 0.08
	pm.gravity = Vector3(0.0, 0.06, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.12
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.scale_min = 0.8
	pm.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.18))
	grow.add_point(Vector2(1, 1.6))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.82, 0.78, 0.0))
	fade.set_color(1, Color(0.85, 0.82, 0.78, 0.0))
	fade.add_point(0.08, Color(0.82, 0.8, 0.77, 0.38))
	fade.add_point(0.6, Color(0.74, 0.72, 0.7, 0.14))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	_smoke.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = g
	sm.albedo_texture = puff
	quad.material = sm
	_smoke.draw_pass_1 = quad
	_world.add_child(_smoke)


# ------------------------------------------------------------------ camera director
var _cam_pos := CAMERA_AT
var _cam_look := LOOK_AT
var _cam_fov := 50.0
var _want_pos := CAMERA_AT
var _want_look := LOOK_AT
var _want_fov := 50.0
var _focus_token := 0


func _update_camera(delta: float) -> void:
	# Everything eases toward its target with the same slow, heavy damping, like
	# the player turning their head; a faint handheld drift keeps the shot alive.
	var k := 1.0 - exp(-delta * 2.4)
	_cam_pos = _cam_pos.lerp(_want_pos, k)
	_cam_look = _cam_look.lerp(_want_look, k)
	_cam_fov = lerpf(_cam_fov, _want_fov, k)
	var drift := Vector3(
		sin(_time * 0.31) * 0.006 + sin(_time * 1.13 + 2.0) * 0.0015,
		sin(_time * 0.47 + 1.0) * 0.004 + sin(_time * 1.7) * 0.001, 0.0)
	var pos := _cam_pos + drift
	if _shake > 0.0:
		pos += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake * 0.016
		_shake = maxf(_shake - delta * 2.5, 0.0)
	camera.fov = _cam_fov
	camera.look_at_from_position(pos, _cam_look + drift * 0.3)
	camera.rotate_object_local(Vector3.FORWARD, _roll + sin(_time * 0.41) * 0.006)


## Turns to look at something, holds, then settles back on the table.
func focus(pos: Vector3, look: Vector3, fov: float, hold: float) -> void:
	_focus_token += 1
	var token := _focus_token
	_want_pos = pos
	_want_look = look
	_want_fov = fov
	await get_tree().create_timer(hold + 0.6).timeout
	if token == _focus_token:
		_want_pos = CAMERA_AT
		_want_look = LOOK_AT
		_want_fov = 50.0


func focus_pile(hold := 1.0) -> void:
	focus(CAMERA_AT + Vector3(0.0, -0.03, -0.08), LOOK_AT.lerp(PILE, 0.5), 44.0, hold)


func focus_rival(hold := 1.2) -> void:
	focus(CAMERA_AT + Vector3(0.01, -0.03, -0.08), LOOK_AT.lerp(Vector3(0.0, 0.98, -0.2), 0.6), 44.0, hold)


func shake(strength := 1.0) -> void:
	_shake = maxf(_shake, strength)


func _hanging_lamp(at: Vector3) -> Node3D:
	var lamp := Node3D.new()
	lamp.position = at
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#2a2622")
	metal.roughness = 0.6
	var parts := []
	var shade := CylinderMesh.new()
	shade.top_radius = 0.035
	shade.bottom_radius = 0.17
	shade.height = 0.13
	parts.append([shade, Vector3(0, 0.07, 0), metal])
	var cord := CylinderMesh.new()
	cord.top_radius = 0.006
	cord.bottom_radius = 0.006
	cord.height = 1.4
	parts.append([cord, Vector3(0, 0.83, 0), metal])
	var bulb := SphereMesh.new()
	bulb.radius = 0.035
	bulb.height = 0.07
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("#fff2c8")
	glow.emission_enabled = true
	glow.emission = Color("#ffd890")
	glow.emission_energy_multiplier = 5.0
	parts.append([bulb, Vector3(0, 0.0, 0), glow])
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.position = p[1]
		mi.material_override = p[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(mi)
	return lamp


## A card hits the pile: a ring of its color spreads over the table and dust puffs up.
func land_fx(card: Card) -> void:
	var col: Color = ACTIVE_COLORS.get(card.color, Color("#e2b44a"))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.06
	torus.outer_radius = 0.075
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.0
	ring.material_override = m
	ring.position = PILE + Vector3(0, 0.004, 0)
	ring.scale = Vector3(1, 0.06, 1)
	_world.add_child(ring)
	var t := create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(3.2, 0.06, 3.2), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color:a", 0.0, 0.45)
	t.chain().tween_callback(ring.queue_free)
	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.amount = 18
	dust.lifetime = 0.7
	dust.explosiveness = 0.95
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 80.0
	dust.initial_velocity_min = 0.12
	dust.initial_velocity_max = 0.3
	dust.gravity = Vector3(0, -0.15, 0)
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.0
	var dm := QuadMesh.new()
	dm.size = Vector2(0.018, 0.018)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dmat.albedo_color = Color(0.95, 0.85, 0.65, 0.6)
	dm.material = dmat
	dust.mesh = dm
	dust.position = PILE + Vector3(0, 0.01, 0)
	_world.add_child(dust)
	dust.emitting = true
	get_tree().create_timer(1.2).timeout.connect(dust.queue_free)
	shake(0.35)


# ------------------------------------------------------------------ eyes
func _build_eyes() -> void:
	var head := _skeleton.find_bone("head")
	var rest := _skeleton.get_bone_global_rest(head)
	var eye_at := _skeleton.global_transform.affine_inverse() * Vector3(0.0, 1.06, -0.114)
	_eye_local = rest.affine_inverse() * Transform3D(Basis.IDENTITY, eye_at)
	_eyes = Node3D.new()
	_world.add_child(_eyes)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color("#fff1d0")
	glow.emission_enabled = true
	glow.emission = Color("#ffd9a0")
	glow.emission_energy_multiplier = 6.0
	# eyes: sharp wedges, inner corners pulled down = a permanent scowl
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array([Vector2(0.044, 0.012), Vector2(0.012, -0.004), Vector2(0.03, -0.012)])
		var eye := _flat_mesh(pts, side, glow)
		eye.name = "Eye"
		_eyes.add_child(eye)
	# grin: a wide zigzag of teeth under the eyes
	var grin := Node3D.new()
	grin.name = "Grin"
	grin.position = Vector3(-0.004, -0.046, 0.004)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var n := 9
	for i: int in range(n + 1):
		var x := lerpf(-0.052, 0.046, float(i) / n)
		var y := 0.012 * pow(x / 0.05, 2.0) - 0.002
		top.append(Vector2(x, y))
		bottom.append(Vector2(x, y - (0.016 if i % 2 == 0 else 0.007) * (1.0 - pow(x / 0.055, 2.0) * 0.5)))
	var verts := PackedVector3Array()
	for i: int in range(n):
		for tri: Array in [[top[i], bottom[i], top[i + 1]], [top[i + 1], bottom[i], bottom[i + 1]]]:
			for v: Vector2 in tri:
				verts.append(Vector3(v.x, v.y, 0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = glow
	grin.add_child(mi)
	_eyes.add_child(grin)


func _flat_mesh(pts: PackedVector2Array, mirror: float, mat: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	for v: Vector2 in pts:
		verts.append(Vector3(v.x * mirror, v.y, 0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _update_eyes(delta: float) -> void:
	if _eyes == null:
		return
	var head := _skeleton.find_bone("head")
	var t := _skeleton.global_transform * _skeleton.get_bone_global_pose(head) * _eye_local
	_eyes.global_transform = Transform3D(t.basis.orthonormalized(), t.origin)
	_blink_wait -= delta
	var blink := 1.0
	if _blink_wait < 0.0:
		blink = clampf(absf(_blink_wait + 0.07) / 0.07, 0.05, 1.0)
		if _blink_wait < -0.14:
			_blink_wait = _rng.randf_range(2.0, 5.5)
	for part in _eyes.get_children():
		var node := part as Node3D
		if node.name == "Grin":
			node.scale = Vector3(lerpf(0.7, 1.2, clampf(_grin, 0.0, 1.5)), maxf(_grin, 0.02), 1.0)
		else:
			node.scale = Vector3(1.0 + maxf(_eye_open - 1.0, 0.0) * 0.3, maxf(_eye_open * blink, 0.02), 1.0)


## Holds an eye shape for a while and eases back to normal.
func _expression(open: float, hold: float) -> void:
	var t := create_tween()
	t.tween_property(self, "_eye_open", open, 0.12)
	t.tween_interval(hold)
	t.tween_property(self, "_eye_open", 1.0, 0.35)


func _grin_to(value: float, hold: float) -> void:
	var t := create_tween()
	t.tween_property(self, "_grin", value, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(hold)
	t.tween_property(self, "_grin", 1.0, 0.4)


# ------------------------------------------------------------------ player's own hands (3D)
const HAND_DEPTH := 0.34     # how far in front of the camera the held cards float
const FIST_DEPTH := 0.31     # fists are a bit closer, so they sit in front of the cards
var _hand_root: Node3D
var _hand_meshes := {}      # card instance id -> MeshInstance3D shown for that card
var _hand_xf := {}          # card instance id -> its current (smoothed) transform
var _spawn_from := {}       # card instance id -> where a card that joins the hand comes from
var _hidden_ids := {}       # cards of the hand that are being carried somewhere else
var _player_held: Node3D    # the card pinched by the player's right fist
var _held_follow := 0.0     # 0..1 from where it was picked up into the fist
var _held_pick := Transform3D()
var _held_flip := 1.0       # 0 back to the player, 1 face to the player
var _held_scale := 1.0      # the hand is drawn small and close: carried cards shrink to match
var _fist_r := Vector3.ZERO
var _fist_vel := Vector3.ZERO
var _hand_card_h := 0.04
var _arm_mat: StandardMaterial3D
var _arm_parts := {}


func _build_player_hands() -> void:
	_hand_root = Node3D.new()
	_world.add_child(_hand_root)
	_arm_mat = StandardMaterial3D.new()
	_arm_mat.albedo_color = Color("#2a2422")
	_arm_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_arm_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for side: String in ["L", "R"]:
		for part: String in ["upper", "fore", "thumb"]:
			var mi := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 1.0
			c.bottom_radius = 1.0
			c.height = 1.0
			c.radial_segments = 10
			mi.mesh = c
			mi.material_override = _arm_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_hand_root.add_child(mi)
			_arm_parts[side + part] = mi
		for joint: String in ["elbow", "fist", "knuckle"]:
			var mi := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 1.0
			sph.height = 2.0
			sph.radial_segments = 12
			sph.rings = 6
			mi.mesh = sph
			mi.material_override = _arm_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_hand_root.add_child(mi)
			_arm_parts[side + joint] = mi


func _limb(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var y := b - a
	var x := y.cross(camera.global_basis.z)
	if x.length() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized() * r
	var z := x.cross(y).normalized() * r
	mi.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _ball(mi: MeshInstance3D, at: Vector3, r: Vector3) -> void:
	mi.global_transform = Transform3D(camera.global_basis * Basis.from_scale(r), at)


func _to_vp(local_pos: Vector2) -> Vector2:
	return local_pos / float(PIXEL_SHRINK)


## Called every frame by the table: mirrors the (invisible) card buttons as 3D cards
## held in front of the camera, and puts the player's stickman fists on them.
## Each card eases toward its place, so the fan closes and opens smoothly.
func update_player_hand(buttons: Array, grip_l: Vector2, grip_r: Vector2) -> void:
	if _hand_root == null:
		_build_player_hands()
	var k := 1.0 - exp(-get_process_delta_time() * 16.0)
	var to_local := get_global_transform().affine_inverse()
	var seen := {}
	for i: int in range(buttons.size()):
		var b := buttons[i] as Button
		var card: Card = b.get_meta("card", null)
		var id: int = card.get_instance_id() if card != null else -1 - i
		seen[id] = true
		var xf := to_local * b.get_global_transform()
		var depth := HAND_DEPTH + i * 0.0015
		var tl := camera.project_position(_to_vp(xf * Vector2.ZERO), depth)
		var tr := camera.project_position(_to_vp(xf * Vector2(b.size.x, 0)), depth)
		var bl := camera.project_position(_to_vp(xf * Vector2(0, b.size.y)), depth)
		var x_axis := tr - tl
		var y_axis := tl - bl
		var z_axis := x_axis.cross(y_axis).normalized() * 0.001
		var target := Transform3D(Basis(x_axis, y_axis, z_axis), (tr + bl) * 0.5)
		_hand_card_h = y_axis.length()
		if not _hand_meshes.has(id):
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			mi.mesh = q
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_hand_root.add_child(mi)
			_hand_meshes[id] = mi
			_hand_xf[id] = _spawn_from.get(id, target)
			_spawn_from.erase(id)
		var now: Transform3D = (_hand_xf[id] as Transform3D).interpolate_with(target, k)
		_hand_xf[id] = now
		var mesh := _hand_meshes[id] as MeshInstance3D
		mesh.visible = i != hidden_hand_index and not _hidden_ids.has(id)
		mesh.global_transform = now
		var m := mesh.material_override as StandardMaterial3D
		m.albedo_texture = b.icon
		# the lamp barely reaches the player's side of the table
		var lit := 0.72 if not b.disabled else 0.38
		var want := Color(lit, lit * 0.94, lit * 0.86)
		m.albedo_color = m.albedo_color.lerp(want, k) if m.albedo_color.a > 0.0 and m.albedo_color != Color.WHITE else want
	for id: int in _hand_meshes.keys():
		if not seen.has(id):
			(_hand_meshes[id] as Node).queue_free()
			_hand_meshes.erase(id)
			_hand_xf.erase(id)
	for side: String in ["L", "R"]:
		var sgn := -1.0 if side == "L" else 1.0
		var grip := grip_l if side == "L" else grip_r
		var vp_size := Vector2(viewport.size)
		var fist := camera.project_position(_to_vp(grip), FIST_DEPTH)
		if side == "R":
			_fist_vel = _fist_vel.lerp((fist - _fist_r) / maxf(get_process_delta_time(), 0.0001), 1.0 - exp(-get_process_delta_time() * 18.0))
			_fist_r = fist
		var shoulder := camera.project_position(Vector2(vp_size.x * (0.5 + 0.3 * sgn), vp_size.y * 1.35), 0.5)
		var elbow := shoulder.lerp(fist, 0.55) + camera.global_basis.x * sgn * 0.05 - camera.global_basis.y * 0.03
		_limb(_arm_parts[side + "upper"], shoulder, elbow, 0.013)
		_limb(_arm_parts[side + "fore"], elbow, fist, 0.0115)
		_ball(_arm_parts[side + "elbow"], elbow, Vector3.ONE * 0.013)
		_ball(_arm_parts[side + "fist"], fist, Vector3(0.0145, 0.016, 0.012))
		# thumb pressed over the card edge, pointing inward
		var thumb_tip := fist + camera.global_basis.y * 0.014 - camera.global_basis.x * sgn * 0.009 + camera.global_basis.z * 0.004
		_limb(_arm_parts[side + "thumb"], fist + camera.global_basis.y * 0.004, thumb_tip, 0.0048)
		_ball(_arm_parts[side + "knuckle"], thumb_tip, Vector3.ONE * 0.005)
	_update_player_held()


## Where a card pinched by the right fist sits: just above the fist, facing the
## player, and leaning with the fist's motion (it drags through the air).
func _fist_card_pose() -> Transform3D:
	var cb := camera.global_basis
	var v := cb.inverse() * _fist_vel.limit_length(1.2)
	var b := cb * Basis(Vector3.UP, PI * (1.0 - _held_flip))
	b = b.rotated(cb.z, clampf(-v.x * 0.5, -0.4, 0.4)).rotated(cb.x, clampf(v.y * 0.4 - 0.12, -0.45, 0.3))
	var s := _held_scale
	return Transform3D(b.scaled_local(Vector3.ONE * s), _fist_r + cb.y * CARD_SIZE.y * s * 0.36 - cb.z * 0.004)


func _update_player_held() -> void:
	if _player_held == null or not is_instance_valid(_player_held):
		return
	if _held_follow <= 0.0:
		_player_held.global_transform = _held_pick
		return
	_player_held.global_transform = _held_pick.interpolate_with(_fist_card_pose(), _smooth(_held_follow))


func _hand_mesh_to_card(xf: Transform3D) -> Transform3D:
	# hand meshes are unit quads scaled to the card; card nodes are CARD_SIZE quads
	var x := xf.basis.x / CARD_SIZE.x
	var y := xf.basis.y / CARD_SIZE.y
	var z := xf.basis.z.normalized() * y.length()
	return Transform3D(Basis(x, y, z), xf.origin)


func _card_to_hand_mesh(xf: Transform3D) -> Transform3D:
	var x := xf.basis.x * CARD_SIZE.x
	var y := xf.basis.y * CARD_SIZE.y
	return Transform3D(Basis(x, y, xf.basis.z.normalized() * 0.001), xf.origin)


func _new_player_card(card: Card) -> Node3D:
	if _player_held != null and is_instance_valid(_player_held):
		_player_held.queue_free()
	_player_held = _card_node(CardViewScript.face_for(card), CardViewScript.back_texture())
	_unshade(_player_held, Color(0.72, 0.68, 0.62))
	_world.add_child(_player_held)
	return _player_held


func holding_wild() -> bool:
	return _wild_card != null and is_instance_valid(_wild_card)


## Keeps a card of the hand out of sight (it is on its way there).
func hide_hand_card(card: Card) -> void:
	_hidden_ids[card.get_instance_id()] = true


## The card the player is about to play stays exactly where it was in the hand,
## until the fist takes it.
func player_pick(card: Card) -> void:
	var id := card.get_instance_id()
	var node := _new_player_card(card)
	var at := camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.06, -HAND_DEPTH))
	if _hand_xf.has(id):
		at = _hand_mesh_to_card(_hand_xf[id])
	node.global_transform = at
	_held_pick = at
	_held_follow = 0.0
	_held_flip = 1.0
	_held_scale = at.basis.y.length()


## The fist closes on the picked card: from now on it travels with the fist.
func player_attach(dur := 0.12) -> void:
	if _player_held == null:
		return
	var t := create_tween()
	t.tween_property(self, "_held_follow", 1.0, dur)


## Draw: the fist (already over the deck) takes the top card, face down.
func player_grab_deck(card: Card) -> void:
	_hidden_ids[card.get_instance_id()] = true
	var node := _new_player_card(card)
	var at := Transform3D(Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, PI * 0.5), DECK + Vector3(0, 0.03, 0))
	if _deck_root.get_child_count() > 0:
		at = (_deck_root.get_child(_deck_root.get_child_count() - 1) as Node3D).global_transform
		at.origin.y += 0.003
	node.global_transform = at
	_held_pick = at
	_held_follow = 0.0
	_held_flip = 0.0
	_held_scale = _hand_card_h / CARD_SIZE.y
	var t := create_tween()
	t.tween_property(self, "_held_follow", 1.0, 0.24)


## ...brings it back to the hand, turning it over on the way, and it joins the fan.
func player_bring_to_hand(card: Card, dur: float) -> void:
	var t := create_tween()
	t.tween_interval(dur * 0.2)
	t.tween_property(self, "_held_flip", 1.0, dur * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(dur).timeout
	var id := card.get_instance_id()
	if _player_held != null and is_instance_valid(_player_held):
		var xf := _card_to_hand_mesh(_player_held.global_transform)
		if _hand_xf.has(id):
			_hand_xf[id] = xf
		else:
			_spawn_from[id] = xf
		_player_held.queue_free()
	_player_held = null
	_hidden_ids.erase(id)


# ------------------------------------------------------------------ mood: lamp, tics, "it went bad"
var _lamp_pivot: Node3D
var _lamp_light: SpotLight3D
var _bulb_mat: StandardMaterial3D
var _flicker_wait := 5.0
var _flicker_left := 0.0
var _lamp_kick := 0.0
var _roll := 0.0
var _danger := 0.0          # 0 healthy .. 1 nearly dead: the image stays sick
var _fx := {"aberration": 0.0, "desaturate": 0.0, "flash": 0.0, "blackout": 0.0, "wobble": 0.0}
# rival tics: a slow wander plus sudden jerks that are held, then let go
var _tic := Vector3.ZERO     # head pitch, yaw, roll offsets (radians)
var _tic_target := Vector3.ZERO
var _tic_wait := 3.0
var _tic_hold := 0.0
var _spine_tic := 0.0


func _build_lamp() -> void:
	# pivot at the ceiling: the lamp hangs from a long cord and sways
	_lamp_pivot = Node3D.new()
	_lamp_pivot.position = Vector3(0.0, 2.98, 0.5)
	_world.add_child(_lamp_pivot)
	var lamp := _hanging_lamp(Vector3(0.0, -1.53, 0.0))
	_lamp_pivot.add_child(lamp)
	for mi in lamp.get_children():
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m != null and m.emission_enabled:
			_bulb_mat = m
	_lamp_light = SpotLight3D.new()
	_lamp_light.light_color = Color("#fff3e0")
	_lamp_light.light_energy = 2.3
	_lamp_light.spot_range = 3.4
	_lamp_light.spot_angle = 34.0
	_lamp_light.spot_angle_attenuation = 0.6
	_lamp_light.shadow_enabled = true
	_lamp_light.light_volumetric_fog_energy = 1.2
	_lamp_light.position = Vector3(0.0, -1.56, 0.0)
	_lamp_light.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_lamp_pivot.add_child(_lamp_light)


func _update_lamp(delta: float) -> void:
	if _lamp_pivot == null:
		return
	# slow, uneven sway; a kick (gunshot) makes it swing harder for a while
	_lamp_kick = maxf(_lamp_kick - delta * 0.25, 0.0)
	var amp := 0.035 + _lamp_kick * 0.12
	_lamp_pivot.rotation = Vector3(sin(_time * 0.71) * amp * 0.6, 0.0, sin(_time * 0.93 + 0.4) * amp)
	# every few seconds the bulb fails: a burst of drops, sometimes a full blackout
	var level := 1.0 - 0.04 * sin(_time * 37.0) * sin(_time * 3.1)
	_flicker_wait -= delta
	if _flicker_wait <= 0.0:
		_flicker_left = _rng.randf_range(0.25, 0.9)
		_flicker_wait = _rng.randf_range(4.0, 12.0)
	if _flicker_left > 0.0:
		_flicker_left -= delta
		if _rng.randf() < 0.45:
			level = _rng.randf_range(0.0, 0.35)
	_lamp_light.light_energy = 2.3 * level
	if _bulb_mat != null:
		_bulb_mat.emission_energy_multiplier = 5.0 * level
		_bulb_mat.albedo_color = Color("#fff2c8") * maxf(level, 0.25)


func _update_tics(delta: float) -> void:
	_tic_wait -= delta
	if _tic_hold > 0.0:
		_tic_hold -= delta
		if _tic_hold <= 0.0:
			_tic_target = Vector3.ZERO
	elif _tic_wait <= 0.0:
		_tic_wait = _rng.randf_range(2.5, 7.0)
		_tic_hold = _rng.randf_range(0.4, 1.6)
		# a sudden, uncomfortable head tilt / snap toward the player
		_tic_target = Vector3(_rng.randf_range(-0.18, 0.12), _rng.randf_range(-0.22, 0.22), _rng.randf_range(-0.3, 0.3))
		if _rng.randf() < 0.3:
			_spine_tic = _rng.randf_range(-0.08, 0.1)
	# jerks in fast, eases out slowly
	var speed := 22.0 if _tic_hold > 0.0 else 1.6
	_tic = _tic.lerp(_tic_target, 1.0 - exp(-delta * speed))
	_spine_tic = lerpf(_spine_tic, 0.0, 1.0 - exp(-delta * 0.8))


func _apply_tics() -> void:
	# runs after the AnimationPlayer has posed the skeleton: adds the tics on top
	if _skeleton == null:
		return
	var wander := Vector3(sin(_time * 0.37) * 0.04, sin(_time * 0.23 + 1.0) * 0.06, sin(_time * 0.29 + 2.0) * 0.05)
	var head := _skeleton.find_bone("head")
	var neck := _skeleton.find_bone("neck")
	var spine := _skeleton.find_bone("spine")
	var t := _tic + wander
	if head >= 0:
		_skeleton.set_bone_pose_rotation(head, _skeleton.get_bone_pose_rotation(head) * Quaternion.from_euler(t * 0.6))
	if neck >= 0:
		_skeleton.set_bone_pose_rotation(neck, _skeleton.get_bone_pose_rotation(neck) * Quaternion.from_euler(t * 0.4))
	if spine >= 0:
		_skeleton.set_bone_pose_rotation(spine, _skeleton.get_bone_pose_rotation(spine) * Quaternion.from_euler(Vector3(_spine_tic, 0, 0)))


func _update_fx(delta: float) -> void:
	var m := material as ShaderMaterial
	if m == null:
		return
	var sick := _danger * (0.7 + 0.3 * sin(_time * 2.3))
	m.set_shader_parameter("aberration", _fx["aberration"] + sick * 0.004)
	m.set_shader_parameter("desaturate", clampf(_fx["desaturate"] + _danger * 0.45, 0.0, 1.0))
	m.set_shader_parameter("flash", _fx["flash"])
	m.set_shader_parameter("blackout", _fx["blackout"])
	m.set_shader_parameter("wobble", _fx["wobble"] + sick * 0.25)
	_roll = lerpf(_roll, 0.0, 1.0 - exp(-delta * 1.2))


func _fx_to(key: String, peak: float, rise: float, fall: float) -> void:
	var t := create_tween()
	t.tween_method(func(v: float) -> void: _fx[key] = v, _fx[key], peak, rise)
	t.tween_method(func(v: float) -> void: _fx[key] = v, peak, 0.0, fall).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## The player gets shot: white-hot flash, the image splits and drains of color,
## the camera rolls and staggers, then everything slowly comes back.
func player_hit(strength := 1.0) -> void:
	_fx_to("flash", 0.85 * strength, 0.03, 0.35)
	_fx_to("aberration", 0.018 * strength, 0.05, 1.6)
	_fx_to("desaturate", 0.9 * strength, 0.05, 2.2)
	_fx_to("wobble", 1.0 * strength, 0.05, 1.8)
	_fx_to("blackout", 0.55 * strength, 0.25, 0.9)
	_roll = _rng.randf_range(0.12, 0.2) * (1.0 if _rng.randf() < 0.5 else -1.0) * strength
	_shake = maxf(_shake, 2.2 * strength)
	_lamp_kick = 1.0
	_flicker_left = 0.6


## How close to death the player is (0..1); the picture stays sick while it is high.
func set_danger(value: float) -> void:
	var t := create_tween()
	t.tween_property(self, "_danger", clampf(value, 0.0, 1.0), 0.8)


# ------------------------------------------------------------------ wild color choice (3D)
## While choosing a Wild's color, the card hangs in front of the player's face and
## four plain color slabs float under it. Everything is camera-local 3D, so it gets
## the same fat pixels and dithering as the rest of the scene.
const WILD_COLORS := [Card.CardColor.RED, Card.CardColor.YELLOW, Card.CardColor.GREEN, Card.CardColor.BLUE]
var hidden_hand_index := -1
var _wild_card: Node3D
var _wild_slabs: Array[MeshInstance3D] = []
var _wild_hover := -1
var _wild_start := Vector3.ZERO
var _wild_jitter_wait := 0.0
var _wild_tint := Color.WHITE


func _unshade(node: Node3D, tint: Color) -> void:
	for mi in node.get_children():
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = tint


func wild_show(from_screen: Vector2, hand_index: int) -> void:
	wild_clear()
	hidden_hand_index = hand_index
	var wild := Card.new(Card.CardColor.WILD, Card.Kind.WILD)
	_wild_card = _card_node(CardViewScript.face_for(wild), CardViewScript.back_texture())
	_unshade(_wild_card, Color(0.85, 0.82, 0.78))
	camera.add_child(_wild_card)
	_wild_start = camera.to_local(camera.project_position(from_screen / float(PIXEL_SHRINK), 0.34))
	_wild_card.position = _wild_start
	_wild_card.rotation = Vector3(0.3, 0.0, 0.4)
	var t := create_tween().set_parallel(true)
	t.tween_property(_wild_card, "position", Vector3(0.0, 0.035, -0.29), 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_wild_card, "rotation", Vector3(0.0, 0.0, -0.04), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i: int in range(4):
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.027, 0.027, 0.005)
		slab.mesh = box
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = ACTIVE_COLORS[WILD_COLORS[i]] * 0.75
		slab.material_override = m
		slab.position = Vector3(-0.054 + i * 0.036, -0.058, -0.27)
		slab.scale = Vector3.ZERO
		camera.add_child(slab)
		_wild_slabs.append(slab)
		var st := create_tween()
		st.tween_interval(0.35 + i * 0.07)
		st.tween_property(slab, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Which color slab is under this screen point (-1 if none).
func wild_pick(screen: Vector2) -> int:
	var best := -1
	var best_d := 46.0
	for i: int in range(_wild_slabs.size()):
		var p := camera.unproject_position(_wild_slabs[i].global_position) * float(PIXEL_SHRINK)
		var d := p.distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	return best


func wild_hover(i: int) -> void:
	_wild_hover = i


func _update_wild(delta: float) -> void:
	if _wild_card == null or not is_instance_valid(_wild_card):
		return
	_wild_jitter_wait -= delta
	var jump := _wild_jitter_wait <= 0.0
	if jump:
		_wild_jitter_wait = _rng.randf_range(0.03, 0.08)
	for i: int in range(_wild_slabs.size()):
		var slab := _wild_slabs[i]
		var base := Vector3(-0.054 + i * 0.036, -0.058, -0.27)
		var m := slab.material_override as StandardMaterial3D
		var col: Color = ACTIVE_COLORS[WILD_COLORS[i]]
		if i == _wild_hover:
			# erratic tremble: snaps to a new offset at uneven intervals
			if jump:
				slab.position = base + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * 0.0026 + Vector3(0, 0.006, 0.008)
				slab.rotation = Vector3(0, 0, _rng.randf_range(-0.3, 0.3))
			slab.scale = slab.scale.lerp(Vector3.ONE * 1.35, 0.3)
			m.albedo_color = col * 1.25
		else:
			slab.position = slab.position.lerp(base, 0.3)
			slab.rotation = Vector3.ZERO
			slab.scale = slab.scale.lerp(Vector3.ONE * (0.82 if _wild_hover >= 0 else 1.0), 0.3) if slab.scale.x > 0.5 else slab.scale
			m.albedo_color = col * (0.45 if _wild_hover >= 0 else 0.75)
	var want := Color(0.85, 0.82, 0.78)
	if _wild_hover >= 0:
		want = want.lerp(ACTIVE_COLORS[WILD_COLORS[_wild_hover]], 0.35)
	_wild_tint = _wild_tint.lerp(want, 0.2)
	_unshade(_wild_card, _wild_tint)
	_wild_card.position += Vector3(sin(_time * 1.7), sin(_time * 1.3), 0) * 0.00004


## The color is chosen: the card is stained with it and the slabs fall away.
func wild_choose(i: int) -> void:
	_wild_hover = i
	var col: Color = ACTIVE_COLORS[WILD_COLORS[i]]
	_wild_tint = Color(0.85, 0.82, 0.78).lerp(col, 0.6)
	for slab in _wild_slabs:
		var t := create_tween()
		t.tween_property(slab, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_callback(slab.queue_free)
	_wild_slabs.clear()
	shake(0.3)


## Put the card back in the hand.
func wild_cancel() -> void:
	if _wild_card == null:
		return
	var card := _wild_card
	_wild_card = null
	for slab in _wild_slabs:
		slab.queue_free()
	_wild_slabs.clear()
	var t := create_tween().set_parallel(true)
	t.tween_property(card, "position", _wild_start, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.tween_property(card, "rotation", Vector3(0.3, 0, 0.4), 0.35)
	t.chain().tween_callback(func() -> void:
		card.queue_free()
		hidden_hand_index = -1)


func wild_clear() -> void:
	if _wild_card != null and is_instance_valid(_wild_card):
		_wild_card.queue_free()
	_wild_card = null
	for slab in _wild_slabs:
		if is_instance_valid(slab):
			slab.queue_free()
	_wild_slabs.clear()
	_wild_hover = -1
	_wild_tint = Color(0.85, 0.82, 0.78)


## The player's card leaves the fist (or the Wild leaves the player's face) and
## is thrown onto the pile, in 3D, with the speed the fist had when it let go.
func player_throw(card: Card, from_screen: Vector2) -> void:
	var node: Node3D
	var launch := Vector3.ZERO
	if _wild_card != null and is_instance_valid(_wild_card):
		node = _wild_card
		_wild_card = null
		node.reparent(_world, true)
		launch = (PILE - node.global_position) * 0.6 + Vector3(0, 0.25, 0)
	elif _player_held != null and is_instance_valid(_player_held):
		node = _player_held
		_player_held = null
		launch = _fist_vel.limit_length(3.0) * 0.9 + Vector3(0, 0.3, 0)
	else:
		node = _card_node(CardViewScript.face_for(card), CardViewScript.back_texture())
		_unshade(node, Color(0.85, 0.82, 0.78))
		_world.add_child(node)
		var p := camera.project_position(from_screen / float(PIXEL_SHRINK), 0.34)
		node.global_transform = Transform3D(camera.global_basis.scaled_local(Vector3.ONE * (_hand_card_h / CARD_SIZE.y)), p)
		launch = (PILE - p) * 0.8 + Vector3(0, 0.3, 0)
	hidden_hand_index = -1
	await _fly_to_pile(node, card, node.global_transform, launch, 0.44, _rng.randf_range(-0.8, 0.8))


var _puffed := false


func _set_held_face(face: Texture2D) -> void:
	var front := _held.get_child(0) as MeshInstance3D
	(front.material_override as StandardMaterial3D).albedo_texture = face


## A thick cloud of smoke out of his mouth, drifting up toward the lamp.
func _puff() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 34
	p.lifetime = 2.6
	p.explosiveness = 0.75
	p.direction = Vector3(0.1, 1.0, 0.6)
	p.spread = 25.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.22
	p.gravity = Vector3(0, 0.05, 0)
	p.damping_min = 0.08
	p.damping_max = 0.15
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 2.2))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.8, 0.78, 0.75, 0.3))
	fade.set_color(1, Color(0.7, 0.68, 0.66, 0.0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = g
	m.albedo_texture = puff
	q.material = m
	p.mesh = q
	_world.add_child(p)
	var head := _skeleton.find_bone("head")
	p.global_position = (_skeleton.global_transform * _skeleton.get_bone_global_pose(head)) * Vector3(0.0, 0.03, 0.12)
	p.emitting = true
	get_tree().create_timer(3.2).timeout.connect(p.queue_free)
