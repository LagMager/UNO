class_name MapEnums
extends RefCounted

## Shared enumerations and helpers for the roguelike map system.

enum NodeType {
	ENCOUNTER,
	DECISION,
	SHOP,
	SAFE_ROOM,
	ELITE,
	BOSS,
}


static func node_type_to_string(node_type: NodeType) -> String:
	match node_type:
		NodeType.ENCOUNTER:
			return "Encounter"
		NodeType.DECISION:
			return "Decision"
		NodeType.SHOP:
			return "Shop"
		NodeType.SAFE_ROOM:
			return "Safe Room"
		NodeType.ELITE:
			return "Elite"
		NodeType.BOSS:
			return "Boss"
		_:
			return "Unknown"


static func node_type_from_string(label: String) -> NodeType:
	match label.strip_edges().to_lower():
		"encounter":
			return NodeType.ENCOUNTER
		"decision", "event":
			return NodeType.DECISION
		"shop":
			return NodeType.SHOP
		"safe_room", "safe room", "rest", "rest_site":
			return NodeType.SAFE_ROOM
		"elite":
			return NodeType.ELITE
		"boss":
			return NodeType.BOSS
		_:
			return NodeType.ENCOUNTER
