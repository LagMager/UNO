class_name MapGraphCanvas
extends Control

## Positions MapNodeView widgets by floor/column and renders DAG connection lines.

signal node_clicked(node_id: String)

const MAP_NODE_VIEW_SCENE = preload("res://scenes/map/map_node_view.tscn")
const NODE_SIZE := Vector2(132, 68)
const FLOOR_SPACING_X := 178.0
const COLUMN_SPACING_Y := 92.0
const PADDING := Vector2(36, 28)

var node_views: Dictionary = {}
var _edges_to_draw: Array[Dictionary] = []


func render_graph(run_state: RunState) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	node_views.clear()
	_edges_to_draw.clear()

	if run_state == null or run_state.map_data == null:
		queue_redraw()
		return

	var map: MapData = run_state.map_data
	var total_floors: int = maxi(map.total_floors, 1)
	var grid_columns: int = maxi(int(map.metadata.get("grid_columns", 5)), 1)
	var reachable_ids: PackedStringArray = run_state.get_reachable_node_ids()

	var canvas_width: float = PADDING.x * 2.0 + float(maxi(total_floors - 1, 0)) * FLOOR_SPACING_X + NODE_SIZE.x
	var canvas_height: float = PADDING.y * 2.0 + float(maxi(grid_columns - 1, 0)) * COLUMN_SPACING_Y + NODE_SIZE.y
	custom_minimum_size = Vector2(canvas_width, canvas_height)

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
			node_views[node_data.id] = widget

	for node_data: MapNodeData in map.nodes:
		if node_data == null or not node_views.has(node_data.id):
			continue
		var from_widget: MapNodeView = node_views[node_data.id]
		var from_center: Vector2 = from_widget.position + NODE_SIZE * 0.5
		for next_id: String in node_data.next_node_ids:
			if not node_views.has(next_id):
				continue
			var to_widget: MapNodeView = node_views[next_id]
			var to_center: Vector2 = to_widget.position + NODE_SIZE * 0.5
			var edge_style: Dictionary = _resolve_edge_style(run_state, node_data.id, next_id, reachable_ids)
			_edges_to_draw.append({
				"from": from_center,
				"to": to_center,
				"color": edge_style["color"],
				"width": edge_style["width"],
			})

	queue_redraw()


func get_node_view(node_id: String) -> MapNodeView:
	return node_views.get(node_id, null) as MapNodeView


func _draw() -> void:
	for edge: Dictionary in _edges_to_draw:
		draw_line(edge["from"], edge["to"], edge["color"], float(edge["width"]), true)


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
		return {"color": Color("#52b788"), "width": 4.0}
	if (run_state.current_node_id == from_id or from_id == run_state.map_data.start_node_id) and reachable_ids.has(to_id):
		return {"color": Color("#ffd166"), "width": 3.5}
	return {"color": Color("#4a4a52"), "width": 2.0}
