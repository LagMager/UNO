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
	_apply_styles()


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
