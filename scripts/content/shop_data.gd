class_name ShopData
extends NodeContentData

## Reusable configuration resource for Shop map nodes.

@export var card_slot_count: int = 3
@export var base_card_price: int = 25
@export var allow_card_removal: bool = true
@export var removal_price: int = 30
@export var heal_price: int = 15
@export var heal_amount: int = 3


func _init(
	p_id: String = "shop_default",
	p_name: String = "Merchant Shop",
	p_description: String = "Spend gold to buy cards or mend your wounds."
) -> void:
	super._init(p_id, p_name, p_description)


func is_compatible_with(node_type: MapEnums.NodeType) -> bool:
	return is_valid() and node_type == MapEnums.NodeType.SHOP


func is_valid() -> bool:
	return super.is_valid() \
		and card_slot_count >= 0 \
		and base_card_price >= 0 \
		and removal_price >= 0 \
		and heal_price >= 0 \
		and heal_amount >= 0
