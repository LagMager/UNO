class_name MapView
extends MarginContainer

## Map presentation screen.
## Displays the generated DAG, highlights reachable nodes, blocks unreachable selections,
## and emits signals to the progression controller.

signal node_selected(node_id: String)
signal deck_requested
signal mode_select_requested
signal restart_run_requested

var _run_state: RunState = null

@onready var title_label: Label = $Column/Header/TitleLabel
@onready var stats_label: Label = $Column/Header/StatsLabel
@onready var seed_label: Label = $Column/Header/SeedLabel
@onready var status_banner: Label = $Column/StatusBanner
@onready var scroll_container: ScrollContainer = $Column/MapPanel/ScrollContainer
@onready var graph_canvas: MapGraphCanvas = $Column/MapPanel/ScrollContainer/GraphCanvas
@onready var restart_button: Button = $Column/Footer/RestartRunButton
@onready var deck_button: Button = $Column/Footer/DeckButton
@onready var choose_mode_button: Button = $Column/Footer/ChooseModeButton
@onready var hint_label: Label = $Column/Footer/HintLabel


func _ready() -> void:
	_dress_as_old_map()
	graph_canvas.node_clicked.connect(_on_node_clicked)
	restart_button.pressed.connect(func() -> void: restart_run_requested.emit())
	deck_button.pressed.connect(func() -> void: deck_requested.emit())
	choose_mode_button.pressed.connect(func() -> void: mode_select_requested.emit())
	if _run_state != null:
		render_map(_run_state)


func bind_run_state(run_state: RunState) -> void:
	if _run_state != null and _run_state.state_changed.is_connected(_on_run_state_changed):
		_run_state.state_changed.disconnect(_on_run_state_changed)
	_run_state = run_state
	if _run_state != null and not _run_state.state_changed.is_connected(_on_run_state_changed):
		_run_state.state_changed.connect(_on_run_state_changed)
	if is_node_ready():
		render_map(_run_state)


func render_map(run_state: RunState = _run_state) -> void:
	_run_state = run_state
	if not is_node_ready() or _run_state == null:
		return

	stats_label.text = "HP: %d / %d  |  Gold: %d" % [
		maxi(_run_state.current_health, 0),
		_run_state.max_health,
		_run_state.gold
	]
	var seed_val: int = _run_state.map_data.generation_seed if _run_state.map_data != null else 0
	seed_label.text = "Seed: %d" % seed_val
	deck_button.text = "Deck (%d)" % _run_state.player_deck.size()
	if hud != null and not hud.deck_clicked.is_connected(_on_hud_deck):
		hud.deck_clicked.connect(_on_hud_deck)
	if hud != null:
		hud.set_values(_run_state.current_health, _run_state.max_health, _run_state.gold, _run_state.player_deck.size())

	if _run_state.run_finished:
		if _run_state.run_victory:
			status_banner.text = "RUN COMPLETE — BOSS DEFEATED!"
			status_banner.add_theme_color_override("font_color", Color(0.8, 0.75, 0.64, 1))
		else:
			status_banner.text = "RUN ENDED — DEFEAT"
			status_banner.add_theme_color_override("font_color", Color(0.6, 0.14, 0.08, 1))
	else:
		var reachable: PackedStringArray = _run_state.get_reachable_node_ids()
		status_banner.text = "Choose where to go next (%d)" % reachable.size()
		status_banner.add_theme_color_override("font_color", Color(0.85, 0.42, 0.18, 1))

	graph_canvas.render_graph(_run_state)
	_after_render()


func request_select_node(node_id: String) -> bool:
	if _run_state == null or not _run_state.can_select_node(node_id):
		return false
	node_selected.emit(node_id)
	return true


func get_node_view(node_id: String) -> MapNodeView:
	return graph_canvas.get_node_view(node_id)


func _on_run_state_changed() -> void:
	render_map(_run_state)


## The circles of Hell (RingMap) behind the trails instead of a flat grey panel,
## and the header in the game's ink colors.
func _dress_as_old_map() -> void:
	var panel := $Column/MapPanel as PanelContainer
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# the circles of Hell, in 3D (the ink ring map laid on stepped terraces), behind the trail
	inferno = Inferno3DScript.new()
	inferno.name = "Inferno"
	panel.add_child(inferno)
	panel.move_child(inferno, 0)
	graph_canvas.layout = inferno
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS
	graph_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	graph_canvas.clip_contents = true
	graph_canvas.node_hovered.connect(_on_node_hovered)
	graph_canvas.gui_input.connect(_on_map_input)
	# the buttons under the map go: the deck opens from its icon above, Esc pauses
	$Column/Footer.visible = false
	_build_info(panel)
	_build_details(panel)
	_build_debug_tools()
	title_label.text = "The Descent"
	# the header floats over the map (it was a black band above it)
	var info_layer := panel.get_node("Info") as Control
	var header := $Column/Header as Control
	var banner := $Column/StatusBanner as Control
	header.reparent(info_layer, false)
	banner.reparent(info_layer, false)
	header.position = Vector2(24, 14)
	banner.position = Vector2(26, 66)
	($Column as VBoxContainer).add_theme_constant_override("separation", 0)
	# life, tears and deck drawn, not written
	stats_label.visible = false
	hud = StatsHUDScript.new()
	header.add_child(hud)
	header.move_child(hud, stats_label.get_index())
	seed_label.visible = false   # the seed lives in the pause menu (Esc), where it can be copied
	choose_mode_button.text = "Leave"
	hint_label.visible = false   # the medallions say what each place is


# ------------------------------------------------------------------ the funnel and what it says
const Inferno3DScript = preload("res://scripts/map/ui/inferno_3d.gd")
const StatsHUDScript = preload("res://scripts/ui/stats_hud.gd")
var hud: StatsHUDScript
const BONE := Color(0.8, 0.75, 0.64, 1)
const ASH := Color(0.55, 0.5, 0.43, 1)
const EMBER_TXT := Color(0.85, 0.42, 0.18, 1)
const TYPE_WORDS := {
	MapEnums.NodeType.ENCOUNTER: ["A fight", "A sinner blocks the trail. Win and the way opens."],
	MapEnums.NodeType.ELITE: ["A stronger fight", "Something worse than a sinner. Harder, and it pays better."],
	MapEnums.NodeType.DECISION: ["A crossroads", "Something happens here. You will have to choose."],
	MapEnums.NodeType.SHOP: ["A trader", "Spend what you carry on cards or a drink."],
	MapEnums.NodeType.SAFE_ROOM: ["A rest point", "A fire under the stars. Rest, or work on a card."],
	MapEnums.NodeType.BOSS: ["The last hand", "The one who waits at the bottom of the pit."],
}

var inferno: Inferno3DScript
var _zone_title: Label
var _zone_line: Label
var _node_title: Label
var _node_kind: Label
var _node_line: Label


func _build_info(panel: Control) -> void:
	var info := Control.new()
	info.name = "Info"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(info)
	var zone := VBoxContainer.new()
	zone.position = Vector2(24, 100)
	zone.custom_minimum_size = Vector2(420, 0)
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(zone)
	_zone_title = _info_label(30, BONE, true)
	_zone_line = _info_label(16, ASH, false)
	_zone_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_line.custom_minimum_size = Vector2(400, 0)
	zone.add_child(_zone_title)
	zone.add_child(_zone_line)
	var node := VBoxContainer.new()
	node.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	node.offset_left = 24
	node.offset_top = -120
	node.offset_right = 460
	node.offset_bottom = -16
	node.alignment = BoxContainer.ALIGNMENT_END
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(node)
	_node_kind = _info_label(15, EMBER_TXT, false)
	_node_title = _info_label(22, BONE, true)
	_node_line = _info_label(15, ASH, false)
	_node_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_node_line.custom_minimum_size = Vector2(420, 0)
	node.add_child(_node_kind)
	node.add_child(_node_title)
	node.add_child(_node_line)
	_on_node_hovered("")


func _info_label(size: int, col: Color, header: bool) -> Label:
	var l := Label.new()
	if header:
		l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## After each render: name the circle you are in, and turn the eye toward where you can go.
func _after_render() -> void:
	if inferno == null or _run_state == null:
		return
	var reachable := _run_state.get_reachable_node_ids()
	inferno.focus_on(graph_canvas.world_points(reachable))
	var fl := 0
	if not reachable.is_empty():
		fl = graph_canvas.floor_of(reachable[0])
	elif not _run_state.current_node_id.is_empty():
		fl = graph_canvas.floor_of(_run_state.current_node_id)
	var zone_now := inferno.zone_of_floor(maxi(fl, 0))
	if _debug_box != null:
		_debug_box.visible = debug_tools
		_debug_zone = zone_now if zone_now >= 0 else 99
	if _shown_zone != -2 and zone_now != _shown_zone and visible:
		_descend(_shown_zone, zone_now)
	else:
		inferno.set_current_zone(zone_now)
		graph_canvas.show_only(func(floor_index: int) -> bool: return inferno.zone_of_floor(floor_index) == zone_now)
	_shown_zone = zone_now
	var z := inferno.zone_info(zone_now)
	_zone_title.text = z["name"]
	_zone_line.text = z["line"]


func _on_node_hovered(id: String) -> void:
	if _node_title == null:
		return
	var node_data: MapNodeData = null
	if _run_state != null and _run_state.map_data != null and not id.is_empty():
		node_data = _run_state.map_data.get_node(id)
	if node_data == null:
		_node_kind.text = ""
		_node_title.text = ""
		_node_line.text = "Embers mark where you can go."
		return
	var words: Array = TYPE_WORDS.get(node_data.node_type, ["", ""])
	var zone := inferno.zone_info(inferno.zone_of_floor(node_data.floor_index))
	_node_kind.text = "%s  ·  %s" % [words[0], zone["name"]]
	_node_title.text = node_data.content.display_name if node_data.content != null and not node_data.content.display_name.is_empty() else words[0]
	var extra: String = node_data.content.description if node_data.content != null else ""
	_node_line.text = extra if not extra.is_empty() else words[1]


# ------------------------------------------------------------------ a closer look at one place
var _details: PanelContainer
var _d_zone: Label
var _d_zone_line: Label
var _d_kind: Label
var _d_title: Label
var _d_line: Label
var _d_go: Button
var _picked := ""


func _build_details(panel: Control) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(holder)
	_details = PanelContainer.new()
	_details.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_details.offset_left = -440
	_details.offset_top = -250
	_details.offset_right = -24
	_details.offset_bottom = 250
	_details.visible = false
	holder.add_child(_details)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_details.add_child(col)
	_portrait = MapPortraitScript.new()
	col.add_child(_portrait)
	_d_zone = _info_label(26, BONE, true)
	_d_zone_line = _info_label(15, ASH, false)
	_d_zone_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_zone_line.custom_minimum_size = Vector2(380, 0)
	var rule := ColorRect.new()
	rule.color = Color(0.42, 0.11, 0.06, 0.8)
	rule.custom_minimum_size = Vector2(0, 2)
	_d_kind = _info_label(15, EMBER_TXT, false)
	_d_title = _info_label(22, BONE, true)
	_d_line = _info_label(15, ASH, false)
	_d_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_line.custom_minimum_size = Vector2(380, 0)
	for n: Control in [_d_zone, _d_zone_line, rule, _d_kind, _d_title, _d_line]:
		col.add_child(n)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_d_go = Button.new()
	_d_go.text = "Go"
	_d_go.custom_minimum_size = Vector2(130, 42)
	_d_go.focus_mode = Control.FOCUS_NONE
	_d_go.pressed.connect(func() -> void:
		var id := _picked
		_close_details()
		request_select_node(id))
	row.add_child(_d_go)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(130, 42)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_close_details)
	row.add_child(back)


## A click on a place: the eye goes down to it and the panel says what it is.
## Only "Go" takes you there.
func _on_node_clicked(id: String) -> void:
	if inferno == null or _run_state == null or _run_state.map_data == null:
		request_select_node(id)
		return
	var node_data: MapNodeData = _run_state.map_data.get_node(id)
	if node_data == null:
		return
	_picked = id
	# the eye goes down to the place; the panel shows who or what waits there
	var pts := graph_canvas.world_points(PackedStringArray([id]))
	if not pts.is_empty():
		inferno.zoom_to(pts[0])
	_portrait.show_kind(_portrait_kind(node_data))
	var zone := inferno.zone_info(inferno.zone_of_floor(node_data.floor_index))
	var words: Array = TYPE_WORDS.get(node_data.node_type, ["", ""])
	_d_zone.text = zone["name"]
	_d_zone_line.text = zone["line"]
	_d_kind.text = words[0]
	_d_title.text = node_data.content.display_name if node_data.content != null and not node_data.content.display_name.is_empty() else words[0]
	var extra: String = node_data.content.description if node_data.content != null else ""
	_d_line.text = (extra + "\n" if not extra.is_empty() else "") + words[1]
	_d_go.disabled = not _run_state.can_select_node(id)
	_details.visible = true
	_details.modulate.a = 0.0
	create_tween().tween_property(_details, "modulate:a", 1.0, 0.35).set_delay(0.3)


func _close_details() -> void:
	_picked = ""
	if inferno != null:
		inferno.zoom_out()
	if _details != null:
		_details.visible = false


func _on_hud_deck() -> void:
	deck_requested.emit()


var _dragging := false
var _drag_moved := 0.0


## Drag the map to look around it, wheel to zoom.
func _on_map_input(event: InputEvent) -> void:
	if inferno == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_moved = 0.0
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			inferno.zoom_by(1.12, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inferno.zoom_by(1.0 / 1.12, mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		inferno.pan(mm.relative)


func get_seed() -> int:
	return _run_state.map_data.generation_seed if _run_state != null and _run_state.map_data != null else 0


# ------------------------------------------------------------------ the photo in the details
const MapPortraitScript = preload("res://scripts/map/ui/portrait.gd")
var _portrait: MapPortraitScript


## Who or what the photo shows for a place: the rival of a fight (the Aggressor is the
## lizard, the rest the card sharp, as at the table), the shopkeeper, the rest point's fire.
func _portrait_kind(node_data: MapNodeData) -> String:
	match node_data.node_type:
		MapEnums.NodeType.SHOP:
			return "bunny"
		MapEnums.NodeType.SAFE_ROOM:
			return "fire"
		MapEnums.NodeType.DECISION:
			return ""
	var enc := node_data.content as EncounterData
	if enc != null and enc.enemy_profile_id == "aggressor":
		return "gila"
	return "tahur"


# ------------------------------------------------------------------ debug: walk the circles freely
## Shown when the map is opened from Debug: go down or up a circle at will, to see the descent.
var debug_tools := false
var _debug_box: HBoxContainer
var _debug_zone := 0


func _build_debug_tools() -> void:
	_debug_box = HBoxContainer.new()
	_debug_box.add_theme_constant_override("separation", 8)
	_debug_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_box.offset_left = -230
	_debug_box.offset_top = 16
	_debug_box.offset_right = -16
	# in the free Info layer: the MapPanel (a PanelContainer) stretched them over the whole map
	$Column/MapPanel.get_node("Info").add_child(_debug_box)
	for entry: Array in [["Circle up", -1], ["Descend", 1]]:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(100, 26)
		b.add_theme_font_size_override("font_size", 13)
		var step: int = entry[1]
		b.pressed.connect(func() -> void: _debug_move(step))
		_debug_box.add_child(b)


func _debug_move(step: int) -> void:
	if inferno == null:
		return
	var zones := 0
	for f: int in range(inferno._terraces()):
		zones = maxi(zones, inferno.zone_of_floor(f) + 1)
	_debug_zone = clampi(_debug_zone + step, 0, zones)       # zones = the pit
	var z := -1 if _debug_zone >= zones else _debug_zone
	_close_details()
	if step > 0:
		_descend(inferno.current_zone, z)
	else:
		inferno.set_current_zone(z)
		graph_canvas.show_only(func(floor_index: int) -> bool: return inferno.zone_of_floor(floor_index) == z)
	_shown_zone = z
	var info := inferno.zone_info(z)
	_zone_title.text = info["name"]
	_zone_line.text = info["line"]


# ------------------------------------------------------------------ circle names over the 3D
var _zone_labels: Array[Control] = []


## Each circle's name, written crisp over the view, riding on its ring as it turns. The one
## you are in is bright; the others (above you) are dim.
## Each circle's sign, in pixel art: a thorn branch, a noose, a gust of wind, a flame.
const ZONE_SIGNS := [
	["....x.......", "...x..x.....", "..x..x......", ".xx.x...x...", "..xxx..x....", "...xx.x.....",
		"....xxx..x..", ".....xx.x...", ".....xxx....", ".....xx.....", ".....xx.....", "....xxxx...."],
	["xxxxxxxxx...", "x.......x...", "x.......x...", "x......xxx..", "x.....x...x.", "x.....x...x.",
		"x......xxx..", "x...........", "x...........", "x...........", "x...........", "xxx........."],
	["...xxxxx....", "..x.....x...", ".x..xxx..x..", ".x.x...x.x..", ".x.x.x.x.x..", ".x.x..xx.x..",
		".x..x...x...", "..x..xxx....", "...x........", "....xxxxxxx.", "............", ".xxxxxxx...."],
	[".....x......", ".....xx.....", "....xxx.....", "....xx.x....", "...xx..xx...", "..xx.x..x...",
		"..x..xx.xx..", ".xx.xxx..x..", ".x..xxxx.x..", ".xx.xxxx.x..", "..xx....xx..", "...xxxxxx..."],
]
const SIGN_COLORS := [Color(0.62, 0.48, 0.3), Color(0.62, 0.6, 0.56), Color(0.75, 0.32, 0.22), Color(0.95, 0.42, 0.14)]


func _sign_texture(i: int) -> ImageTexture:
	var rows: Array = ZONE_SIGNS[i]
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y: int in range(12):
		var row: String = rows[y]
		for x: int in range(12):
			if row[x] == "x":
				img.set_pixel(x, y, SIGN_COLORS[i])
	return ImageTexture.create_from_image(img)


## Each circle's name (title only) with its sign, written over the view in small type blown up
## with hard pixels, riding on its ring as it turns. The one you are in is bright.
func _update_zone_labels() -> void:
	if inferno == null:
		return
	var panel := $Column/MapPanel as Control
	var layer := panel.get_node("Info") as Control      # not the PanelContainer: it would lay them out
	while _zone_labels.size() < 3:
		var i := _zone_labels.size()
		var tag := HBoxContainer.new()
		tag.add_theme_constant_override("separation", 3)
		tag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tag.scale = Vector2(2, 2)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = _sign_texture(i)
		icon.custom_minimum_size = Vector2(12, 12)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(icon)
		var l := Label.new()
		l.theme_type_variation = &"HeaderLabel"
		l.add_theme_font_size_override("font_size", 11)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(l)
		layer.add_child(tag)
		_zone_labels.append(tag)
	for z: int in range(_zone_labels.size()):
		var tag := _zone_labels[z]
		(tag.get_child(1) as Label).text = inferno.zone_info(z)["name"]
		# the first point of its band, going round from the upper left, that is on screen
		var at := Vector2(-9999, -9999)
		for k: int in range(16):
			var ang := -PI * 0.5 - 0.6 - k * 0.25
			var p := inferno.screen_pos_of(inferno.zone_point(z, ang))
			if p.x > 80.0 and p.y > 60.0 and p.x < panel.size.x - 80.0 and p.y < panel.size.y - 40.0:
				at = p
				break
		tag.visible = at.x > -1000.0
		tag.position = at - tag.size * tag.scale * 0.5
		var here := z == inferno.current_zone
		tag.modulate = Color(1, 1, 1, 1.0 if here else 0.35)


func _process(_delta: float) -> void:
	if visible:
		_update_zone_labels()


# ------------------------------------------------------------------ leaving a circle
## When a circle is done: a notebook page comes up listing the circles in ink, the finished
## one is struck through with a red line, the page is pulled away, and the eye drops hard to
## the next circle.
var _shown_zone := -2
var _notebook: Control
var _nb_rows: Array[Label] = []


const HAND := preload("res://assets/fonts/HomemadeApple-Regular.ttf")
const PAGE := preload("res://assets/ui/notebook_page.png")
const PAPER_PIXELS := preload("res://resources/shaders/paper_pixels.gdshader")
const INK_HAND := Color(0.13, 0.07, 0.04)
const INK_RED := Color(0.45, 0.05, 0.03)


## A page torn from a notebook (stained, folded, burnt at a corner), the circles written on
## its lines in a hurried hand. Drawn at half size through the game's dither, so the paper, the
## writing and the ink are pixels like everything else.
func _build_notebook() -> void:
	# a small scrap torn from a notebook page, laid out at 200 x 124 and shown twice as big with
	# hard pixels (expand mode is set before the size: else the image took its own 640 x 420)
	var holder := Control.new()
	holder.size = Vector2(200, 124)
	holder.scale = Vector2(2, 2)
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.rotation = 0.05
	holder.visible = false
	_notebook = holder
	$Column/MapPanel.get_node("Info").add_child(holder)
	# the scrap is drawn small (160 x 100) in its own viewport and shown big, with hard pixels
	# and a little grime on top
	var vp := SubViewport.new()
	vp.size = Vector2i(160, 100)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	holder.add_child(vp)
	var group := Control.new()
	group.size = Vector2(200, 124)
	group.scale = Vector2(0.8, 0.8)
	vp.add_child(group)
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture = vp.get_texture()
	view.size = Vector2(200, 124)
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = PAPER_PIXELS
	view.material = mat
	holder.add_child(view)
	var scrap := AtlasTexture.new()
	scrap.atlas = PAGE
	scrap.region = Rect2(0, 40, 380, 236)          # the left part, burnt corner and all
	# the shadow: the same torn shape, black, a little offset
	var shadow := TextureRect.new()
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.texture = scrap
	shadow.size = Vector2(200, 124)
	shadow.position = Vector2(4, 5)
	shadow.modulate = Color(0, 0, 0, 0.6)
	group.add_child(shadow)
	var page := TextureRect.new()
	page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page.stretch_mode = TextureRect.STRETCH_SCALE
	page.texture = scrap
	page.size = Vector2(200, 124)
	page.modulate = Color(0.9, 0.86, 0.8)
	group.add_child(page)
	var rows := [10.0, 36.0, 62.0, 88.0]          # on the scrap's ruled lines
	for i: int in range(4):
		var info := inferno.zone_info(i if i < 3 else -1)
		var l := Label.new()
		l.text = "%d.  %s" % [i + 1, info["hand"]]
		l.add_theme_font_override("font", HAND)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", INK_HAND)
		l.add_theme_constant_override("outline_size", 0)
		l.position = Vector2(14 + i * 1.5, rows[i])
		l.rotation = randf_range(-0.02, 0.015)
		page.add_child(l)
		_nb_rows.append(l)
	_strike_line = Line2D.new()
	_strike_line.default_color = INK_RED
	_strike_line.width = 2.5
	var wc := Curve.new()
	wc.add_point(Vector2(0, 1.0))
	wc.add_point(Vector2(0.6, 0.9))
	wc.add_point(Vector2(1, 0.3))
	_strike_line.width_curve = wc
	_strike_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_strike_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	page.add_child(_strike_line)
	_splatter = Node2D.new()
	page.add_child(_splatter)


var _strike_line: Line2D
var _splatter: Node2D


## Struck out with hate: one hard, fast slash across the name, driven past its end, the pen
## pressing hardest where it starts; ink spatters where it leaves the paper.
func _strike_out(row: Label) -> void:
	var w := HAND.get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var y := row.position.y + row.size.y * 0.6
	var x0 := row.position.x - 6.0
	var x1 := row.position.x + w + 16.0
	var path: Array[Vector2] = []
	var n := 12
	for i: int in range(n + 1):
		var u := float(i) / n
		path.append(Vector2(lerpf(x0, x1, u), y + 3.0 - u * 7.0 + randf_range(-0.8, 0.8)))
	_strike_line.clear_points()
	for c in _splatter.get_children():
		c.queue_free()
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		var upto := int(v * (path.size() - 1))
		while _strike_line.get_point_count() <= upto:
			_strike_line.add_point(path[_strike_line.get_point_count()]), 0.0, 1.0, 0.13) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	# the spatter flung off the end of the stroke
	var end := path[path.size() - 1]
	for k: int in range(7):
		var dot := ColorRect.new()
		dot.color = INK_RED
		var s := randf_range(1.0, 2.5)
		dot.size = Vector2(s, s)
		dot.position = end + Vector2(randf_range(2.0, 14.0), randf_range(-6.0, 3.0))
		_splatter.add_child(dot)


func _descend(from_zone: int, to_zone: int) -> void:
	if _notebook == null:
		_build_notebook()
	graph_canvas.show_only(func(_f: int) -> bool: return false)
	var panel := $Column/MapPanel as Control
	_notebook.visible = true
	_notebook.modulate.a = 0.0
	await get_tree().process_frame
	# pulled out at the lower left, like a to-do list looked at sideways
	var rest := Vector2(36, panel.size.y - _notebook.size.y * 2.0 - 40.0)
	_notebook.position = rest + Vector2(-80, 60)
	var row: Label = _nb_rows[from_zone] if from_zone >= 0 and from_zone < _nb_rows.size() else null
	_strike_line.clear_points()
	for c in _splatter.get_children():
		c.queue_free()
	var t := create_tween()
	t.tween_property(_notebook, "modulate:a", 1.0, 0.25)
	t.parallel().tween_property(_notebook, "position", rest, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	if row != null:
		await _strike_out(row)
	await get_tree().create_timer(0.45).timeout
	# the page is pulled away and you drop
	var out := create_tween()
	out.tween_property(_notebook, "position", rest + Vector2(-140, 420), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	inferno.drop_to_zone(to_zone)
	await out.finished
	_notebook.visible = false
	graph_canvas.show_only(func(floor_index: int) -> bool: return inferno.zone_of_floor(floor_index) == to_zone)
