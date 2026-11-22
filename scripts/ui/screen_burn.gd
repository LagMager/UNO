class_name ScreenBurn
extends CanvasLayer

## The change between screens: a still of the old screen is laid on top and burns away
## (burn_transition.gdshader), revealing the new one underneath. Call burn() right before
## swapping what is visible; it takes the still from the last drawn frame.

const DURATION := 2.2

var _rect: TextureRect
var _mat: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	layer = 50
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# the still is window-sized: it must fit the screen, not push the rect to its own size (that was the zoom)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.visible = false
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://resources/shaders/burn_transition.gdshader")
	_rect.material = _mat
	add_child(_rect)


func burn() -> void:
	if DisplayServer.get_name() == "headless":
		return    # nothing is drawn there, there is no still to burn
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	var tex := ImageTexture.create_from_image(img)
	_rect.texture = tex
	_mat.set_shader_parameter("old_screen", tex)
	_mat.set_shader_parameter("seed", Vector2(randf() * 50.0, randf() * 50.0))
	_mat.set_shader_parameter("aspect", float(img.get_width()) / maxf(img.get_height(), 1.0))
	_mat.set_shader_parameter("progress", 0.0)
	_rect.visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("progress", v), 0.0, 1.0, DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func() -> void: _rect.visible = false)
