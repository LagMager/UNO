extends VBoxContainer

@onready var status_label: Label = $StatusLabel
@onready var progress_label: Label = $ProgressLabel
@onready var pile_label: Label = $PileLabel


func render_hud(session: RefCounted) -> void:
	var encounter = session.encounter
	status_label.text = session.status_text()
	progress_label.text = session.progress_text()

	var status_color := Color.WHITE
	if encounter.result == "Victory":
		status_color = Color.LIGHT_GREEN
	elif encounter.result == "Defeat":
		status_color = Color.SALMON
	status_label.add_theme_color_override("font_color", status_color)

	pile_label.text = "Top card: %s  |  Active color: %s  |  Draw pile: %d" % [
		encounter.card_label(encounter.top_card()),
		encounter.active_color_name(),
		encounter.draw_pile.size()
	]
