@tool
class_name ScriptUtils
extends RefCounted

# Create a new GDScript with basic template content
static func create_new_script(class_name_str: String = "", extends_type: String = "Node") -> GDScript:
	var script = GDScript.new()
	var content = ""
	
	if not class_name_str.is_empty():
		content += "class_name " + class_name_str + "\n"
	
	content += "extends " + extends_type + "\n\n"
	content += "func _ready():\n"
	content += "\tpass\n"
	
	script.source_code = content
	return script

# Create a new script file with basic template content
static func create_script_file(path: String, class_name_str: String = "", extends_type: String = "Node") -> bool:
	# Make sure directory exists
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_error("Failed to create directory: " + dir_path)
			return false
	
	var content = ""
	
	if not class_name_str.is_empty():
		content += "class_name " + class_name_str + "\n"
	
	content += "extends " + extends_type + "\n\n"
	content += "func _ready():\n"
	content += "\tpass\n"
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: " + path)
		return false
	
	file.store_string(content)
	file = null  # Close the file
	
	return true

# Parse a script file and extract its class name and base class
static func get_script_info(path: String) -> Dictionary:
	var result = {
		"class_name": "",
		"extends": "",
		"path": path
	}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file for reading: " + path)
		return result
	
	var content = file.get_as_text()
	file = null  # Close the file
	
	# Find class_name
	var class_name_regex = RegEx.new()
	class_name_regex.compile("class_name\\s+([A-Za-z0-9_]+)")
	var matches = class_name_regex.search(content)
	if matches:
		result["class_name"] = matches.get_string(1)
	
	# Find extends
	var extends_regex = RegEx.new()
	extends_regex.compile("extends\\s+([A-Za-z0-9_]+)")
	matches = extends_regex.search(content)
	if matches:
		result["extends"] = matches.get_string(1)
	
	return result

# Extract all method names from a script
static func get_script_methods(path: String) -> Array:
	var methods = []
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file for reading: " + path)
		return methods
	
	var content = file.get_as_text()
	file = null  # Close the file
	
	var method_regex = RegEx.new()
	method_regex.compile("func\\s+([A-Za-z0-9_]+)\\s*\\(")
	
	var matches = method_regex.search_all(content)
	for match_idx in range(matches.size()):
		methods.append(matches[match_idx].get_string(1))
	
	return methods

# Apply a script to a node
static func apply_script_to_node(node: Node, script_path: String) -> bool:
	if not node:
		push_error("Node is null")
		return false
	
	var script = ResourceLoader.load(script_path)
	if not script:
		push_error("Failed to load script: " + script_path)
		return false
	
	node.set_script(script)
	return true