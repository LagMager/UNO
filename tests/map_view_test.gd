extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var map_data: MapData = MapGenerator.generate(2026)
	var run_state := RunState.new(map_data, 8, 30)

	var scene: PackedScene = load("res://scenes/map/map_view.tscn")
	var map_view := scene.instantiate() as MapView
	root.add_child(map_view)
	map_view.bind_run_state(run_state)
	await process_frame
	await process_frame

	_check(map_view.graph_canvas.node_views.size() == map_data.nodes.size(), "MapView should instantiate a MapNodeView for every node in MapData.")

	var start_widget: MapNodeView = map_view.get_node_view(map_data.start_node_id)
	var boss_widget: MapNodeView = map_view.get_node_view(map_data.boss_node_id)
	_check(start_widget != null and boss_widget != null, "Start and boss widgets should exist.")
	_check(not start_widget.disabled and start_widget.visual_state == MapNodeView.VisualState.REACHABLE, "Start node should be reachable and enabled initially.")
	_check(boss_widget.disabled and boss_widget.visual_state == MapNodeView.VisualState.LOCKED, "Boss node should be locked and disabled initially.")

	var selected_ids: Array[String] = []
	map_view.node_selected.connect(func(id: String) -> void:
		selected_ids.append(id)
	)

	# Attempt to select unreachable boss node — must be rejected
	_check(not map_view.request_select_node(map_data.boss_node_id), "Selecting unreachable boss node must fail.")
	_check(selected_ids.is_empty(), "Unreachable node must not emit node_selected.")

	# Select reachable start node
	_check(map_view.request_select_node(map_data.start_node_id), "Selecting reachable start node must succeed.")
	_check(selected_ids == [map_data.start_node_id], "Selecting start node should emit node_selected once.")

	# Progress run state through start node and verify UI updates
	_check(run_state.select_node(map_data.start_node_id), "RunState should enter start node.")
	await process_frame
	start_widget = map_view.get_node_view(map_data.start_node_id)
	_check(start_widget.visual_state == MapNodeView.VisualState.CURRENT and start_widget.disabled, "Entered node should display as CURRENT and be disabled while active.")

	_check(run_state.complete_active_node(), "Completing start node should succeed.")
	await process_frame
	start_widget = map_view.get_node_view(map_data.start_node_id)
	_check(start_widget.visual_state == MapNodeView.VisualState.COMPLETED, "Completed node should display as COMPLETED.")

	var next_ids: PackedStringArray = run_state.get_reachable_node_ids()
	_check(not next_ids.is_empty(), "Outgoing nodes from start should now be reachable.")
	for next_id: String in next_ids:
		var next_widget: MapNodeView = map_view.get_node_view(next_id)
		_check(next_widget != null and not next_widget.disabled and next_widget.visual_state == MapNodeView.VisualState.REACHABLE, "Outgoing node '%s' should be highlighted as REACHABLE." % next_id)

	if failures == 0:
		print("Milestone 3 map presentation tests passed.")
	quit(1 if failures > 0 else 0)
