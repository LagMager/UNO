class_name MapGraphCanvas
extends Control

## Positions MapNodeView widgets by floor/column and renders DAG connection lines.

signal node_clicked(node_id: String)
## The mouse is over a node (empty id: over none).
signal node_hovered(node_id: String)

const MAP_NODE_VIEW_SCENE = preload("res://scenes/map/map_node_view.tscn")
const NODE_SIZE := Vector2(132, 84)
const FLOOR_SPACING_X := 178.0
const COLUMN_SPACING_Y := 100.0
const PADDING := Vector2(36, 28)
const ICON_CENTER := Vector2(66, 24)    # NODE_SIZE.x / 2, MapNodeView.ICON_R + 4

var node_views: Dictionary = {}
var _edges_to_draw: Array[Dictionary] = []
## Optional layout (RingMap): nodes stand where their place on the rings is.
var layout: Object = null
var _cells := {}     # node id -> Vector2i(floor, column)


func render_graph(run_state: RunState) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	node_views.clear()
	_edges_to_draw.clear()
	_cells.clear()

	if run_state == null or run_state.map_data == null:
		queue_redraw()
		return

	var map: MapData = run_state.map_data
	var total_floors: int = maxi(map.total_floors, 1)
	var grid_columns: int = maxi(int(map.metadata.get("grid_columns", 5)), 1)
	var reachable_ids: PackedStringArray = run_state.get_reachable_node_ids()

	var canvas_width: float = PADDING.x * 2.0 + float(maxi(total_floors - 1, 0)) * FLOOR_SPACING_X + NODE_SIZE.x
	var canvas_height: float = PADDING.y * 2.0 + float(maxi(grid_columns - 1, 0)) * COLUMN_SPACING_Y + NODE_SIZE.y
	custom_minimum_size = Vector2(canvas_width, canvas_height) if layout == null else Vector2.ZERO
	if layout != null:
		layout.set_layout(total_floors, grid_columns)

	for floor_idx: int in range(total_floors):
		var floor_nodes: Array[MapNodeData] = map.get_nodes_on_floor(floor_idx)
		for node_data: MapNodeData in floor_nodes:
			var widget := MAP_NODE_VIEW_SCENE.instantiate() as MapNodeView
			widget.name = "Node_%s" % node_data.id
			add_child(widget)

			var state: MapNodeView.VisualState = _resolve_visual_state(run_state, node_data.id, reachable_ids)
			widget.setup_node(node_data, state)
			widget.size = NODE_SIZE
			widget.position = _compute_node_position(node_data)
			widget.node_clicked.connect(func(clicked_id: String) -> void: node_clicked.emit(clicked_id))
			var hid: String = node_data.id
			widget.mouse_entered.connect(func() -> void: node_hovered.emit(hid))
			widget.mouse_exited.connect(func() -> void: node_hovered.emit(""))
			_cells[node_data.id] = Vector2i(node_data.floor_index, node_data.column_index)
			node_views[node_data.id] = widget

	for node_data: MapNodeData in map.nodes:
		if node_data == null or not node_views.has(node_data.id):
			continue
		var from_widget: MapNodeView = node_views[node_data.id]
		var from_center: Vector2 = from_widget.position + ICON_CENTER
		for next_id: String in node_data.next_node_ids:
			if not node_views.has(next_id):
				continue
			var to_widget: MapNodeView = node_views[next_id]
			var to_center: Vector2 = to_widget.position + ICON_CENTER
			var edge_style: Dictionary = _resolve_edge_style(run_state, node_data.id, next_id, reachable_ids)
			_edges_to_draw.append({
				"from_id": node_data.id,
				"to_id": next_id,
				"from": from_center,
				"to": to_center,
				"color": edge_style["color"],
				"width": edge_style["width"],
				"dashed": edge_style.get("dashed", false),
			})

	queue_redraw()


func get_node_view(node_id: String) -> MapNodeView:
	return node_views.get(node_id, null) as MapNodeView


## Trails drawn by hand in ink: a slight wobble, stopping short of the medallions,
## dashed where the way is still unknown.
func _draw() -> void:
	for edge: Dictionary in _edges_to_draw:
		var a: Vector2 = edge["from"]
		var b: Vector2 = edge["to"]
		if layout != null:
			if not ((node_views[edge["from_id"]] as Control).visible and (node_views[edge["to_id"]] as Control).visible):
				continue
			a = (node_views[edge["from_id"]] as Control).position + ICON_CENTER
			b = (node_views[edge["to_id"]] as Control).position + ICON_CENTER
		var d := (b - a).normalized()
		a += d * (MapNodeView.ICON_R + 6.0)
		b -= d * (MapNodeView.ICON_R + 6.0)
		var n := Vector2(-d.y, d.x)
		var seg := 18
		var seed := a.x * 0.37 + b.y * 0.11
		var pts := PackedVector2Array()
		for i: int in range(seg + 1):
			var u := float(i) / seg
			var wob := sin(u * 9.0 + seed) * 1.6 + sin(u * 23.0 + seed * 2.0) * 0.7
			pts.append(a.lerp(b, u) + n * wob * sin(u * PI))
		if edge["dashed"]:
			for i: int in range(0, seg, 2):
				draw_line(pts[i], pts[i + 1], edge["color"], float(edge["width"]))
		else:
			draw_polyline(pts, edge["color"], float(edge["width"]))


func _compute_node_position(node_data: MapNodeData) -> Vector2:
	var base := Vector2(
		PADDING.x + float(node_data.floor_index) * FLOOR_SPACING_X,
		PADDING.y + float(node_data.column_index) * COLUMN_SPACING_Y
	)
	return base + node_data.position_offset


func _resolve_visual_state(
	run_state: RunState,
	node_id: String,
	reachable_ids: PackedStringArray
) -> MapNodeView.VisualState:
	if run_state.current_node_id == node_id and not run_state.is_node_completed(node_id):
		return MapNodeView.VisualState.CURRENT
	if reachable_ids.has(node_id):
		return MapNodeView.VisualState.REACHABLE
	if run_state.is_node_completed(node_id):
		return MapNodeView.VisualState.COMPLETED
	if run_state.is_node_discovered(node_id):
		return MapNodeView.VisualState.DISCOVERED
	return MapNodeView.VisualState.LOCKED


func _resolve_edge_style(
	run_state: RunState,
	from_id: String,
	to_id: String,
	reachable_ids: PackedStringArray
) -> Dictionary:
	if run_state.is_node_completed(from_id) and (run_state.is_node_completed(to_id) or run_state.current_node_id == to_id):
		return {"color": Color(0.5, 0.1, 0.07, 1), "width": 3.5}         # the way you came, in dried blood
	if (run_state.current_node_id == from_id or from_id == run_state.map_data.start_node_id) and reachable_ids.has(to_id):
		return {"color": Color(0.85, 0.32, 0.1, 1), "width": 3.0}        # where you can go, ember
	return {"color": Color(0.8, 0.75, 0.64, 0.25), "width": 2.0, "dashed": true}


## With a 3D layout the nodes follow the camera every frame.
func _process(_delta: float) -> void:
	if layout == null or node_views.is_empty():
		return
	for id: String in node_views.keys():
		var cell: Vector2i = _cells[id]
		var w := node_views[id] as Control
		w.position = layout.screen_pos_of(layout.world_pos_of(cell.x, cell.y)) - ICON_CENTER
	queue_redraw()


var _shown: Callable = Callable()


## Shows only the nodes whose floor passes the filter (the others and their trails hide).
func show_only(filter: Callable) -> void:
	_shown = filter
	for id: String in node_views.keys():
		(node_views[id] as Control).visible = filter.call((_cells[id] as Vector2i).x)
	queue_redraw()


## Where the nodes stand in the 3D world (for the camera to look at).
func world_points(ids: PackedStringArray) -> Array:
	var out := []
	if layout == null:
		return out
	for id: String in ids:
		if _cells.has(id):
			var cell: Vector2i = _cells[id]
			out.append(layout.world_pos_of(cell.x, cell.y))
	return out


func floor_of(id: String) -> int:
	return (_cells[id] as Vector2i).x if _cells.has(id) else -1
