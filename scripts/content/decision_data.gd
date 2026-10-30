class_name DecisionData
extends NodeContentData

## Reusable event/decision definition for Decision map nodes.
## Holds the event title, narrative description, and ordered choices.

@export var title: String = ""
@export var choices: Array[ChoiceData] = []


func _init(
	p_id: String = "decision_default",
	p_title: String = "Mysterious Crossroads",
	p_description: String = "You encounter a strange figure along the path.",
	p_choices: Array[ChoiceData] = []
) -> void:
	super._init(p_id, p_title, p_description)
	title = p_title
	choices = p_choices.duplicate()


func is_compatible_with(node_type: MapEnums.NodeType) -> bool:
	return is_valid() and node_type == MapEnums.NodeType.DECISION


func is_valid() -> bool:
	return super.is_valid() and not title.strip_edges().is_empty()
