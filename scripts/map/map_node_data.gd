class_name MapNodeData
extends Resource

## Represents one node in the map directed acyclic graph (DAG).
## Stores immutable identity, layer/column coordinates, outgoing node IDs, and content reference.
## Mutable progression state (discovered, completed, current) is stored in RunState.

@export var id: String = ""
@export var node_type: MapEnums.NodeType = MapEnums.NodeType.ENCOUNTER
@export var floor_index: int = 0
@export var column_index: int = 0
@export var position_offset: Vector2 = Vector2.ZERO
@export var next_node_ids: PackedStringArray = PackedStringArray()
@export var content: NodeContentData = null


func _init(
	p_id: String = "",
	p_node_type: MapEnums.NodeType = MapEnums.NodeType.ENCOUNTER,
	p_floor_index: int = 0,
	p_column_index: int = 0,
	p_content: NodeContentData = null
) -> void:
	id = p_id
	node_type = p_node_type
	floor_index = p_floor_index
	column_index = p_column_index
	content = p_content


## Adds an outgoing connection to target_id if not already present and not a self-loop.
func add_connection(target_id: String) -> bool:
	var cleaned: String = target_id.strip_edges()
	if cleaned.is_empty() or cleaned == id:
		return false
	if not next_node_ids.has(cleaned):
		next_node_ids.append(cleaned)
	return true


func has_connection_to(target_id: String) -> bool:
	return next_node_ids.has(target_id)


## Validates that the assigned content resource is non-null and compatible with this node's type.
func is_content_compatible() -> bool:
	if content == null:
		return false
	return content.is_compatible_with(node_type)


## Validates node identity, coordinates, connections, and content compatibility.
func is_valid() -> bool:
	if id.strip_edges().is_empty():
		return false
	if floor_index < 0 or column_index < 0:
		return false
	for next_id: String in next_node_ids:
		if next_id.strip_edges().is_empty() or next_id == id:
			return false
	return is_content_compatible()
