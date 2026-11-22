class_name MapNodeView
extends Button

## Visual button widget representing one MapNodeData in the MapView DAG.

signal node_clicked(node_id: String)

enum VisualState {
	LOCKED,
	DISCOVERED,
	REACHABLE,
	CURRENT,
	COMPLETED,
}

var node_id: String = ""
var node_type: MapEnums.NodeType = MapEnums.NodeType.ENCOUNTER
var visual_state: VisualState = VisualState.LOCKED

@onready var badge_label: Label = $Margin/Column/BadgeLabel
@onready var title_label: Label = $Margin/Column/TitleLabel
@onready var state_label: Label = $Margin/Column/StateLabel


func _ready() -> void:
	pressed.connect(_on_pressed)
	_style_as_ink()


func setup_node(node_data: MapNodeData, state: VisualState) -> void:
	if node_data == null:
		return
	node_id = node_data.id
	node_type = node_data.node_type
	visual_state = state

	var symbol: String = _type_symbol(node_type)
	var type_text: String = MapEnums.node_type_to_string(node_type)
	badge_label.text = "%s %s" % [symbol, type_text.to_upper()]

	var content_title: String = node_data.content.display_name if node_data.content != null and not node_data.content.display_name.is_empty() else type_text
	title_label.text = content_title

	match visual_state:
		VisualState.COMPLETED:
			state_label.text = "COMPLETED"
			disabled = true
		VisualState.CURRENT:
			state_label.text = "CURRENT"
			disabled = true
		VisualState.REACHABLE:
			state_label.text = "SELECTABLE"
			disabled = false
		VisualState.DISCOVERED:
			state_label.text = "AHEAD"
			disabled = true
		_:
			state_label.text = "LOCKED"
			disabled = true

	tooltip_text = "%s (%s)\n%s" % [
		content_title,
		type_text,
		node_data.content.description if node_data.content != null else ""
	]
	queue_redraw()


func _apply_styles() -> void:
	var accent: Color = _type_accent_color(node_type)
	var bg_color := Color("#262626")
	var border_color := accent.darkened(0.35)
	var border_width := 2

	match visual_state:
		VisualState.REACHABLE:
			bg_color = accent.darkened(0.58)
			border_color = accent.lightened(0.25)
			border_width = 3
		VisualState.CURRENT:
			bg_color = Color("#3a3520")
			border_color = Color("#ffd166")
			border_width = 3
		VisualState.COMPLETED:
			bg_color = Color("#1d2820")
			border_color = Color("#52b788")
			border_width = 2
		VisualState.DISCOVERED:
			bg_color = Color("#242428")
			border_color = accent.darkened(0.25)
			border_width = 2
		VisualState.LOCKED:
			bg_color = Color("#1a1a1d")
			border_color = Color("#3d3d42")
			border_width = 1

	var normal_box := _make_box(bg_color, border_color, border_width)
	var hover_box := _make_box(bg_color.lightened(0.12), border_color.lightened(0.2), border_width)
	var pressed_box := _make_box(bg_color.lightened(0.2), Color.WHITE, border_width)
	var disabled_box := _make_box(bg_color, border_color, border_width)

	add_theme_stylebox_override("normal", normal_box)
	add_theme_stylebox_override("hover", hover_box)
	add_theme_stylebox_override("pressed", pressed_box)
	add_theme_stylebox_override("disabled", disabled_box)
	badge_label.add_theme_color_override("font_color", accent.lightened(0.25))


func _make_box(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	return style


static func _type_symbol(t: MapEnums.NodeType) -> String:
	match t:
		MapEnums.NodeType.ENCOUNTER:
			return "[⚔]"
		MapEnums.NodeType.DECISION:
			return "[?]"
		MapEnums.NodeType.SHOP:
			return "[$]"
		MapEnums.NodeType.SAFE_ROOM:
			return "[+]"
		MapEnums.NodeType.ELITE:
			return "[!]"
		MapEnums.NodeType.BOSS:
			return "[★]"
		_:
			return "[·]"


static func _type_accent_color(t: MapEnums.NodeType) -> Color:
	match t:
		MapEnums.NodeType.ENCOUNTER:
			return Color("#e07a5f")
		MapEnums.NodeType.DECISION:
			return Color("#81b29a")
		MapEnums.NodeType.SHOP:
			return Color("#f2cc8f")
		MapEnums.NodeType.SAFE_ROOM:
			return Color("#64dfdf")
		MapEnums.NodeType.ELITE:
			return Color("#c77dff")
		MapEnums.NodeType.BOSS:
			return Color("#ef476f")
		_:
			return Color("#999999")


func _on_pressed() -> void:
	if not disabled and not node_id.is_empty():
		node_clicked.emit(node_id)


# ------------------------------------------------------------------ ink drawing
## The node is drawn, not boxed: an inked medallion with a small picture of what waits there
## (a shot-through card for a fight, a campfire for a safe room, a coin for the shop, a skull
## for an elite, a horned hat for the boss), and its name in small type under it.
## Reachable nodes glow like embers; finished ones are crossed out.
const INK := Color(0.07, 0.05, 0.045, 1)
const BONE := Color(0.8, 0.75, 0.64, 1)
const EMBER := Color(0.85, 0.32, 0.1, 1)
const BLOOD := Color(0.5, 0.1, 0.07, 1)
const ICON_R := 20.0

var _time := 0.0
var _hover := false


func _style_as_ink() -> void:
	var empty := StyleBoxEmpty.new()
	for s: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, empty)
	$Margin.visible = false
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(func() -> void: _hover = true)
	mouse_exited.connect(func() -> void: _hover = false)


func _process(delta: float) -> void:
	_time += delta
	if visual_state == VisualState.REACHABLE or visual_state == VisualState.CURRENT or _hover:
		queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, ICON_R + 4.0)
	var ink := BONE
	var alpha := 1.0
	match visual_state:
		VisualState.LOCKED:
			alpha = 0.32
		VisualState.DISCOVERED:
			alpha = 0.55
		VisualState.COMPLETED:
			alpha = 0.45
	ink.a = alpha
	# ember glow under reachable nodes, breathing slowly
	if visual_state == VisualState.REACHABLE or visual_state == VisualState.CURRENT:
		var pulse := 0.55 + 0.45 * sin(_time * 2.2)
		for i: int in range(4):
			var g := EMBER
			g.a = (0.10 + 0.08 * pulse) * (1.0 - i / 4.0)
			draw_circle(c, ICON_R + 6.0 + i * 5.0 + (3.0 if _hover else 0.0), g)
	# the medallion: dark disk, ragged inked rim
	var disk := Color(0.09, 0.07, 0.06, 0.92)
	if visual_state == VisualState.CURRENT:
		disk = Color(0.3, 0.08, 0.04, 0.95)
	draw_circle(c, ICON_R, disk)
	var rim := EMBER if visual_state == VisualState.REACHABLE else ink
	if _hover and not disabled:
		rim = Color(1.0, 0.62, 0.3, 1)
	_ragged_ring(c, ICON_R, rim, 2.5)
	_ragged_ring(c, ICON_R - 4.0, Color(rim.r, rim.g, rim.b, rim.a * 0.35), 1.0)
	_draw_icon(c, ink if visual_state != VisualState.REACHABLE else BONE)
	if visual_state == VisualState.COMPLETED:
		# crossed out in dried blood
		draw_line(c + Vector2(-20, -18), c + Vector2(20, 18), BLOOD, 4.0)
		draw_line(c + Vector2(20, -18), c + Vector2(-20, 18), BLOOD, 4.0)
	# the name, small, under the medallion
	var font := get_theme_default_font()
	var name_col := BONE
	# names only where they matter: where you can go, where you are, and under the mouse
	if not (visual_state == VisualState.REACHABLE or visual_state == VisualState.CURRENT or _hover):
		return
	name_col.a = 1.0
	var label := title_label.text
	var fs := 13
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var pos := Vector2(c.x - w * 0.5, c.y + ICON_R + 18.0)
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, INK)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, name_col)


func _ragged_ring(c: Vector2, r: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var n := 40
	var seed := float(hash(node_id) % 1000)
	for i: int in range(n + 1):
		var a := TAU * i / n
		var wob := sin(a * 7.0 + seed) * 0.8 + sin(a * 13.0 + seed * 2.0) * 0.5
		pts.append(c + Vector2(cos(a), sin(a)) * (r + wob))
	draw_polyline(pts, col, width)


func _draw_icon(c: Vector2, col: Color) -> void:
	match node_type:
		MapEnums.NodeType.ENCOUNTER:
			# a playing card, tilted, shot through
			var tilt := Transform2D(-0.22, c)
			draw_set_transform_matrix(tilt)
			draw_rect(Rect2(-9, -13, 18, 26), col, false, 2.0)
			draw_circle(Vector2(2, -2), 3.2, col)
			draw_line(Vector2(2, -2), Vector2(7, -7), col, 1.2)
			draw_line(Vector2(2, -2), Vector2(-3, 4), col, 1.2)
			draw_set_transform_matrix(Transform2D())
		MapEnums.NodeType.ELITE:
			# a skull
			draw_circle(c + Vector2(0, -3), 10.0, col)
			draw_rect(Rect2(c + Vector2(-6, 4), Vector2(12, 7)), col)
			var hole := Color(0.09, 0.07, 0.06, 1)
			draw_circle(c + Vector2(-4, -3), 3.0, hole)
			draw_circle(c + Vector2(4, -3), 3.0, hole)
			draw_line(c + Vector2(-3, 8), c + Vector2(-3, 11), hole, 1.5)
			draw_line(c + Vector2(0, 8), c + Vector2(0, 11), hole, 1.5)
			draw_line(c + Vector2(3, 8), c + Vector2(3, 11), hole, 1.5)
		MapEnums.NodeType.SAFE_ROOM:
			# a campfire: two crossed logs and a flame
			draw_line(c + Vector2(-11, 10), c + Vector2(11, 4), col, 3.0)
			draw_line(c + Vector2(-11, 4), c + Vector2(11, 10), col, 3.0)
			var flame := PackedVector2Array([c + Vector2(0, -14), c + Vector2(6, -2), c + Vector2(4, 5),
				c + Vector2(0, 2), c + Vector2(-4, 5), c + Vector2(-6, -2)])
			draw_colored_polygon(flame, col)
		MapEnums.NodeType.SHOP:
			# a coin with a notched rim
			_ragged_ring(c, 10.0, col, 2.5)
			draw_circle(c, 6.5, col)
			draw_line(c + Vector2(0, -4), c + Vector2(0, 4), Color(0.09, 0.07, 0.06, 1), 2.0)
		MapEnums.NodeType.BOSS:
			# a wide-brim hat with horns
			draw_line(c + Vector2(-15, 6), c + Vector2(15, 6), col, 3.0)
			draw_rect(Rect2(c + Vector2(-7, -6), Vector2(14, 12)), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -4), c + Vector2(-14, -16), c + Vector2(-4, -6)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(7, -4), c + Vector2(14, -16), c + Vector2(4, -6)]), col)
		_:
			# a decision: a fork in the trail
			draw_line(c + Vector2(0, 12), c + Vector2(0, 0), col, 2.5)
			draw_line(c + Vector2(0, 0), c + Vector2(-9, -11), col, 2.5)
			draw_line(c + Vector2(0, 0), c + Vector2(9, -11), col, 2.5)
