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
	graph_canvas.node_clicked.connect(request_select_node)
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

	if _run_state.run_finished:
		if _run_state.run_victory:
			status_banner.text = "RUN COMPLETE — BOSS DEFEATED!"
			status_banner.add_theme_color_override("font_color", Color.LIGHT_GREEN)
		else:
			status_banner.text = "RUN ENDED — DEFEAT"
			status_banner.add_theme_color_override("font_color", Color.SALMON)
	else:
		var reachable: PackedStringArray = _run_state.get_reachable_node_ids()
		status_banner.text = "Select a highlighted node to advance (%d available)" % reachable.size()
		status_banner.add_theme_color_override("font_color", Color("#ffd166"))

	graph_canvas.render_graph(_run_state)


func request_select_node(node_id: String) -> bool:
	if _run_state == null or not _run_state.can_select_node(node_id):
		return false
	node_selected.emit(node_id)
	return true


func get_node_view(node_id: String) -> MapNodeView:
	return graph_canvas.get_node_view(node_id)


func _on_run_state_changed() -> void:
	render_map(_run_state)
