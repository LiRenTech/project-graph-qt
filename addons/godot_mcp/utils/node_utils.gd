@tool
class_name NodeUtils
extends RefCounted

# Get all nodes of a certain type in the scene tree
static func get_nodes_by_type(root_node: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	
	if root_node.get_class() == type_name:
		result.push_back(root_node)
	
	for child in root_node.get_children():
		result.append_array(get_nodes_by_type(child, type_name))
	
	return result

# Get a node by its path, or null if not found
static func find_node_by_path(root_node: Node, path: String) -> Node:
	if path.is_empty():
		return null
	
	if path.begins_with("/"):
		path = path.substr(1)
	
	var path_parts = path.split("/")
	var current_node = root_node
	
	for part in path_parts:
		var found = false
		for child in current_node.get_children():
			if child.name == part:
				current_node = child
				found = true
				break
		
		if not found:
			return null
	
	return current_node

# Convert a node to a JSON-compatible dictionary
static func node_to_dict(node: Node) -> Dictionary:
	var result = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"properties": {}
	}
	
	# Get properties
	var properties = {}
	var property_list = node.get_property_list()
	
	for prop in property_list:
		var name = prop["name"]
		if not name.begins_with("_"): # Skip internal properties
			result["properties"][name] = node.get(name)
	
	# Get children
	var children = []
	for child in node.get_children():
		children.append({
			"name": child.name,
			"type": child.get_class(),
			"path": str(child.get_path())
		})
	
	result["children"] = children
	
	return result

# Create a screenshot of a node (only works for CanvasItem nodes)
static func take_node_screenshot(node: CanvasItem) -> Image:
	if not node is CanvasItem:
		push_error("Can only take screenshots of CanvasItem nodes")
		return null
	
	var viewport = node.get_viewport()
	if not viewport:
		return null
	
	return viewport.get_texture().get_image()
