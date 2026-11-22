class_name MainMenu
extends Control

## The main menu is a room, not a set of windows. You stand in a dark plank room under one
## swinging oil lamp; your head follows the mouse, and whatever you look at draws the eye in
## (the camera leans toward it and focuses on it). Nothing looks like a button.
## - The options are burnt into the wall in front of you; the lamp swings to the one you look
##   at and it smoulders. Click it.
## - Settings: you turn to the corner on the left, a candle on a small table. The whiskey
##   bottle is the volume (look at it and drag the liquor up or down; the glass has marks);
##   the window is the screen (click: shutters open = full screen, shut = a window; its state
##   is burnt under it). Esc or right click turns you back.
## - Play: you turn to the door on the right; moonlight leaks round it. You walk, push it open
##   on the night outside, and step out.
## - Quit: the lamp's flame is blown out (it bends, dies, smokes), then the game closes.
## The props are simple shapes for now (to be swapped for Tripo models).

signal play_requested
signal debug_requested

const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const WOOD_TEX := preload("res://assets/textures/wood_grain.png")
const WALL_TEX := preload("res://assets/textures/menu/wall_planks.png")
const NIGHT_TEX := preload("res://assets/textures/menu/night_road.png")
const OUTLINE := preload("res://resources/shaders/outline.gdshader")
const PROPS := {
	"table": preload("res://assets/models/menu/mn_table.glb"),
	"candle": preload("res://assets/models/menu/mn_candle.glb"),
	"chair": preload("res://assets/models/menu/mn_chair.glb"),
	"bottle": preload("res://assets/models/menu/mn_bottle.glb"),
	"window": preload("res://assets/models/menu/mn_window.glb"),
	"door": preload("res://assets/models/menu/mn_door.glb"),
}
const SETTINGS_PATH := "user://settings.cfg"
const SettingsScript = preload("res://scripts/menu/settings_panel.gd")
const PIXEL_SHRINK := 3
const PIVOT := Vector3(-0.4, 3.3, 1.7)       # where the lamp's chain hangs from
const CHAIN := 1.25
const DIM := Color(0.42, 0.38, 0.33, 1)
const CHAR := Color(0.36, 0.22, 0.14, 1)     # burnt words at rest: dark, but readable
const SMOULDER := Color(1.0, 0.45, 0.15, 1)
const ROOM_W := 3.0      # half width of the room (smaller: it was a hall, it felt empty)
const TABLE_AT := Vector3(-ROOM_W + 0.6, 0, 2.6)
const CHIPS_AT := TABLE_AT + Vector3(0.2, 0.83, 0.12)      # the stack of chips (volume): near edge, on the right
const CARD_AT := TABLE_AT + Vector3(-0.17, 0.834, -0.1)   # the card (screen mode): back, to the left
const CARD_FACE := preload("res://assets/cards/faces/wild.png")
const CARD_BACK := preload("res://assets/cards/faces/back.png")
const CHIP_COUNT := 10
const CHIP_H := 0.016
const WINDOW_AT := Vector3(-ROOM_W + 0.02, 1.95, 1.7)
const DOOR_AT := Vector3(ROOM_W, 0, 2.4)
# where you stand and look, for each place you turn to
const VIEW_FRONT := [Vector3(0.4, 1.6, 5.2), Vector3(0.2, 1.45, 0.0)]
const VIEW_CORNER := [Vector3(-2.0, 1.5, 3.7), Vector3(-ROOM_W + 0.55, 0.85, 2.55)]
const VIEW_DOOR := [Vector3(0.6, 1.6, 4.0), Vector3(ROOM_W, 1.3, 2.4)]

var view: SubViewportContainer
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _lamp: Node3D
var _spot: SpotLight3D
var _glow: OmniLight3D
var _bulb: MeshInstance3D
var _bulb_mat: StandardMaterial3D
var _smoke: GPUParticles3D
var _title: Label3D
var _targets: Array = []       # things you can look at and click: {kind, place, label, center, extent, hit, heat, action}
var _hits: Control
var _hint: Label
var _time := 0.0
var _swing := Vector2.ZERO
var _swing_v := Vector2.ZERO
var _aim := Vector3.ZERO
var _hot := -1
var _place := "front"
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _gaze := Vector2.ZERO      # the mouse, -1..1 across the screen
var _walk := -1.0
var _blow := -1.0
var _volume := 0.8
var _fullscreen := false
var _chips: Array[MeshInstance3D] = []
var _chip_drop: Array[float] = []    # height each chip still has to fall
var _card: Node3D
var _card_flip := 0.0
var _drag_acc := 0.0
var _shutters: Array[Node3D] = []
var _shutter_open := 0.0
var _door: Node3D
var _outside_light: SpotLight3D
var _crack_mat: StandardMaterial3D
var _cracks: Array[Node3D] = []
var _lantern: OmniLight3D
var _far_fire: OmniLight3D
var _dragging_chips := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_settings()
	_build_view()
	_build_room()
	_build_lamp()
	_build_corner()
	_build_door()
	_build_decor()
	_hits = Control.new()
	_hits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hits)
	_build_targets()
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.4, 0.36, 0.31, 0.8))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -40
	_hint.offset_left = -200
	_hint.offset_right = 200
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	var debug := Button.new()
	debug.text = "debug"
	debug.flat = true
	debug.focus_mode = Control.FOCUS_NONE
	debug.add_theme_font_size_override("font_size", 14)
	debug.add_theme_color_override("font_color", DIM)
	debug.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	debug.offset_left = -110
	debug.offset_top = -46
	debug.offset_right = -20
	debug.offset_bottom = -14
	debug.pressed.connect(func() -> void: debug_requested.emit())
	add_child(debug)
	_cam_pos = VIEW_FRONT[0]
	_cam_look = VIEW_FRONT[1]
	visibility_changed.connect(func() -> void:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED)


func open() -> void:
	visible = true
	_place = "front"
	_walk = -1.0
	_blow = -1.0
	_hot = -1
	if _door != null:
		_door.rotation.y = 0.0


## For tests: run a front option by index (0 Play, 1 Settings, 2 Quit).
func choose(index: int) -> void:
	(_targets[index]["action"] as Callable).call()


# ------------------------------------------------------------------ the room
func _build_view() -> void:
	view = SubViewportContainer.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.stretch = true
	view.stretch_shrink = PIXEL_SHRINK
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dither := ShaderMaterial.new()
	dither.shader = preload("res://resources/shaders/pixel_dither.gdshader")
	view.material = dither
	add_child(view)
	_viewport = SubViewport.new()
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.own_world_3d = true
	view.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#020101")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3a3440")
	env.ambient_light_energy = 0.14
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.04
	env.volumetric_fog_length = 7.0     # only the room: past the door the night stays clear
	env.volumetric_fog_albedo = Color("#b9a68c")
	env.volumetric_fog_anisotropy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	_camera = Camera3D.new()
	_camera.fov = 56.0
	_world.add_child(_camera)
	var film := ColorRect.new()
	film.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://resources/shaders/film_look.gdshader")
	film.material = fm
	add_child(film)


func _wood(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = WOOD_TEX
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.35, 0.35, 0.35)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


func _flat(col: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, at: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = at
	(parent if parent != null else _world).add_child(mi)
	return mi


func _cyl(r_top: float, r_bottom: float, h: float, at: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	mi.mesh = c
	mi.material_override = m
	mi.position = at
	(parent if parent != null else _world).add_child(mi)
	return mi


func _build_room() -> void:
	var front := _planks(Vector2(ROOM_W * 2, 6), Vector3(0, 2, 0), Vector3.ZERO)
	# the left wall, with a hole for the window (its planks continue across the pieces)
	var face_r := Vector3(0, PI * 0.5, 0)
	var hz := Vector2(WINDOW_AT.z - 0.36, WINDOW_AT.z + 0.36)     # the hole, along the wall
	var hy := Vector2(WINDOW_AT.y - 0.35, WINDOW_AT.y + 0.42)     # and up the wall
	_planks(Vector2(7, hy.x + 1.0), Vector3(-ROOM_W, (hy.x - 1.0) * 0.5, 3), face_r)
	_planks(Vector2(7, 5.0 - hy.y), Vector3(-ROOM_W, (hy.y + 5.0) * 0.5, 3), face_r)
	_planks(Vector2(hz.x + 0.5, hy.y - hy.x), Vector3(-ROOM_W, (hy.x + hy.y) * 0.5, (hz.x - 0.5) * 0.5), face_r)
	_planks(Vector2(6.5 - hz.y, hy.y - hy.x), Vector3(-ROOM_W, (hy.x + hy.y) * 0.5, (hz.y + 6.5) * 0.5), face_r)
	# the right wall, with a gap for the door
	_planks(Vector2(1.9, 6), Vector3(ROOM_W, 2, 0.85), Vector3(0, -PI * 0.5, 0))
	_planks(Vector2(3.9, 6), Vector3(ROOM_W, 2, 4.85), Vector3(0, -PI * 0.5, 0))
	_planks(Vector2(1.0, 3.7), Vector3(ROOM_W, 4.15, 2.4), Vector3(0, -PI * 0.5, 0))
	var floor := _planks(Vector2(ROOM_W * 2, 7), Vector3(0, 0, 3), Vector3(-PI * 0.5, 0, 0))
	(floor.material_override as StandardMaterial3D).albedo_color = Color(0.62, 0.52, 0.46)
	front.name = "FrontWall"
	var ceiling := _box(Vector3(ROOM_W * 2 + 0.4, 0.2, 7.4), Vector3(0, 4.2, 3), _wood(Color(0.12, 0.08, 0.05)))
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


## A wall of planks: the Gemini plank texture, tiled about every 1.6 m.
func _planks(size: Vector2, at: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = WALL_TEX
	m.albedo_color = Color(0.95, 0.85, 0.78)
	# mapped in world space, so walls cut in pieces (round the window) keep their planks lined up
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / 1.6, 1.0 / 1.6, 1.0 / 1.6)
	m.texture_repeat = true
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mi.material_override = m
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_world.add_child(mi)
	return mi


## A Tripo prop (its own texture, the game's toon shading); returns its root.
func _prop(key: String, at: Vector3, rot_y: float, scale := Vector3.ONE, parent: Node3D = null) -> Node3D:
	var root := (PROPS[key] as PackedScene).instantiate() as Node3D
	(parent if parent != null else _world).add_child(root)
	root.position = at
	root.rotation.y = rot_y
	root.scale = scale
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s: int in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := StandardMaterial3D.new()
			m.albedo_texture = src.albedo_texture
			m.albedo_color = Color(0.95, 0.92, 0.9)
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			mi.set_surface_override_material(s, m)
	return root

func _build_lamp() -> void:
	_lamp = Node3D.new()
	_lamp.position = PIVOT
	_world.add_child(_lamp)
	var iron := _flat(Color(0.08, 0.07, 0.06))
	_box(Vector3(0.02, CHAIN, 0.02), Vector3(0, -CHAIN * 0.5, 0), iron, _lamp)
	_cyl(0.05, 0.22, 0.16, Vector3(0, -CHAIN - 0.05, 0), iron, _lamp)
	_bulb = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.06
	sph.height = 0.12
	_bulb.mesh = sph
	_bulb_mat = _flat(Color(1.0, 0.78, 0.45), true)
	_bulb.material_override = _bulb_mat
	_bulb.position = Vector3(0, -CHAIN - 0.12, 0)
	_lamp.add_child(_bulb)
	_glow = OmniLight3D.new()
	_glow.light_color = Color("#ffb066")
	_glow.light_energy = 0.9
	_glow.omni_range = 3.0
	_glow.position = _bulb.position
	_lamp.add_child(_glow)
	_spot = SpotLight3D.new()
	_spot.light_color = Color("#ffc285")
	_spot.light_energy = 5.0
	_spot.spot_range = 8.0
	_spot.spot_angle = 30.0
	_spot.spot_angle_attenuation = 1.4
	_spot.shadow_enabled = true
	_spot.light_volumetric_fog_energy = 2.5
	_world.add_child(_spot)
	# the smoke of a blown-out flame (only when quitting)
	_smoke = GPUParticles3D.new()
	_smoke.emitting = false
	_smoke.one_shot = true
	_smoke.amount = 14
	_smoke.lifetime = 1.4
	_smoke.explosiveness = 0.0
	_smoke.position = _bulb.position
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.08
	pm.initial_velocity_max = 0.14
	pm.gravity = Vector3(0.02, 0.04, -0.05)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.15
	pm.scale_min = 0.4
	pm.scale_max = 0.8
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.53, 0.5, 0.28))
	ramp.set_color(1, Color(0.4, 0.4, 0.42, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	_smoke.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var qm := StandardMaterial3D.new()
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	quad.material = qm
	_smoke.draw_pass_1 = quad
	_lamp.add_child(_smoke)


## The settings corner: a small table with a candle, a stack of poker chips (the volume) and a
## card (the screen: face up is full screen, face down a window). The window is just the night.
func _build_corner() -> void:
	# the table's top is 0.8 m up; it stands with its long side along the wall
	_prop("table", TABLE_AT, PI * 0.5, Vector3(0.85, 1, 0.85))
	_prop("chair", TABLE_AT + Vector3(0.95, 0, 0.55), -2.2)
	_prop("bottle", TABLE_AT + Vector3(-0.12, 0.8, 0.32), 0.4)
	# the chips: worn clay chips in muted colors; as many on the stack as the volume
	var chip_cols := [Color(0.45, 0.1, 0.07), Color(0.75, 0.7, 0.6), Color(0.1, 0.09, 0.09)]
	for k: int in range(CHIP_COUNT):
		var m := _flat(chip_cols[k % 3])
		var chip := _cyl(0.05, 0.05, CHIP_H * 0.9, Vector3.ZERO, m)
		var edge := _cyl(0.051, 0.051, CHIP_H * 0.35, Vector3.ZERO, _flat(Color(0.85, 0.8, 0.7)), chip)
		edge.position = Vector3.ZERO
		_chips.append(chip)
		_chip_drop.append(0.0)
	_set_chips(false)
	# the card, lying on the table on a pivot so it can turn over
	_card = Node3D.new()
	_card.position = CARD_AT
	_card.rotation.y = 0.35
	_world.add_child(_card)
	for side: int in range(2):
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.17, 0.2)
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = CARD_FACE if side == 0 else CARD_BACK
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		q.material_override = m
		q.rotation.x = -PI * 0.5 if side == 0 else PI * 0.5     # face looks up, back looks down
		q.position = Vector3(0, 0.001 if side == 0 else -0.001, 0)
		_card.add_child(q)
	_card_flip = 0.0 if _fullscreen else 1.0
	# a candle beside it: the corner's own small light
	_prop("candle", TABLE_AT + Vector3(-0.2, 0.8, -0.4), 0.8)
	# (the candle is an old cold stub: the room has one light, the lamp, and it follows your eyes)
	# the window (the Tripo window, its glass gone but for a few shards), and outside it the
	# painted night, with cold moonlight coming in
	_prop("window", WINDOW_AT + Vector3(0.03, -0.52, 0), PI * 0.5)
	var outside := MeshInstance3D.new()
	var oq := QuadMesh.new()
	oq.size = Vector2(5.2, 2.9)
	outside.mesh = oq
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_texture = NIGHT_TEX
	om.albedo_color = Color(0.55, 0.58, 0.68)
	om.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	outside.material_override = om
	outside.position = Vector3(-ROOM_W - 2.2, WINDOW_AT.y - 0.2, WINDOW_AT.z)
	outside.rotation.y = PI * 0.5
	_world.add_child(outside)
	var moon_in := SpotLight3D.new()
	moon_in.light_color = Color("#8fa6d0")
	moon_in.light_energy = 1.6
	moon_in.spot_range = 6.0
	moon_in.spot_angle = 20.0
	moon_in.shadow_enabled = true
	moon_in.light_volumetric_fog_energy = 2.0
	_world.add_child(moon_in)
	moon_in.look_at_from_position(WINDOW_AT + Vector3(-1.5, 0.9, -0.3), TABLE_AT + Vector3(0.6, 0.4, 0.2))

## The door out: moonlight leaks through its cracks; behind it, the night.
func _build_door() -> void:
	var frame := _wood(Color(0.2, 0.13, 0.08))
	_box(Vector3(0.1, 2.3, 0.1), DOOR_AT + Vector3(-0.05, 1.15, -0.55), frame)
	_box(Vector3(0.1, 2.3, 0.1), DOOR_AT + Vector3(-0.05, 1.15, 0.55), frame)
	_box(Vector3(0.1, 0.1, 1.2), DOOR_AT + Vector3(-0.05, 2.3, 0), frame)
	# outside: the painted moonlit road (Gemini), big and far, seen through the open door
	var night := MeshInstance3D.new()
	var nq := QuadMesh.new()
	nq.size = Vector2(30, 16.7)
	night.mesh = nq
	var nm := StandardMaterial3D.new()
	nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nm.albedo_texture = NIGHT_TEX
	nm.albedo_color = Color(0.55, 0.58, 0.68)    # deeper night than the painting
	nm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	night.material_override = nm
	night.position = DOOR_AT + Vector3(14.0, 2.45, 0)     # its horizon at eye height
	night.rotation.y = -PI * 0.5
	_world.add_child(night)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_texture = preload("res://assets/textures/zones/rest_ground.png")
	# lit like the painting (cold moonlit dirt), not by the room's lights: it runs on into it
	dirt.albedo_color = Color(0.36, 0.4, 0.52)
	dirt.uv1_triplanar = true
	dirt.uv1_world_triplanar = true
	dirt.uv1_scale = Vector3(0.5, 0.5, 0.5)
	dirt.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	dirt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_build_outside(dirt)
	_outside_light = SpotLight3D.new()
	_outside_light.light_color = Color("#9fb4dc")
	_outside_light.light_energy = 0.0
	_outside_light.spot_range = 9.0
	_outside_light.spot_angle = 22.0
	_outside_light.shadow_enabled = true
	_outside_light.light_volumetric_fog_energy = 3.0
	_world.add_child(_outside_light)
	_outside_light.look_at_from_position(DOOR_AT + Vector3(3.0, 2.4, 0.3), Vector3(0.8, 0, 3.0))
	_door = Node3D.new()
	_door.position = DOOR_AT + Vector3(-0.08, 0, -0.5)
	_world.add_child(_door)
	# the Tripo door came out wide and low: squeezed to a doorway (1.05 m by 2.15 m)
	# the door leaf only (its frame was cut off in Blender; the frame here stays put): 1 m by 2.1 m
	_prop("door", Vector3(0, 0, 0.5), -PI * 0.5, Vector3(0.68, 1.066, 0.3), _door)
	# moonlight through the cracks round the door
	_crack_mat = _flat(Color(0.55, 0.65, 0.85), true)
	_cracks.append(_box(Vector3(0.02, 0.02, 1.0), DOOR_AT + Vector3(-0.1, 0.02, 0), _crack_mat))
	var leak := OmniLight3D.new()
	leak.light_color = Color("#7f96c8")
	leak.light_energy = 0.7
	leak.omni_range = 1.4
	leak.position = DOOR_AT + Vector3(-0.25, 0.1, 0)
	_world.add_child(leak)
	_cracks.append(leak)


## Outside the door: uneven moonlit ground with the dirt road running out to meet the painted
## one, stones, dry brush and two dead trees as silhouettes; behind the painting, a wide
## backdrop in its own sky and ground colors so no edge ever shows.
func _build_outside(dirt: StandardMaterial3D) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.35
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 56
	var nz := 60
	var len_x := 14.0
	var len_z := 30.0
	var heights := []
	for i: int in range(nx + 1):
		var row := []
		for j: int in range(nz + 1):
			var x := i * len_x / nx
			var z := -len_z * 0.5 + j * len_z / nz
			var road := 1.0 - smoothstep(0.55, 1.1, absf(z))
			var h := (noise.get_noise_2d(x, z) * 0.35 + noise.get_noise_2d(x * 3.1, z * 3.1) * 0.08) * (1.0 - road * 0.85)
			h *= smoothstep(0.0, 1.5, x)                # flat at the threshold
			# the road: two ruts worn into it
			h -= road * 0.04 * (1.0 - absf(absf(z) - 0.35) / 0.35) if absf(z) < 0.7 else 0.0
			row.append(h)
		heights.append(row)
	for i: int in range(nx):
		for j: int in range(nz):
			var quad := []
			for c: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var x := c.x * len_x / nx
				var z := -len_z * 0.5 + c.y * len_z / nz
				quad.append(Vector3(x, heights[c.x][c.y], z))
			for k: int in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = quad[k]
				var road := 1.0 - smoothstep(0.55, 1.1, absf(v.z))
				# moonlit dirt; the road paler; hollows darker, bumps catch the light
				var shade := 0.85 + v.y * 0.9
				st.set_color(Color(0.42, 0.44, 0.52).lerp(Color(0.6, 0.6, 0.66), road * 0.8) * shade)
				st.add_vertex(DOOR_AT + v)
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	var m := dirt.duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = m
	_world.add_child(ground)
	# stones and dry brush along the way
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var stone := _flat(Color(0.45, 0.45, 0.5))
	var brush := _flat(Color(0.12, 0.1, 0.09))
	for k: int in range(26):
		var x := rng.randf_range(1.2, 12.0)
		var z := rng.randf_range(1.0, 7.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		if rng.randf() < 0.5:
			var s := _cyl(0.0, rng.randf_range(0.08, 0.22), rng.randf_range(0.06, 0.16), DOOR_AT + Vector3(x, 0.03, z), stone)
			s.rotation.y = rng.randf() * TAU
		else:
			for b: int in range(5):
				var stick := _box(Vector3(0.025, rng.randf_range(0.25, 0.55), 0.025), DOOR_AT + Vector3(x, 0.15, z), brush)
				stick.rotation = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	# two dead trees by the road, black against the sky
	for spot: Vector3 in [Vector3(4.5, 0, -2.6), Vector3(8.5, 0, 3.2)]:
		var tree := (preload("res://assets/models/zones/rest_point/rp_tree.glb") as PackedScene).instantiate() as Node3D
		_world.add_child(tree)
		tree.position = DOOR_AT + spot
		tree.rotation.y = spot.x
		tree.scale = Vector3.ONE * 0.8
		for node in tree.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = _flat(Color(0.14, 0.12, 0.12))
	# a lantern hanging from a post by the road: warm light against the cold night
	var post := _wood(Color(0.2, 0.13, 0.08))
	var post_at := DOOR_AT + Vector3(2.2, 0, -1.3)
	_box(Vector3(0.12, 2.5, 0.12), post_at + Vector3(0, 1.25, 0), post)
	_box(Vector3(0.6, 0.08, 0.08), post_at + Vector3(0, 2.4, 0.26), post).rotation.y = PI * 0.5
	var glass := _box(Vector3(0.14, 0.2, 0.14), post_at + Vector3(0, 2.15, 0.5), _flat(Color(1.0, 0.72, 0.38), true))
	glass.name = "LanternGlass"
	_lantern = OmniLight3D.new()
	_lantern.light_color = Color("#ffa25a")
	_lantern.light_energy = 1.3
	_lantern.omni_range = 5.0
	_lantern.shadow_enabled = true
	_lantern.position = post_at + Vector3(0, 2.1, 0.5)
	_world.add_child(_lantern)
	# a campfire far away on the plain, the only other light in the world
	var ember := MeshInstance3D.new()
	var es := SphereMesh.new()
	es.radius = 0.12
	es.height = 0.2
	ember.mesh = es
	ember.material_override = _flat(Color(1.0, 0.5, 0.18), true)
	ember.position = DOOR_AT + Vector3(12.5, 0.4, 3.6)
	_world.add_child(ember)
	_far_fire = OmniLight3D.new()
	_far_fire.light_color = Color("#ff7a30")
	_far_fire.light_energy = 0.9
	_far_fire.omni_range = 2.5
	_far_fire.position = ember.position + Vector3(0, 0.3, 0)
	_world.add_child(_far_fire)
	# the moon: a cold light from high over the plain, long shadows toward the house
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("#8ea4d8")
	moon.light_energy = 0.75
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 30.0
	moon.light_volumetric_fog_energy = 1.5
	_world.add_child(moon)
	moon.look_at_from_position(DOOR_AT + Vector3(14, 9, -6), DOOR_AT + Vector3(2, 0, 1))
	# a low mist creeping over the ground, pale in the moonlight
	var mist := FogVolume.new()
	mist.size = Vector3(13, 1.0, 16)
	mist.position = DOOR_AT + Vector3(7.5, 0.25, 0)
	var fm := FogMaterial.new()
	fm.density = 0.25
	fm.albedo = Color(0.55, 0.62, 0.8)
	fm.height_falloff = 2.5
	fm.edge_fade = 0.6
	mist.material = fm
	_world.add_child(mist)
	# dust and sand drifting through the moonlight
	var dust := GPUParticles3D.new()
	dust.amount = 70
	dust.lifetime = 10.0
	dust.preprocess = 10.0
	dust.position = DOOR_AT + Vector3(4.0, 1.0, 0)
	dust.visibility_aabb = AABB(Vector3(-6, -2, -8), Vector3(12, 5, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(4, 1.0, 5)
	pm.gravity = Vector3(-0.08, -0.01, 0.04)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.1
	pm.color = Color(0.75, 0.8, 0.95, 0.5)
	dust.process_material = pm
	var dq := QuadMesh.new()
	dq.size = Vector2(0.02, 0.02)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dq.material = dm
	dust.draw_pass_1 = dq
	_world.add_child(dust)
	# the backdrop behind the painting: its sky above, its ground below, very wide
	var sky := _flat(Color(0.028, 0.045, 0.1), true)
	_box(Vector3(0.1, 30, 80), DOOR_AT + Vector3(14.3, 14.0, 0), sky)
	_box(Vector3(0.1, 4.0, 80), DOOR_AT + Vector3(14.2, -1.0, 0), _flat(Color(0.11, 0.12, 0.17), true))


# ------------------------------------------------------------------ the room's clutter
## Placeholders made here until the Tripo props come (see modelos_tripo/zonas/menu/prompts.md):
## a shelf of bottles, wanted posters nailed up, barrels and crates in the corners.
func _build_decor() -> void:
	var plank := _wood(Color(0.3, 0.2, 0.13))
	# a shelf of bottles on the front wall, to the right of the words
	for row: int in range(2):
		var y := 1.25 + row * 0.6
		_box(Vector3(1.5, 0.05, 0.24), Vector3(1.75, y, 0.12), plank)
		for k: int in range(4 - row):
			var b := _prop("bottle", Vector3(1.2 + k * 0.33 + (0.12 if row == 1 else 0.0), y + 0.025, 0.12), k * 1.3,
				Vector3.ONE * (0.8 + 0.15 * sin(k * 2.1 + row)))
			b.rotation.z = 0.0 if k != 2 or row == 1 else 1.45     # one lies on its side
	# wanted posters, nailed up, curling, their faces gone dark
	var spots := [[Vector3(0.95, 0.5, 0.012), Vector3.ZERO, 0.05], [Vector3(2.45, 0.6, 0.012), Vector3.ZERO, -0.08],
		[Vector3(ROOM_W - 0.012, 1.55, 4.3), Vector3(0, -PI * 0.5, 0), 0.03]]
	for i: int in range(spots.size()):
		var s: Array = spots[i]
		var poster := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.42, 0.56)
		poster.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_texture = _poster_texture(i)
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		poster.material_override = m
		poster.position = s[0] + Vector3(0, 0.6, 0)
		poster.rotation = s[1]
		poster.rotation.z = s[2]
		_world.add_child(poster)
	# barrels in the front right corner, crates stacked in the front left one
	for k: int in range(2):
		var at := Vector3(ROOM_W - 0.4 - k * 0.65, 0, 0.45 + k * 0.1)
		_cyl(0.28, 0.3, 0.85, at + Vector3(0, 0.425, 0), _wood(Color(0.34, 0.22, 0.14)))
		for band: float in [0.12, 0.73]:
			_cyl(0.305, 0.305, 0.05, at + Vector3(0, band, 0), _flat(Color(0.09, 0.08, 0.07)))
	for k: int in range(3):
		var at := Vector3(-ROOM_W + 0.4 + (0.62 if k == 1 else 0.0), 0.3 + (0.6 if k == 2 else 0.0), 0.4)
		var crate := _box(Vector3(0.6, 0.6, 0.6), at, _wood(Color(0.38, 0.27, 0.17)))
		crate.rotation.y = 0.1 * (k - 1)
	# an old rug under where you stand
	var rug := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(2.6, 1.7)
	rug.mesh = rq
	rug.material_override = _flat(Color(0.25, 0.08, 0.06))
	rug.rotation.x = -PI * 0.5
	rug.position = Vector3(0.2, 0.005, 3.2)
	_world.add_child(rug)


## A wanted poster drawn here: yellowed paper, burnt edges, a dark blot where the face was,
## lines of type nobody can read any more.
func _poster_texture(seed: int) -> ImageTexture:
	var w := 42
	var h := 56
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed
	for y: int in range(h):
		for x: int in range(w):
			var edge := mini(mini(x, w - 1 - x), mini(y, h - 1 - y))
			var c := Color(0.72, 0.62, 0.45) * rng.randf_range(0.85, 1.05)
			if edge < 2 + rng.randi() % 2:
				c = Color(0.25, 0.15, 0.08)      # burnt edge
			c.a = 1.0
			img.set_pixel(x, y, c)
	var ink := Color(0.18, 0.12, 0.08)
	for x: int in range(6, w - 6):
		img.set_pixel(x, 6, ink)              # the big word at the top, smeared
		img.set_pixel(x, 7, ink)
	for y: int in range(12, 32):
		for x: int in range(12, w - 12):
			img.set_pixel(x, y, Color(0.12, 0.08, 0.06))   # where the face was
	for line: int in range(4):
		var y := 36 + line * 4
		for x: int in range(7, w - 7 - rng.randi() % 8):
			if rng.randf() < 0.75:
				img.set_pixel(x, y, ink)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ things to look at
func _word(text: String, size: int, at: Vector3, facing := Vector3.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = size
	l.pixel_size = 0.004
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.shaded = false
	l.modulate = CHAR
	l.position = at
	l.rotation = facing
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_world.add_child(l)
	return l


## Something you can look at: when the mouse is on it, the eye leans in (focus) and it warms.
func _add_target(kind: String, place: String, label: Label3D, center: Vector3, extent: Vector3,
		focus: float, action: Callable) -> void:
	# the area only measures where the thing is on screen; picking is done in _pick()
	var hit := Control.new()
	hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hits.add_child(hit)
	_targets.append({"kind": kind, "place": place, "label": label, "center": center, "extent": extent,
		"focus": focus, "hit": hit, "heat": 0.0, "action": action, "meshes": []})


## The meshes of a thing get an ember outline while you look at it.
func _outline_meshes(index: int, meshes: Array) -> void:
	_targets[index]["meshes"] = meshes


func _set_outline(t: Dictionary, on: bool) -> void:
	var l: Label3D = t["label"]
	if l != null:
		l.outline_size = 10 if on else 0
		l.outline_modulate = Color(0.9, 0.35, 0.1, 0.9)
	for mi: MeshInstance3D in t["meshes"]:
		var m := mi.material_override as StandardMaterial3D
		if m == null:
			continue
		if on and m.next_pass == null:
			var o := ShaderMaterial.new()
			o.shader = OUTLINE
			o.set_shader_parameter("grow", 0.004)
			o.set_shader_parameter("color", Color(0.95, 0.42, 0.12, 1))
			m.next_pass = o
		elif not on:
			m.next_pass = null


func _build_targets() -> void:
	_title = _word("UNTITLED", 200, Vector3(-1.7, 2.45, 0.02))
	_title.modulate = Color(0.42, 0.27, 0.17, 1)
	var words := [["Play", _play], ["Settings", func() -> void: _turn("corner")], ["Quit", _quit]]
	for i: int in range(words.size()):
		var l := _word(words[i][0], 110, Vector3(-1.55, 1.45 - i * 0.5, 0.02))
		_add_target("word", "front", l, Vector3.ZERO, Vector3.ZERO, 0.18, words[i][1])
	_add_target("chips", "corner", null, CHIPS_AT + Vector3(0, 0.08, 0), Vector3(0.12, 0.18, 0.12), 0.3, func() -> void: pass)
	_outline_meshes(_targets.size() - 1, _chips)
	_add_target("card", "corner", null, CARD_AT + Vector3(0, 0.01, 0), Vector3(0.17, 0.03, 0.17), 0.3, func() -> void:
		_fullscreen = not _fullscreen
		_save_settings())
	var card_meshes: Array = []
	for c in _card.get_children():
		card_meshes.append(c)
	_outline_meshes(_targets.size() - 1, card_meshes)
	_build_tip()

func _on_target_input(index: int, e: InputEvent) -> void:
	var t: Dictionary = _targets[index]
	if t["place"] != _place or _walk >= 0.0 or _blow >= 0.0:
		return
	if t["kind"] == "chips":
		# drag up to stack chips on, down to take them off (or the wheel), one chip at a time
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_dragging_chips = e.pressed
			_drag_acc = 0.0
			if not e.pressed and not (t["hit"] as Control).get_global_rect().has_point(get_global_mouse_position()):
				_hot = -1
		elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_add_chips(1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		elif e is InputEventMouseMotion and _dragging_chips:
			_drag_acc -= e.relative.y
			while absf(_drag_acc) >= 16.0:
				_add_chips(1 if _drag_acc > 0.0 else -1)
				_drag_acc -= 16.0 * signf(_drag_acc)
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		(t["action"] as Callable).call()


func _add_chips(n: int) -> void:
	var before := roundi(_volume * CHIP_COUNT)
	var after := clampi(before + n, 0, CHIP_COUNT)
	if after == before:
		return
	_volume = float(after) / CHIP_COUNT
	if after > before:
		_chip_drop[after - 1] = 0.12      # the new chip drops onto the stack
	_set_chips(true)
	_save_settings()


func _set_chips(_animate: bool) -> void:
	var count := roundi(_volume * CHIP_COUNT)
	for k: int in range(_chips.size()):
		_chips[k].visible = k < count


# ------------------------------------------------------------------ what the mouse is on
## Every frame, from where things really are on screen now: the one under the mouse is
## looked at (the smallest one if several overlap). The one already looked at keeps it a
## little longer (a margin), so the eye leaning in never makes it flicker. While stacking
## chips, the chips keep it.
func _pick() -> void:
	if _dragging_chips:
		return
	var mouse := get_local_mouse_position()
	if _hot >= 0:
		var cur: Dictionary = _targets[_hot]
		var r := Rect2((cur["hit"] as Control).position, (cur["hit"] as Control).size).grow(14.0)
		if cur["place"] == _place and (cur["hit"] as Control).visible and r.has_point(mouse):
			return
	var best := -1
	var best_area := INF
	for i: int in range(_targets.size()):
		var t: Dictionary = _targets[i]
		var hit: Control = t["hit"]
		if t["place"] != _place or not hit.visible or _walk >= 0.0 or _blow >= 0.0:
			continue
		var r := Rect2(hit.position, hit.size)
		if r.has_point(mouse) and r.get_area() < best_area:
			best = i
			best_area = r.get_area()
	_hot = best
	mouse_default_cursor_shape = Control.CURSOR_ARROW if best < 0 else 		(Control.CURSOR_VSIZE if _targets[best]["kind"] == "chips" else Control.CURSOR_POINTING_HAND)


func _gui_input(event: InputEvent) -> void:
	if _hot >= 0 and (event is InputEventMouseButton or event is InputEventMouseMotion):
		_on_target_input(_hot, event)
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_chips = false


# ------------------------------------------------------------------ the tip card
var _tip: PanelContainer
var _tip_title: Label
var _tip_value: Label
var _tip_how: Label


func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.custom_minimum_size = Vector2(260, 0)
	_tip.modulate.a = 0.0
	add_child(_tip)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(col)
	_tip_title = Label.new()
	_tip_title.theme_type_variation = &"HeaderLabel"
	_tip_title.add_theme_font_size_override("font_size", 22)
	col.add_child(_tip_title)
	_tip_value = Label.new()
	_tip_value.add_theme_font_size_override("font_size", 30)
	_tip_value.add_theme_color_override("font_color", Color(0.95, 0.55, 0.25, 1))
	col.add_child(_tip_value)
	_tip_how = Label.new()
	_tip_how.add_theme_font_size_override("font_size", 14)
	_tip_how.add_theme_color_override("font_color", Color(0.55, 0.5, 0.44, 1))
	_tip_how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_how.custom_minimum_size = Vector2(240, 0)
	col.add_child(_tip_how)


## Opens beside the chips or the card while you look at them, and says what they do.
func _update_tip(delta: float) -> void:
	if _tip == null:
		return
	var t: Dictionary = _targets[_hot] if _hot >= 0 else {}
	var show: bool = _place == "corner" and not t.is_empty() and t["kind"] in ["chips", "card"]
	_tip.modulate.a = move_toward(_tip.modulate.a, 1.0 if show else 0.0, delta * 6.0)
	if not show:
		return
	if t["kind"] == "chips":
		_tip_title.text = "VOLUME"
		_tip_value.text = "%d%%" % roundi(_volume * 100.0)
		_tip_how.text = "More chips, louder. Drag the stack up to add chips, down to take them off."
	else:
		_tip_title.text = "SCREEN"
		_tip_value.text = "Full screen" if _fullscreen else "Window"
		_tip_how.text = "Face up, full screen. Face down, a window. Click to turn the card over."
	var hit: Control = t["hit"]
	var at := hit.position + Vector2(hit.size.x + 24, -10)
	at.x = minf(at.x, size.x - _tip.size.x - 16)
	at.y = clampf(at.y, 16, size.y - _tip.size.y - 60)
	_tip.position = _tip.position.lerp(at, 1.0 - exp(-delta * 18.0)) if _tip.modulate.a > 0.05 else at


# ------------------------------------------------------------------ actions
func _turn(place: String) -> void:
	_place = place
	_hot = -1


func _play() -> void:
	_turn("door")
	_walk = 0.0


func _quit() -> void:
	_blow = 0.0


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_volume = float(cfg.get_value("audio", "volume", 0.8))
	_fullscreen = bool(cfg.get_value("video", "fullscreen", false))


func _save_settings() -> void:
	SettingsScript._apply(_volume, _fullscreen)
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", _volume)
	cfg.set_value("video", "fullscreen", _fullscreen)
	cfg.save(SETTINGS_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _place != "corner":
		return
	var back: bool = (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)
	if back:
		_turn("front")
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if size.x > 0.0:
		var m := get_local_mouse_position() / size * 2.0 - Vector2.ONE
		_gaze = _gaze.lerp(m.clamp(Vector2(-1, -1), Vector2(1, 1)), 1.0 - exp(-delta * 2.5))
	_update_camera(delta)
	_update_lamp(delta)
	_update_corner(delta)
	for i: int in range(_targets.size()):
		var t: Dictionary = _targets[i]
		var here: bool = t["place"] == _place and _walk < 0.0 and _blow < 0.0
		var hot: bool = i == _hot and here
		t["heat"] = move_toward(float(t["heat"]), 1.0 if hot else 0.0, delta * (6.0 if hot else 2.5))
		var l: Label3D = t["label"]
		if l != null:
			l.modulate = CHAR.lerp(SMOULDER, float(t["heat"]))
		_set_outline(t, hot)
		var hit: Control = t["hit"]
		hit.visible = here
		if here:
			if t["kind"] == "word":
				_fit_label(hit, l)
			else:
				_fit_box(hit, t["center"], t["extent"])
	_pick()
	_hint.text = "Press Esc to go back" if _place == "corner" else ""
	_update_tip(delta)


func _target_point(t: Dictionary) -> Vector3:
	if t["kind"] == "word":
		var l: Label3D = t["label"]
		return l.global_transform * l.get_aabb().get_center()
	return t["center"]


func _update_camera(delta: float) -> void:
	var base: Array = VIEW_FRONT
	if _place == "corner":
		base = VIEW_CORNER
	elif _place == "door":
		base = VIEW_DOOR
	var pos: Vector3 = base[0]
	var look: Vector3 = base[1]
	# whatever you look at draws you in
	if _hot >= 0 and _targets[_hot]["place"] == _place and _walk < 0.0:
		var t: Dictionary = _targets[_hot]
		var p := _target_point(t)
		var f: float = t["focus"]
		look = look.lerp(p, 0.75)
		pos = pos.lerp(p + (pos - p).normalized() * 1.1, f)
	var bob := Vector3.ZERO
	if _walk >= 0.0:
		# you walk to the door, it swings open on the moonlit night, you step out
		_walk += delta
		# up to a step from the door (0.5 .. 1.6 s), shove it (1.6 s), then out (1.9 .. 3.4 s)
		var near := DOOR_AT + Vector3(-0.85, 1.6, 0)
		var a := smoothstep(0.5, 1.6, _walk)
		var b := smoothstep(1.9, 3.4, _walk)
		pos = VIEW_DOOR[0].lerp(near, a).lerp(DOOR_AT + Vector3(1.4, 1.6, 0), b)
		look = VIEW_DOOR[1].lerp(DOOR_AT + Vector3(8.0, 1.2, -1.0), smoothstep(1.6, 2.4, _walk))
		var walking := (_walk > 0.5 and _walk < 1.6) or (_walk > 1.9 and _walk < 3.4)
		bob = Vector3(0, -absf(sin(_walk * 5.5)) * 0.045, 0) if walking else Vector3.ZERO
		# you shove it: it flies open, slams against the wall, bounces back a little, settles
		var kick := _walk - 1.6
		var open := 0.0
		if kick > 0.0:
			open = 1.0 - exp(-7.0 * kick) * cos(16.0 * kick)
			bob += Vector3(sin(kick * 60.0), cos(kick * 47.0), 0) * 0.03 * exp(-10.0 * kick)
		_door.rotation.y = -1.7 * open
		_outside_light.light_energy = 1.8 * clampf(open, 0.0, 1.0)
		for c: Node3D in _cracks:
			c.visible = open < 0.05
		if _walk > 3.6:
			_walk = -1.0
			play_requested.emit()
	var k := 1.0 - exp(-delta * 3.5)
	_cam_pos = _cam_pos.lerp(pos, k)
	_cam_look = _cam_look.lerp(look, k)
	# the head follows the mouse a little, and never sits perfectly still
	var right := (_cam_look - _cam_pos).cross(Vector3.UP).normalized()
	var gaze := right * _gaze.x * 0.28 + Vector3.UP * -_gaze.y * 0.16
	var sway := Vector3(sin(_time * 0.37) * 0.02, sin(_time * 0.53) * 0.012, 0)
	_camera.look_at_from_position(_cam_pos + sway + bob, _cam_look + gaze + sway * 0.5)


func _update_lamp(delta: float) -> void:
	var want: Vector3
	if _hot >= 0 and _targets[_hot]["place"] == _place:
		want = _target_point(_targets[_hot]) + Vector3(0, 0.05, 0)
	elif _place == "corner":
		want = TABLE_AT + Vector3(0.05, 0.85, 0.0)
	elif _place == "door":
		want = DOOR_AT + Vector3(-0.05, 1.1, 0.1)
	else:
		want = Vector3(-0.9 + sin(_time * 0.35) * 0.6, 1.4 + sin(_time * 0.23) * 0.7, 0)
	_aim = _aim.lerp(want, 1.0 - exp(-delta * 6.0))
	var to := _aim - PIVOT
	var goal := Vector2(clampf(to.x * 0.08, -0.25, 0.25), 0.0)
	var acc := (goal - _swing) * 10.0 - _swing_v * 2.2
	_swing_v += acc * delta
	_swing += _swing_v * delta
	_swing.x += sin(_time * 0.9) * 0.0006
	_lamp.rotation = Vector3(_swing.y, 0, _swing.x)
	var bulb := _lamp.global_transform * Vector3(0, -CHAIN - 0.12, 0)
	_spot.look_at_from_position(bulb, _aim)
	var flick := 0.92 + 0.08 * sin(_time * 7.3) * sin(_time * 2.9)
	var life := 1.0
	if _blow >= 0.0:
		# blown out, like a real flame: it bends for an instant, then the light is gone at once;
		# only the wick keeps a tiny ember that fades, and a thin wisp of smoke rises
		_blow += delta
		var bend := clampf(_blow / 0.12, 0.0, 1.0)
		life = 1.0 - bend * 0.25 if _blow < 0.12 else 0.0
		_bulb.scale = Vector3(1.0 + bend * 0.5, 1.0 - bend * 0.5, 1.0) if _blow < 0.12 else Vector3(0.25, 0.25, 0.25)
		_bulb.position = Vector3(bend * 0.04, -CHAIN - 0.12, 0)
		if _blow >= 0.12 and not _smoke.emitting:
			_smoke.restart()
			_smoke.emitting = true
		if _blow > 1.8:
			get_tree().quit()
	else:
		_bulb.scale = Vector3.ONE
		_bulb.position = Vector3(0, -CHAIN - 0.12, 0)
	_spot.light_energy = 4.2 * flick * life
	_glow.light_energy = 0.9 * flick * life
	if _blow >= 0.12:
		var ember := clampf(1.0 - (_blow - 0.12) / 0.9, 0.0, 1.0)
		_bulb_mat.albedo_color = Color(0.9, 0.25, 0.05) * ember
	else:
		_bulb_mat.albedo_color = Color(1.0, 0.78, 0.45) * maxf(life, 0.04)


func _update_corner(delta: float) -> void:
	_shutter_open = 0.0
	var e := _shutter_open * _shutter_open * (3.0 - 2.0 * _shutter_open)
	for h: Node3D in _shutters:
		var side: float = h.get_meta("side")
		h.rotation.y = side * lerpf(0.0, 1.5, e)
	_card_flip = move_toward(_card_flip, 0.0 if _fullscreen else 1.0, delta * 3.0)
	var f := _card_flip * _card_flip * (3.0 - 2.0 * _card_flip)
	_card.rotation.z = f * PI
	_card.position = CARD_AT + Vector3(0, sin(f * PI) * 0.08 + (0.002 if f > 0.5 else 0.0), 0)
	for k: int in range(_chips.size()):
		_chip_drop[k] = move_toward(_chip_drop[k], 0.0, delta * 0.6)
		_chips[k].position = CHIPS_AT + Vector3(sin(k * 2.3) * 0.004, CHIP_H * (k + 0.5) + _chip_drop[k], cos(k * 1.7) * 0.004)
	if _lantern != null:
		_lantern.light_energy = 1.3 * (0.85 + 0.15 * sin(_time * 8.3) * sin(_time * 3.1))
	if _far_fire != null:
		_far_fire.light_energy = 0.9 * (0.7 + 0.3 * sin(_time * 5.7) * sin(_time * 2.3))
	var leak := 0.8 + 0.1 * sin(_time * 0.7)
	_crack_mat.albedo_color = Color(0.6, 0.72, 0.95) * leak


# ------------------------------------------------------------------ hit areas over 3D things
func _fit_label(hit: Control, l: Label3D) -> void:
	var aabb := l.get_aabb()
	var pts: Array[Vector3] = []
	for k: int in range(8):
		pts.append(l.global_transform * aabb.get_endpoint(k))
	_fit(hit, pts, Vector2(12, 8))


func _fit_box(hit: Control, center: Vector3, extent: Vector3) -> void:
	var pts: Array[Vector3] = []
	for k: int in range(8):
		pts.append(center + Vector3(extent.x * (0.5 if k & 1 else -0.5), extent.y * (0.5 if k & 2 else -0.5), extent.z * (0.5 if k & 4 else -0.5)))
	_fit(hit, pts, Vector2(6, 6))


func _fit(hit: Control, pts: Array[Vector3], pad: Vector2) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in pts:
		if _camera.is_position_behind(p):
			hit.visible = false
			return
		var s := _camera.unproject_position(p) * PIXEL_SHRINK
		lo = lo.min(s)
		hi = hi.max(s)
	hit.position = lo - pad
	hit.size = hi - lo + pad * 2.0
