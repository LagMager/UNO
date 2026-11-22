class_name MapPortrait
extends SubViewportContainer

## A small live "photo" for the map's details panel: who (or what) waits at a place, its 3D
## model in its idle animation, lit from one side, through the game's pixel dither.
## show_kind("tahur" | "gila" | "bunny" | "fire" | "").

const MODELS := {
	"tahur": preload("res://assets/models/rival.glb"),
	"gila": preload("res://assets/models/yorkie.glb"),
	"bunny": preload("res://assets/models/bunny.glb"),
	"fire": preload("res://assets/models/zones/rest_point/rp_campfire.glb"),
}

var _vp: SubViewport
var _world: Node3D
var _camera: Camera3D
var _model: Node3D
var _kind := ""
var _time := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(380, 170)
	stretch = true
	stretch_shrink = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dither := ShaderMaterial.new()
	dither.shader = preload("res://resources/shaders/pixel_dither.gdshader")
	material = dither
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0b0807")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6b5a50")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_world.add_child(_camera)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffc48a")
	key.light_energy = 1.4
	key.rotation_degrees = Vector3(-25, 35, 0)
	_world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#8aa0d0")
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(-15, -150, 0)
	_world.add_child(rim)


func show_kind(kind: String) -> void:
	visible = MODELS.has(kind)
	if kind == _kind or not visible:
		return
	_kind = kind
	if _model != null:
		_model.queue_free()
	_model = (MODELS[kind] as PackedScene).instantiate() as Node3D
	_world.add_child(_model)
	# frame it: characters from the chest up, things whole
	var box := AABB()
	var first := true
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var focus := box.get_center()
	var reach := box.size.length() * 0.9
	if kind != "fire":
		focus = box.position + Vector3(box.size.x * 0.5, box.size.y * 0.78, box.size.z * 0.5)
		reach = box.size.y * 0.75
	_camera.look_at_from_position(focus + Vector3(0.15, 0.05, 1.0).normalized() * (reach * 2.2 + 0.3), focus)
	for node in _model.find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		for n: String in ap.get_animation_list():
			if n == "idle" or n.ends_with("/idle"):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
				ap.play(n)
				break
