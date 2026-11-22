class_name RestSiteData
extends NodeContentData

## Reusable configuration resource for Safe Room / Rest Site map nodes.

@export var heal_amount: int = 3
@export var allow_card_upgrade: bool = true


func _init(
	p_id: String = "rest_default",
	p_heal_amount: int = 3,
	p_allow_upgrade: bool = true,
	p_name: String = "Safe Room",
	p_description: String = "Rest to recover health or upgrade a card in your deck."
) -> void:
	super._init(p_id, p_name, p_description)
	heal_amount = p_heal_amount
	allow_card_upgrade = p_allow_upgrade


func is_compatible_with(node_type: MapEnums.NodeType) -> bool:
	return is_valid() and node_type == MapEnums.NodeType.SAFE_ROOM


func is_valid() -> bool:
	return super.is_valid() and (heal_amount > 0 or allow_card_upgrade)
