class_name StatsHUD
extends SubViewportContainer

## What you carry, drawn as things of the world and put through the game's pixel dither
## (half resolution, the same Bayer finish as the 3D):
## - LIFE is a cartridge belt: one bullet per point, empty loops where you lost them;
## - TEARS (the run's currency, the world design doc's "lágrimas") glow in a small glass vial;
## - DECK is a worn stack of cards (click it to see your deck).
## Each has its name and its number. A hit makes the belt flinch red; tears make the vial glint.

signal deck_clicked

const SHRINK := 2
const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const BONE := Color(0.84, 0.78, 0.66, 1)
const ASH := Color(0.55, 0.5, 0.44, 1)
const INK := Color(0.03, 0.022, 0.02, 1)
const LEATHER := Color(0.3, 0.17, 0.09, 1)
const LEATHER_DARK := Color(0.16, 0.09, 0.05, 1)
const BRASS := Color(0.78, 0.6, 0.28, 1)
const LEAD := Color(0.5, 0.5, 0.52, 1)
const HURT := Color(1.0, 0.3, 0.18, 1)
const TEAR := Color(0.68, 0.84, 1.0, 1)

var health := 20
var max_health := 20
var tears := 0
var deck := 0
var _hurt_flash := 0.0
var _tear_flash := 0.0
var _time := 0.0
var _canvas: Control
var _deck_rect := Rect2()


func _init() -> void:
	custom_minimum_size = Vector2(700, 52)
	stretch = true
	stretch_shrink = SHRINK
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dither := ShaderMaterial.new()
	dither.shader = preload("res://resources/shaders/pixel_dither.gdshader")
	dither.set_shader_parameter("levels", 12.0)
	material = dither
	var vp := SubViewport.new()
	vp.transparent_bg = true
	add_child(vp)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_paint)
	vp.add_child(_canvas)


func set_values(hp: int, max_hp: int, gold: int, deck_size: int) -> void:
	if hp < health:
		_hurt_flash = 1.0
	if gold > tears:
		_tear_flash = 1.0
	health = maxi(hp, 0)
	max_health = maxi(max_hp, 1)
	tears = gold
	deck = deck_size


func _process(delta: float) -> void:
	_time += delta
	_hurt_flash = maxf(_hurt_flash - delta * 1.4, 0.0)
	_tear_flash = maxf(_tear_flash - delta * 1.4, 0.0)
	if _canvas != null:
		_canvas.size = size / SHRINK
		_canvas.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _deck_rect.has_point(event.position / SHRINK):
			deck_clicked.emit()
			accept_event()


# ------------------------------------------------------------------ painting (half resolution)
func _paint() -> void:
	var c := _canvas
	var h := c.size.y
	var y := h * 0.5
	var x := 4.0
	# ---- LIFE: a cartridge belt
	x += _text(c, Vector2(x, y), "LIFE", ASH, 9) + 5.0
	var shake := Vector2(sin(_time * 60.0) * 1.5 * _hurt_flash, 0)
	var loops := max_health
	var belt := Rect2(Vector2(x, y - 6) + shake, Vector2(loops * 6.0 + 6.0, 13))
	c.draw_rect(belt.grow(1), INK)
	c.draw_rect(belt, LEATHER.lerp(HURT, _hurt_flash * 0.35))
	c.draw_rect(Rect2(belt.position + Vector2(0, belt.size.y - 3), Vector2(belt.size.x, 3)), LEATHER_DARK)
	for k: int in range(int(belt.size.x / 4.0)):
		c.draw_rect(Rect2(belt.position + Vector2(2 + k * 4, 1), Vector2(2, 1)), LEATHER_DARK)    # stitching
	for i: int in range(loops):
		var bx := belt.position.x + 4.0 + i * 6.0
		var loop := Rect2(bx - 1, y - 4, 6, 9)
		c.draw_rect(_moved(loop, shake), LEATHER_DARK)
		if i < health:
			# a bullet sitting in its loop: brass casing, lead tip poking out above the belt
			c.draw_rect(_moved(Rect2(bx, y - 10, 4, 12), shake), BRASS)
			c.draw_rect(_moved(Rect2(bx, y - 10, 1, 12), shake), BRASS.lightened(0.35))
			c.draw_rect(_moved(Rect2(bx, y - 13, 4, 3), shake), LEAD)
			c.draw_rect(_moved(Rect2(bx + 1, y - 14, 2, 1), shake), LEAD)
		else:
			c.draw_rect(_moved(Rect2(bx + 1, y - 3, 2, 5), shake), INK)     # an empty loop
	x = belt.end.x + 6.0
	x += _text(c, Vector2(x, y), "%d/%d" % [health, max_health], BONE.lerp(HURT, _hurt_flash), 11) + 16.0
	# ---- TEARS: a small glass vial with a faint light in it
	x += _text(c, Vector2(x, y), "TEARS", ASH, 9) + 5.0
	var vial := Rect2(x, y - 9, 8, 17)
	var glow := TEAR
	glow.a = 0.18 + 0.08 * sin(_time * 1.7) + _tear_flash * 0.4
	c.draw_circle(vial.get_center() + Vector2(0, 2), 9.0, glow)
	c.draw_rect(Rect2(vial.position + Vector2(2, -3), Vector2(4, 3)), LEATHER)            # the cork
	c.draw_rect(vial.grow(1), INK)
	c.draw_rect(vial, Color(0.12, 0.14, 0.17, 1))
	var level := 0.35 + 0.55 * clampf(tears / 100.0, 0.0, 1.0)
	var liquid := Rect2(vial.position.x, vial.end.y - vial.size.y * level, vial.size.x, vial.size.y * level)
	c.draw_rect(liquid, TEAR.lerp(Color.WHITE, _tear_flash * 0.5).darkened(0.15))
	c.draw_rect(Rect2(liquid.position, Vector2(liquid.size.x, 1)), Color(1, 1, 1, 0.7))
	c.draw_rect(Rect2(vial.position + Vector2(1, 2), Vector2(1, vial.size.y - 4)), Color(1, 1, 1, 0.25))   # glass shine
	x = vial.end.x + 6.0
	x += _text(c, Vector2(x, y), "%d" % tears, BONE, 11) + 16.0
	# ---- DECK: a worn stack of cards
	var start := x
	x += _text(c, Vector2(x, y), "DECK", ASH, 9) + 5.0
	for k: int in range(3):
		var card := Rect2(x + k * 2.0, y - 9 - k * 1.0, 10, 15)
		c.draw_rect(card.grow(1), INK)
		c.draw_rect(card, Color(0.3, 0.21, 0.16, 1))
		c.draw_rect(card.grow(-2), Color(0.45, 0.12, 0.07, 1), false, 1.0)
	x += 18.0
	x += _text(c, Vector2(x, y), "%d" % deck, BONE, 11)
	_deck_rect = Rect2(start - 2, 0, x - start + 4, h)


func _text(c: Control, at: Vector2, s: String, col: Color, fs: int) -> float:
	var p := Vector2(at.x, at.y + fs * 0.36)
	c.draw_string_outline(FONT, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, INK)
	c.draw_string(FONT, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _moved(r: Rect2, by: Vector2) -> Rect2:
	return Rect2(r.position + by, r.size)
