class_name NodeContentData
extends Resource

## Base resource for content associated with a map node.
## Subclasses define data for Encounters, Decisions, Shops, and Safe Rooms.
## Runtime state must never be stored on shared NodeContentData instances.

@export var content_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""


func _init(p_id: String = "", p_name: String = "", p_description: String = "") -> void:
	content_id = p_id
	display_name = p_name
	description = p_description


## Override in subclasses to specify which MapEnums.NodeType values this resource supports.
func is_compatible_with(_node_type: MapEnums.NodeType) -> bool:
	return false


## Validates that required fields on the content resource are well-formed.
func is_valid() -> bool:
	return not content_id.strip_edges().is_empty()
