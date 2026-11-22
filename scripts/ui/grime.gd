class_name UIGrime
extends RefCounted

## Puts the dirty interface finish (ui_grime.gdshader) on a 2D tree: the root gets the
## material and every CanvasItem under it uses its parent's, including the ones created
## later. 3D views (SubViewportContainer, which carry the pixel dither) and anything with
## its own material are left alone.

const SHADER := preload("res://resources/shaders/ui_grime.gdshader")


static func apply(root: CanvasItem) -> void:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	root.material = m
	for child in root.get_children():
		_inherit(child)
	root.get_tree().node_added.connect(func(n: Node) -> void:
		if is_instance_valid(root) and root.is_ancestor_of(n):
			_inherit_one(n))


static func _inherit(n: Node) -> void:
	if not _inherit_one(n):
		return
	for child in n.get_children():
		_inherit(child)


## Returns false where the finish must stop (3D views and their insides).
static func _inherit_one(n: Node) -> bool:
	if n is SubViewport or n is SubViewportContainer:
		return false
	var p := n.get_parent()
	while p != null:
		if p is SubViewport or p is SubViewportContainer:
			return false
		p = p.get_parent()
	if n is CanvasItem:
		var ci := n as CanvasItem
		if ci.material == null:
			ci.use_parent_material = true
		else:
			return false
	return true
