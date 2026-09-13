# node_tools_native.gd - Node Tools原生实现

@tool
class_name NodeToolsNative
extends RefCounted

var _editor_interface: EditorInterface = null

func initialize(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface

func register_tools(server_core: RefCounted) -> void:
	_register_create_node(server_core)
	_register_delete_node(server_core)
	_register_update_node_property(server_core)
	_register_batch_update_node_properties(server_core)
	_register_batch_scene_node_edits(server_core)
	_register_get_node_properties(server_core)
	_register_list_nodes(server_core)
	_register_get_scene_tree(server_core)
	_register_duplicate_node(server_core)
	_register_move_node(server_core)
	_register_rename_node(server_core)
	_register_add_resource(server_core)
	_register_set_anchor_preset(server_core)
	_register_connect_signal(server_core)
	_register_disconnect_signal(server_core)
	_register_get_node_groups(server_core)
	_register_set_node_groups(server_core)
	_register_find_nodes_in_group(server_core)
	_register_audit_scene_node_persistence(server_core)
	_register_audit_scene_inheritance(server_core)

func _register_create_node(server_core: RefCounted) -> void:
	server_core.register_tool(
		"create_node",
		"Create a new node in the Godot scene tree. Returns the node path and type.",
		{
			"type": "object",
			"properties": {
				"parent_path": {
					"type": "string",
					"description": "Path to the parent node where the new node will be created (e.g. '/root', '/root/MainScene')"
				},
				"node_type": {
					"type": "string",
					"description": "Type of node to create (e.g. 'Node2D', 'Sprite2D', 'CharacterBody2D')"
				},
				"node_name": {
					"type": "string",
					"description": "Name for the new node"
				},
				"on_name_conflict": {
					"type": "string",
					"description": "Behavior when node_name already exists in parent: 'error' (return error), 'rename' (auto-rename with unique suffix), 'auto' (allow Godot to assign @NodeType@XXXXX name). Default: 'error'.",
					"default": "error",
					"enum": ["error", "rename", "auto"]
				}
			},
			"required": ["parent_path", "node_type", "node_name"]
		},
		Callable(self, "_tool_create_node"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"node_path": {"type": "string"},
				"node_type": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"core", "Node-Write"
	)

func _resolve_node_path(node_path: String) -> Node:
	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return null
	
	if node_path == "/root" or node_path.is_empty():
		return scene_root
	
	var relative: String = node_path.trim_prefix("/root/")
	var parts: PackedStringArray = relative.split("/")
	
	if parts.size() > 0 and parts[0] == scene_root.name:
		if parts.size() == 1:
			return scene_root
		var sub_path: String = "/".join(parts.slice(1))
		return scene_root.get_node_or_null(sub_path)
	
	return scene_root.get_node_or_null(relative)

func _tool_create_node(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var node_type: String = params.get("node_type", "Node")
	var node_name: String = params.get("node_name", "NewNode")
	var on_name_conflict: String = params.get("on_name_conflict", "error")

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var parent: Node = _resolve_node_path(parent_path)
	if not parent:
		if parent_path == "/root" or parent_path.is_empty():
			parent = _get_user_scene_root()

	if not parent:
		return {"error": "Parent node not found: " + parent_path}

	if not ClassDB.class_exists(node_type):
		return {"error": "Invalid node type: " + node_type}

	# Handle name conflicts
	if parent.has_node(node_name):
		match on_name_conflict:
			"error":
				return {"error": "A node named '" + node_name + "' already exists under " + parent_path + ". Use a different name or set on_name_conflict='rename'."}
			"rename":
				var counter: int = 1
				var new_name: String = node_name + "_" + str(counter)
				while parent.has_node(new_name):
					counter += 1
					new_name = node_name + "_" + str(counter)
				node_name = new_name
			"auto":
				# Allow Godot to auto-rename with @ suffix (existing behavior)
				pass

	var node: Node = ClassDB.instantiate(node_type)
	node.name = node_name

	var scene_root: Node = _get_user_scene_root()

	# Traverse parent chain to find correct owner for nested/instanced scenes.
	# If parent is inside an instanced sub-scene, use parent.owner instead of scene_root.
	var correct_owner: Node = scene_root
	if scene_root and parent != scene_root:
		var current: Node = parent
		while current and current != scene_root:
			if current.owner and current.owner != scene_root and current.owner != current:
				correct_owner = current.owner
				break
			current = current.get_parent()
	
	# Wrap in EditorUndoRedoManager so the editor properly tracks the change
	var undo_redo: EditorUndoRedoManager = editor_interface.get_editor_undo_redo()
	if undo_redo:
		undo_redo.create_action("Create Node: " + node_name)
		undo_redo.add_do_method(parent, "add_child", node)
		undo_redo.add_do_method(node, "set_owner", correct_owner)
		undo_redo.add_undo_method(parent, "remove_child", node)
		undo_redo.commit_action()
	else:
		parent.add_child(node)
		if correct_owner:
			node.owner = correct_owner
	
	editor_interface.mark_scene_as_unsaved()
	
	var friendly_path: String = "/root/" + scene_root.name if scene_root else "/root"
	var node_friendly: String = str(node.get_path())
	if scene_root:
		var root_full: String = str(scene_root.get_path())
		if node_friendly.begins_with(root_full):
			node_friendly = "/root/" + scene_root.name + node_friendly.substr(root_full.length())
	
	return {
		"status": "success",
		"node_path": node_friendly,
		"node_type": node.get_class()
	}

func _register_delete_node(server_core: RefCounted) -> void:
	server_core.register_tool(
		"delete_node",
		"Delete a node from the Godot scene tree. This operation is destructive and cannot be undone.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the node to delete (e.g. '/root/MainScene/Player')"
				}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_delete_node"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"deleted_node": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false},
		"core", "Node-Write"
	)

func _tool_delete_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var node_to_delete: Node = _resolve_node_path(node_path)
	
	if not node_to_delete:
		return {"error": "Node not found: " + node_path}
	
	var deleted_node_name: String = node_to_delete.name
	var parent: Node = node_to_delete.get_parent()
	if parent:
		parent.remove_child(node_to_delete)
	
	node_to_delete.queue_free()
	editor_interface.mark_scene_as_unsaved()
	
	return {
		"status": "success",
		"deleted_node": deleted_node_name
	}

func _register_update_node_property(server_core: RefCounted) -> void:
	server_core.register_tool(
		"update_node_property",
		"Update a property of a specific node. Supports common property types with automatic type conversion.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the target node (e.g. '/root/MainScene/Player')"
				},
				"property_name": {
					"type": "string",
					"description": "Name of the property to update (e.g. 'position', 'visible', 'modulate')"
				},
				"property_value": {
					"description": "New value for the property. Type conversion is handled automatically."
				}
			},
			"required": ["node_path", "property_name", "property_value"]
		},
		Callable(self, "_tool_update_node_property"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"node_path": {"type": "string"},
				"property_name": {"type": "string"},
				"old_value": {"type": "string"},
				"new_value": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"core", "Node-Write"
	)

func _tool_update_node_property(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var property_name: String = params.get("property_name", "")
	var property_value: Variant = params.get("property_value", null)
	
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	if property_name.is_empty():
		return {"error": "Missing required parameter: property_name"}
	if property_value == null:
		return {"error": "Missing required parameter: property_value"}
	
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var target_node: Node = _resolve_node_path(node_path)
	
	if not target_node:
		return {"error": "Node not found: " + node_path}
	
	if not property_name in target_node:
		return {"error": "Property '" + property_name + "' not found on node " + node_path}
	
	var old_value: Variant = target_node.get(property_name)
	var actual_value: Variant = property_value
	if property_value is String:
		var parsed: Variant = JSON.parse_string(property_value)
		if parsed != null:
			actual_value = parsed
	var converted_value: Variant = _convert_value_for_property(target_node, property_name, actual_value)
	
	# Validate res:// resource paths before setting
	if actual_value is String and (actual_value as String).begins_with("res://"):
		if not ResourceLoader.exists(actual_value):
			return {"error": "Resource path does not exist: " + actual_value}
	
	var undo_redo: EditorUndoRedoManager = editor_interface.get_editor_undo_redo()
	if undo_redo:
		undo_redo.create_action("Update Property: " + property_name)
		undo_redo.add_do_property(target_node, property_name, converted_value)
		undo_redo.add_undo_property(target_node, property_name, old_value)
		undo_redo.commit_action()
	else:
		target_node.set(property_name, converted_value)
	
	var new_value: Variant = target_node.get(property_name)
	
	editor_interface.mark_scene_as_unsaved()
	
	return {
		"status": "success",
		"node_path": node_path,
		"property_name": property_name,
		"old_value": str(old_value),
		"new_value": str(new_value)
	}

func _register_batch_update_node_properties(server_core: RefCounted) -> void:
	server_core.register_tool(
		"batch_update_node_properties",
		"Update multiple node properties inside one editor UndoRedo action. Useful for transaction-style scene edits that should undo in a single step.",
		{
			"type": "object",
			"properties": {
				"label": {
					"type": "string",
					"description": "Optional UndoRedo action label. Default is 'Batch Update Node Properties'."
				},
				"changes": {
					"type": "array",
					"items": {
						"type": "object",
						"properties": {
							"node_path": {"type": "string"},
							"property_name": {"type": "string"},
							"property_value": {}
						},
						"required": ["node_path", "property_name", "property_value"]
					},
					"description": "Property updates to apply in one action."
				}
			},
			"required": ["changes"]
		},
		Callable(self, "_tool_batch_update_node_properties"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"label": {"type": "string"},
				"change_count": {"type": "integer"},
				"changes": {"type": "array"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"supplementary", "Node-Advanced"
	)

func _tool_batch_update_node_properties(params: Dictionary) -> Dictionary:
	var changes: Array = params.get("changes", [])
	if changes.is_empty():
		return {"error": "Missing required parameter: changes"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var prepared_changes: Array = []
	for change in changes:
		if not (change is Dictionary):
			return {"error": "Each change entry must be an object"}
		var node_path: String = str(change.get("node_path", ""))
		var property_name: String = str(change.get("property_name", ""))
		if node_path.is_empty() or property_name.is_empty() or not change.has("property_value"):
			return {"error": "Each change requires node_path, property_name, and property_value"}
		var target_node: Node = _resolve_node_path(node_path)
		if not target_node:
			return {"error": "Node not found: " + node_path}
		if not property_name in target_node:
			return {"error": "Property '" + property_name + "' not found on node " + node_path}
		var actual_value: Variant = change.get("property_value")
		if actual_value is String:
			var parsed: Variant = JSON.parse_string(actual_value)
			if parsed != null:
				actual_value = parsed
		var converted_value: Variant = _convert_value_for_property(target_node, property_name, actual_value)
		
		# Validate res:// resource paths before setting
		if actual_value is String and (actual_value as String).begins_with("res://"):
			if not ResourceLoader.exists(actual_value):
				return {"error": "Resource path does not exist: " + actual_value + " for property " + property_name + " on node " + node_path}
		prepared_changes.append({
			"node": target_node,
			"node_path": node_path,
			"property_name": property_name,
			"old_value": target_node.get(property_name),
			"new_value": converted_value
		})

	var label: String = str(params.get("label", "Batch Update Node Properties")).strip_edges()
	if label.is_empty():
		label = "Batch Update Node Properties"

	var undo_redo: EditorUndoRedoManager = editor_interface.get_editor_undo_redo()
	if undo_redo:
		undo_redo.create_action(label)
		for prepared in prepared_changes:
			undo_redo.add_do_property(prepared["node"], prepared["property_name"], prepared["new_value"])
			undo_redo.add_undo_property(prepared["node"], prepared["property_name"], prepared["old_value"])
		undo_redo.commit_action()
	else:
		for prepared in prepared_changes:
			prepared["node"].set(prepared["property_name"], prepared["new_value"])

	editor_interface.mark_scene_as_unsaved()

	var results: Array = []
	var property_types: Dictionary = {}
	for prepared in prepared_changes:
		results.append({
			"node_path": prepared["node_path"],
			"property_name": prepared["property_name"],
			"old_value": _serialize_value(prepared["old_value"]),
			"new_value": _serialize_value(prepared["node"].get(prepared["property_name"]))
		})
		# Collect type info for first node's properties
		if property_types.is_empty():
			for prop in prepared["node"].get_property_list():
				var pname: String = prop.get("name", "")
				if not pname.is_empty():
					property_types[pname] = _get_type_name(prop.get("type", TYPE_NIL))

	return {
		"status": "success",
		"label": label,
		"change_count": results.size(),
		"changes": results,
		"property_types": property_types
	}

func _get_type_name(type_id: int) -> String:
	match type_id:
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "string"
		TYPE_VECTOR2:
			return "Vector2 (dict {x,y} or string '(x,y)')"
		TYPE_VECTOR2I:
			return "Vector2i (dict {x,y} or string '(x,y)')"
		TYPE_VECTOR3:
			return "Vector3 (dict {x,y,z} or string '(x,y,z)')"
		TYPE_VECTOR3I:
			return "Vector3i"
		TYPE_COLOR:
			return "Color (dict {r,g,b,a} or hex '#RRGGBB')"
		TYPE_RECT2:
			return "Rect2 (dict {x,y,w,h})"
		TYPE_TRANSFORM2D:
			return "Transform2D (dict)"
		TYPE_PLANE:
			return "Plane"
		TYPE_QUATERNION:
			return "Quaternion"
		TYPE_AABB:
			return "AABB"
		TYPE_BASIS:
			return "Basis"
		TYPE_TRANSFORM3D:
			return "Transform3D"
		_:
			return "type_" + str(type_id)

func _register_batch_scene_node_edits(server_core: RefCounted) -> void:
	server_core.register_tool(
		"batch_scene_node_edits",
		"Apply multiple create/delete scene node edits inside one editor UndoRedo action so the full structure change undoes in a single step.",
		{
			"type": "object",
			"properties": {
				"label": {
					"type": "string",
					"description": "Optional UndoRedo action label. Default is 'Batch Scene Node Edits'."
				},
				"operations": {
					"type": "array",
					"description": "Ordered create/delete operations to apply in one transaction.",
					"items": {
						"type": "object",
						"properties": {
							"type": {"type": "string"},
							"parent_path": {"type": "string"},
							"node_type": {"type": "string"},
							"node_name": {"type": "string"},
							"node_path": {"type": "string"},
							"new_name": {"type": "string"},
							"new_parent_path": {"type": "string"},
							"keep_global_transform": {"type": "boolean"}
						},
						"required": ["type"]
					}
				}
			},
			"required": ["operations"]
		},
		Callable(self, "_tool_batch_scene_node_edits"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"label": {"type": "string"},
				"operation_count": {"type": "integer"},
				"operations": {"type": "array"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false},
		"supplementary", "Node-Advanced"
	)

func _tool_batch_scene_node_edits(params: Dictionary) -> Dictionary:
	var operations: Array = params.get("operations", [])
	if operations.is_empty():
		return {"error": "Missing required parameter: operations"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	var prepared_operations: Array = []
	for operation in operations:
		if not (operation is Dictionary):
			return {"error": "Each operation entry must be an object"}
		var operation_type: String = str(operation.get("type", "")).strip_edges().to_lower()
		match operation_type:
			"create":
				var parent_path: String = str(operation.get("parent_path", ""))
				var node_type: String = str(operation.get("node_type", "Node"))
				var node_name: String = str(operation.get("node_name", "NewNode"))
				if parent_path.is_empty() or node_name.is_empty():
					return {"error": "Create operations require parent_path and node_name"}
				var parent_node: Node = _resolve_node_path(parent_path)
				if not parent_node:
					if parent_path == "/root":
						parent_node = scene_root
					else:
						return {"error": "Parent node not found: " + parent_path}
				if not ClassDB.class_exists(node_type):
					return {"error": "Invalid node type: " + node_type}
				var new_node: Node = ClassDB.instantiate(node_type)
				new_node.name = node_name
				new_node.owner = scene_root
				prepared_operations.append({
					"type": "create",
					"parent": parent_node,
					"parent_path": parent_path,
					"node": new_node,
					"node_type": node_type,
					"node_name": node_name
				})
			"delete":
				var node_path: String = str(operation.get("node_path", ""))
				if node_path.is_empty():
					return {"error": "Delete operations require node_path"}
				var target_node: Node = _resolve_node_path(node_path)
				if not target_node:
					return {"error": "Node not found: " + node_path}
				var parent: Node = target_node.get_parent()
				if not parent:
					return {"error": "Cannot delete scene root"}
				var node_index: int = target_node.get_index()
				var duplicated: Node = target_node.duplicate()
				if duplicated:
					duplicated.owner = target_node.owner
				prepared_operations.append({
					"type": "delete",
					"node_path": node_path,
					"parent": parent,
					"node": target_node,
					"node_snapshot": duplicated,
					"node_owner": target_node.owner,
					"node_name": String(target_node.name),
					"node_type": target_node.get_class(),
					"node_index": node_index
				})
			"rename":
				var rename_node_path: String = str(operation.get("node_path", ""))
				var new_name: String = str(operation.get("new_name", "")).strip_edges()
				if rename_node_path.is_empty() or new_name.is_empty():
					return {"error": "Rename operations require node_path and new_name"}
				var rename_target: Node = _resolve_node_path(rename_node_path)
				if not rename_target:
					return {"error": "Node not found: " + rename_node_path}
				var old_name: String = str(rename_target.name)
				var rename_parent: Node = rename_target.get_parent()
				if rename_parent and old_name != new_name and rename_parent.has_node(new_name):
					return {"error": "Name '" + new_name + "' already exists in parent"}
				prepared_operations.append({
					"type": "rename",
					"node_path": rename_node_path,
					"node": rename_target,
					"old_name": old_name,
					"new_name": new_name,
					"node_type": rename_target.get_class()
				})
			"move":
				var move_node_path: String = str(operation.get("node_path", ""))
				var new_parent_path: String = str(operation.get("new_parent_path", ""))
				var keep_global_transform: bool = bool(operation.get("keep_global_transform", true))
				if move_node_path.is_empty() or new_parent_path.is_empty():
					return {"error": "Move operations require node_path and new_parent_path"}
				var move_target: Node = _resolve_node_path(move_node_path)
				if not move_target:
					return {"error": "Node not found: " + move_node_path}
				var old_parent: Node = move_target.get_parent()
				if not old_parent:
					return {"error": "Cannot move scene root"}
				var move_parent: Node = _resolve_node_path(new_parent_path)
				if not move_parent:
					if new_parent_path == "/root":
						move_parent = scene_root
					else:
						return {"error": "New parent not found: " + new_parent_path}
				if move_target == move_parent:
					return {"error": "Cannot move node to itself"}
				if move_target.is_ancestor_of(move_parent):
					return {"error": "Cannot move node to its own descendant"}
				prepared_operations.append({
					"type": "move",
					"node_path": move_node_path,
					"node": move_target,
					"old_parent": old_parent,
					"new_parent": move_parent,
					"new_parent_path": new_parent_path,
					"keep_global_transform": keep_global_transform,
					"node_owner": move_target.owner,
					"node_name": String(move_target.name),
					"node_type": move_target.get_class(),
					"old_index": move_target.get_index()
				})
			_:
				return {"error": "Unsupported operation type: " + operation_type}

	var label: String = str(params.get("label", "Batch Scene Node Edits")).strip_edges()
	if label.is_empty():
		label = "Batch Scene Node Edits"

	var undo_redo: EditorUndoRedoManager = editor_interface.get_editor_undo_redo()
	if not undo_redo:
		return {"error": "Editor UndoRedo is not available"}

	undo_redo.create_action(label)
	var result_operations: Array = []
	for prepared in prepared_operations:
		if prepared["type"] == "create":
			var created_parent: Node = prepared["parent"]
			var created_node: Node = prepared["node"]
			undo_redo.add_do_method(created_parent, "add_child", created_node)
			undo_redo.add_do_method(created_node, "set_owner", scene_root)
			undo_redo.add_undo_method(created_parent, "remove_child", created_node)
			result_operations.append({
				"type": "create",
				"node_path": _append_child_path(_make_friendly_path(created_parent, scene_root), prepared["node_name"]),
				"node_type": prepared["node_type"]
			})
		else:
			match String(prepared["type"]):
				"delete":
					var deleted_parent: Node = prepared["parent"]
					var deleted_node: Node = prepared["node"]
					var deleted_snapshot: Node = prepared["node_snapshot"]
					undo_redo.add_do_method(deleted_parent, "remove_child", deleted_node)
					undo_redo.add_undo_method(deleted_parent, "add_child", deleted_snapshot)
					undo_redo.add_undo_method(deleted_snapshot, "set_owner", prepared["node_owner"])
					undo_redo.add_undo_method(deleted_parent, "move_child", deleted_snapshot, prepared["node_index"])
					result_operations.append({
						"type": "delete",
						"node_path": prepared["node_path"],
						"node_type": prepared["node_type"]
					})
				"rename":
					var renamed_node: Node = prepared["node"]
					undo_redo.add_do_property(renamed_node, "name", prepared["new_name"])
					undo_redo.add_undo_property(renamed_node, "name", prepared["old_name"])
					var renamed_parent_path: String = _make_friendly_path(renamed_node.get_parent(), scene_root)
					result_operations.append({
						"type": "rename",
						"old_node_path": prepared["node_path"],
						"node_path": _append_child_path(renamed_parent_path, prepared["new_name"]),
						"old_name": prepared["old_name"],
						"new_name": prepared["new_name"],
						"node_type": prepared["node_type"]
					})
				"move":
					var moved_node: Node = prepared["node"]
					var old_parent_ref: Node = prepared["old_parent"]
					var new_parent_ref: Node = prepared["new_parent"]
					var preserve_global: bool = bool(prepared["keep_global_transform"])
					undo_redo.add_do_method(moved_node, "reparent", new_parent_ref, preserve_global)
					undo_redo.add_do_method(moved_node, "set_owner", prepared["node_owner"])
					undo_redo.add_undo_method(moved_node, "reparent", old_parent_ref, preserve_global)
					undo_redo.add_undo_method(moved_node, "set_owner", prepared["node_owner"])
					undo_redo.add_undo_method(old_parent_ref, "move_child", moved_node, prepared["old_index"])
					var friendly_new_parent_path: String = _make_friendly_path(new_parent_ref, scene_root)
					result_operations.append({
						"type": "move",
						"old_node_path": prepared["node_path"],
						"node_path": _append_child_path(friendly_new_parent_path, prepared["node_name"]),
						"new_parent_path": friendly_new_parent_path,
						"node_type": prepared["node_type"]
					})
	undo_redo.commit_action()
	editor_interface.mark_scene_as_unsaved()

	return {
		"status": "success",
		"label": label,
		"operation_count": result_operations.size(),
		"operations": result_operations
	}

func _register_audit_scene_node_persistence(server_core: RefCounted) -> void:
	server_core.register_tool(
		"audit_scene_node_persistence",
		"Audit node owner and persistence state for the currently edited scene. Reports missing or invalid owner relationships that affect scene saving and inheritance.",
		{
			"type": "object",
			"properties": {}
		},
		Callable(self, "_tool_audit_scene_node_persistence"),
		{
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"scene_root_path": {"type": "string"},
				"total_nodes": {"type": "integer"},
				"persistent_node_count": {"type": "integer"},
				"issue_count": {"type": "integer"},
				"nodes": {"type": "array"},
				"issues": {"type": "array"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Node-Advanced"
	)

func _tool_audit_scene_node_persistence(params: Dictionary) -> Dictionary:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	var nodes: Array = []
	var issues: Array = []
	_collect_scene_persistence_entries(scene_root, scene_root, nodes, issues)

	var persistent_node_count: int = 0
	for entry in nodes:
		if bool(entry.get("is_persistent", false)):
			persistent_node_count += 1

	return {
		"scene_path": String(scene_root.scene_file_path),
		"scene_root_path": _make_friendly_path(scene_root, scene_root),
		"total_nodes": nodes.size(),
		"persistent_node_count": persistent_node_count,
		"issue_count": issues.size(),
		"nodes": nodes,
		"issues": issues
	}

func _register_audit_scene_inheritance(server_core: RefCounted) -> void:
	server_core.register_tool(
		"audit_scene_inheritance",
		"Audit inherited or instanced scene structure for the current scene. Classifies local nodes, instance roots, inherited instance content, and local additions inside instanced subtrees.",
		{
			"type": "object",
			"properties": {}
		},
		Callable(self, "_tool_audit_scene_inheritance"),
		{
			"type": "object",
			"properties": {
				"scene_path": {"type": "string"},
				"scene_root_path": {"type": "string"},
				"node_count": {"type": "integer"},
				"instance_root_count": {"type": "integer"},
				"issue_count": {"type": "integer"},
				"instance_roots": {"type": "array"},
				"nodes": {"type": "array"},
				"issues": {"type": "array"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Node-Advanced"
	)

func _tool_audit_scene_inheritance(params: Dictionary) -> Dictionary:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	var nodes: Array = []
	var instance_roots: Array = []
	var issues: Array = []
	_collect_scene_inheritance_entries(scene_root, scene_root, nodes, instance_roots, issues)

	return {
		"scene_path": String(scene_root.scene_file_path),
		"scene_root_path": _make_friendly_path(scene_root, scene_root),
		"node_count": nodes.size(),
		"instance_root_count": instance_roots.size(),
		"issue_count": issues.size(),
		"instance_roots": instance_roots,
		"nodes": nodes,
		"issues": issues
	}

func _register_get_node_properties(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_node_properties",
		"Get all properties of a specific node in the scene tree.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the node (e.g. '/root/MainScene/Player')"
				}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_get_node_properties"),
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"node_type": {"type": "string"},
				"properties": {"type": "object"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"core", "Node-Read"
	)

func _tool_get_node_properties(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var target_node: Node = _resolve_node_path(node_path)
	
	if not target_node:
		return {"error": "Node not found: " + node_path}
	
	var properties: Dictionary = {}
	var property_list: Array = target_node.get_property_list()
	
	for property_dict in property_list:
		var prop_name: String = property_dict.get("name", "")
		if prop_name.begins_with("__"):
			continue
		var usage_flags: int = property_dict.get("usage", 0)
		if usage_flags & 128 or usage_flags & 64 or usage_flags & 256:
			continue
		var value = target_node.get(prop_name)
		properties[prop_name] = _serialize_value(value)
	
	return {
		"node_path": node_path,
		"node_type": target_node.get_class(),
		"properties": properties
	}

func _register_list_nodes(server_core: RefCounted) -> void:
	server_core.register_tool(
		"list_nodes",
		"List all nodes in the current scene or under a specific parent node.",
		{
			"type": "object",
			"properties": {
				"parent_path": {
					"type": "string",
					"description": "Optional path to the parent node. If not provided, lists all nodes in the scene."
				},
				"recursive": {
					"type": "boolean",
					"description": "Whether to list nodes recursively. Default is true."
				}
			}
		},
		Callable(self, "_tool_list_nodes"),
		{
			"type": "object",
			"properties": {
				"nodes": {"type": "array", "items": {"type": "string"}},
				"count": {"type": "integer"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"core", "Node-Read"
	)

func _tool_list_nodes(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var recursive: bool = params.get("recursive", true)
	
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}
	
	var start_node: Node = _get_user_scene_root()
	if not start_node:
		return {"error": "No scene is currently open"}
	
	if not parent_path.is_empty() and parent_path != "/root":
		start_node = _resolve_node_path(parent_path)
		if not start_node:
			return {"error": "Parent node not found: " + parent_path}
	
	var nodes_list: Array[String] = []
	_collect_nodes(start_node, "", recursive, nodes_list, scene_root)
	
	return {
		"nodes": nodes_list,
		"count": nodes_list.size()
	}

func _register_get_scene_tree(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_scene_tree",
		"Get the complete scene tree hierarchy starting from the scene root. Returns full tree structure with node types.",
		{
			"type": "object",
			"properties": {
				"max_depth": {
					"type": "integer",
					"description": "Maximum depth to traverse. -1 means no limit."
				}
			}
		},
		Callable(self, "_tool_get_scene_tree"),
		{
			"type": "object",
			"properties": {
				"scene_name": {"type": "string"},
				"tree": {"type": "object"},
				"total_nodes": {"type": "integer"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"core", "Node-Read"
	)

func _tool_get_scene_tree(params: Dictionary) -> Dictionary:
	var max_depth: int = params.get("max_depth", -1)
	
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}
	
	var tree: Dictionary = _build_scene_tree_node(scene_root, 0, max_depth, scene_root)
	var total_nodes: int = _count_all_nodes(scene_root)
	
	return {
		"scene_name": scene_root.name,
		"tree": tree,
		"total_nodes": total_nodes
	}

func _get_editor_interface() -> EditorInterface:
	if _editor_interface:
		return _editor_interface
	if Engine.has_meta("GodotMCPPlugin"):
		var plugin = Engine.get_meta("GodotMCPPlugin")
		if plugin and plugin.has_method("get_editor_interface"):
			return plugin.get_editor_interface()
	return null

func _get_user_scene_root() -> Node:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return null
	
	var scene_root: Node = editor_interface.get_edited_scene_root()
	if scene_root and not scene_root.name.begins_with("@") and scene_root.get_class() != "PanelContainer":
		return scene_root
	
	var open_scene_roots: Array = editor_interface.get_open_scene_roots()
	for root in open_scene_roots:
		var node_root: Node = root
		if node_root and not node_root.name.begins_with("@") and node_root.get_class() != "PanelContainer":
			return node_root
	
	return scene_root

static func _make_friendly_path(node: Node, scene_root: Node) -> String:
	if not scene_root:
		return str(node.get_path())
	if node == scene_root:
		return "/root/" + scene_root.name
	var node_path: String = str(node.get_path())
	var root_path: String = str(scene_root.get_path())
	if node_path.begins_with(root_path + "/"):
		return "/root/" + scene_root.name + node_path.substr(root_path.length())
	return node_path

static func _append_child_path(parent_path: String, child_name: String) -> String:
	if parent_path.is_empty() or parent_path == "/":
		return "/" + child_name
	if parent_path.ends_with("/"):
		return parent_path + child_name
	return parent_path + "/" + child_name

static func _collect_nodes(node: Node, path: String, recursive: bool, result: Array[String], scene_root: Node = null) -> void:
	var node_path: String = _make_friendly_path(node, scene_root)
	result.append(node_path)
	if recursive:
		for child_index in range(node.get_child_count()):
			var child: Node = node.get_child(child_index)
			_collect_nodes(child, node_path, recursive, result, scene_root)

func _convert_value_for_property(node: Node, property_name: String, value: Variant) -> Variant:
	if value == null:
		return value
	
	var property_type: int = TYPE_NIL
	for prop in node.get_property_list():
		if prop["name"] == property_name:
			property_type = prop["type"]
			break
	
	if property_type == TYPE_NIL:
		return value
	
	match property_type:
		TYPE_VECTOR2:
			if value is Dictionary:
				return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
			if value is String:
				var parsed: Dictionary = _parse_key_value_string(value)
				if not parsed.is_empty():
					return Vector2(float(parsed.get("x", 0.0)), float(parsed.get("y", 0.0)))
				var parts: PackedStringArray = _strip_constructor_prefix(value).replace("(", "").replace(")", "").replace(" ", "").split(",")
				if parts.size() >= 2:
					return Vector2(float(parts[0]), float(parts[1]))
		TYPE_VECTOR2I:
			if value is Dictionary:
				return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
			if value is String:
				var parts: PackedStringArray = _strip_constructor_prefix(value).replace("(", "").replace(")", "").replace(" ", "").split(",")
				if parts.size() >= 2:
					return Vector2i(int(parts[0]), int(parts[1]))
		TYPE_VECTOR3:
			if value is Dictionary:
				return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
			if value is String:
				var parsed: Dictionary = _parse_key_value_string(value)
				if not parsed.is_empty():
					return Vector3(float(parsed.get("x", 0.0)), float(parsed.get("y", 0.0)), float(parsed.get("z", 0.0)))
				var parts: PackedStringArray = _strip_constructor_prefix(value).replace("(", "").replace(")", "").replace(" ", "").split(",")
				if parts.size() >= 3:
					return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		TYPE_VECTOR3I:
			if value is Dictionary:
				return Vector3i(int(value.get("x", 0)), int(value.get("y", 0)), int(value.get("z", 0)))
			if value is String:
				var parts: PackedStringArray = _strip_constructor_prefix(value).replace("(", "").replace(")", "").replace(" ", "").split(",")
				if parts.size() >= 3:
					return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		TYPE_COLOR:
			if value is Dictionary:
				return Color(float(value.get("r", 0.0)), float(value.get("g", 0.0)), float(value.get("b", 0.0)), float(value.get("a", 1.0)))
			if value is String:
				if value.begins_with("#"):
					return Color(value)
				return Color(value)
		TYPE_BOOL:
			if value is String:
				return value.to_lower() == "true"
			if value is int or value is float:
				return value != 0
		TYPE_INT:
			if value is String:
				return int(value)
			if value is float:
				return int(value)
		TYPE_FLOAT:
			if value is String:
				return float(value)
			if value is int:
				return float(value)
		TYPE_RECT2:
			if value is Dictionary:
				return Rect2(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("w", 0.0)), float(value.get("h", 0.0)))
		TYPE_TRANSFORM2D:
			if value is Dictionary:
				var t: Transform2D = Transform2D()
				if value.has("rotation"):
					t = t.rotated(float(value["rotation"]))
				if value.has("origin"):
					var origin: Dictionary = value["origin"]
					t.origin = Vector2(float(origin.get("x", 0.0)), float(origin.get("y", 0.0)))
				return t
		TYPE_NODE_PATH:
			if value is String:
				return NodePath(value)
		TYPE_OBJECT:
			if value is String:
				if value.begins_with("res://"):
					var loaded_resource: Resource = load(value)
					if loaded_resource:
						return loaded_resource
				if ClassDB.class_exists(value) and ClassDB.is_parent_class(value, "Resource"):
					return ClassDB.instantiate(value)
	
	return value

func _parse_key_value_string(value: String) -> Dictionary:
	if not (value.begins_with("{") and value.ends_with("}")):
		return {}
	var inner: String = value.substr(1, value.length() - 2).replace(" ", "")
	var result: Dictionary = {}
	var entries: PackedStringArray = inner.split(",")
	for entry in entries:
		var kv: PackedStringArray = entry.split(":")
		if kv.size() == 2:
			result[kv[0]] = kv[1]
	return result

static func _strip_constructor_prefix(value: String) -> String:
	var trimmed: String = value.strip_edges()
	var open_index: int = trimmed.find("(")
	if open_index <= 0:
		return trimmed
	var prefix: String = trimmed.substr(0, open_index)
	if prefix.is_valid_identifier():
		return trimmed.substr(open_index)
	return trimmed

static func _serialize_value(value: Variant) -> Variant:
	if value == null:
		return null
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR4:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(_serialize_value(item))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in value:
				result[str(key)] = _serialize_value(value[key])
			return result
		TYPE_OBJECT:
			var resource := value as Resource
			if resource:
				return {
					"type": "Resource",
					"resource_type": resource.get_class(),
					"resource_path": resource.resource_path,
					"resource_name": resource.resource_name,
					"resource_local_to_scene": resource.resource_local_to_scene
				}
			return str(value)
		_:
			return str(value)

func _collect_scene_persistence_entries(node: Node, scene_root: Node, nodes: Array, issues: Array) -> void:
	var owner: Node = node.owner
	var owner_path: String = _make_friendly_path(owner, scene_root) if owner else ""
	var node_path: String = _make_friendly_path(node, scene_root)
	var is_scene_root: bool = node == scene_root
	var node_entry: Dictionary = {
		"node_path": node_path,
		"node_name": String(node.name),
		"node_type": node.get_class(),
		"owner_path": owner_path,
		"is_persistent": owner != null or is_scene_root,
		"is_scene_root": is_scene_root,
		"scene_file_path": String(node.scene_file_path)
	}
	nodes.append(node_entry)

	if not is_scene_root:
		if owner == null:
			issues.append({
				"node_path": node_path,
				"issue_code": "missing_owner",
				"message": "Node has no owner and will not be saved with the scene."
			})
		elif not _is_owner_chain_valid(node, owner):
			issues.append({
				"node_path": node_path,
				"issue_code": "owner_not_ancestor",
				"message": "Node owner is not an ancestor in the scene tree.",
				"owner_path": owner_path
			})

	for child in node.get_children():
		_collect_scene_persistence_entries(child, scene_root, nodes, issues)

func _collect_scene_inheritance_entries(node: Node, scene_root: Node, nodes: Array, instance_roots: Array, issues: Array) -> void:
	var node_path: String = _make_friendly_path(node, scene_root)
	var owner: Node = node.owner
	var owner_path: String = _make_friendly_path(owner, scene_root) if owner else ""
	var direct_scene_file_path: String = String(node.scene_file_path)
	var nearest_instance_root: Node = _find_nearest_instance_root(node, scene_root)
	var nearest_instance_root_path: String = _make_friendly_path(nearest_instance_root, scene_root) if nearest_instance_root else ""
	var source_scene_path: String = String(nearest_instance_root.scene_file_path) if nearest_instance_root else direct_scene_file_path

	var relationship: String = "local"
	if node == scene_root:
		relationship = "scene_root"
	elif not direct_scene_file_path.is_empty():
		relationship = "instance_root"
	elif nearest_instance_root:
		if owner == scene_root or owner == null:
			relationship = "local_override"
		else:
			relationship = "inherited_content"

	var node_entry: Dictionary = {
		"node_path": node_path,
		"node_name": String(node.name),
		"node_type": node.get_class(),
		"owner_path": owner_path,
		"scene_file_path": direct_scene_file_path,
		"relationship": relationship,
		"instance_root_path": nearest_instance_root_path,
		"source_scene_path": source_scene_path
	}
	nodes.append(node_entry)

	if relationship == "instance_root":
		instance_roots.append({
			"node_path": node_path,
			"node_name": String(node.name),
			"node_type": node.get_class(),
			"source_scene_path": direct_scene_file_path
		})

	if nearest_instance_root and relationship == "inherited_content":
		if owner == scene_root or (owner and not nearest_instance_root.is_ancestor_of(owner) and owner != nearest_instance_root):
			issues.append({
				"node_path": node_path,
				"issue_code": "unexpected_instance_owner",
				"owner_path": owner_path,
				"instance_root_path": nearest_instance_root_path,
				"message": "Inherited instance content should be owned by the instance root or one of its ancestors."
			})

	for child in node.get_children():
		_collect_scene_inheritance_entries(child, scene_root, nodes, instance_roots, issues)

func _is_owner_chain_valid(node: Node, owner: Node) -> bool:
	var current: Node = node.get_parent()
	while current:
		if current == owner:
			return true
		current = current.get_parent()
	return false

func _find_nearest_instance_root(node: Node, scene_root: Node) -> Node:
	var current: Node = node
	while current and current != scene_root:
		if not String(current.scene_file_path).is_empty():
			return current
		current = current.get_parent()
	return null

static func _build_scene_tree_node(node: Node, current_depth: int, max_depth: int, scene_root: Node = null) -> Dictionary:
	var node_info: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": _make_friendly_path(node, scene_root),
		"child_count": node.get_child_count()
	}
	
	var important_props: Array[String] = ["visible", "position", "rotation", "scale", "modulate"]
	var properties: Dictionary = {}
	for prop_name in important_props:
		if prop_name in node:
			properties[prop_name] = _serialize_value(node.get(prop_name))
	if properties.size() > 0:
		node_info["properties"] = properties
	
	if max_depth >= 0 and current_depth >= max_depth:
		if node.get_child_count() > 0:
			node_info["children_truncated"] = true
		return node_info
	
	if node.get_child_count() > 0:
		var children: Array[Dictionary] = []
		for child_index in range(node.get_child_count()):
			var child: Node = node.get_child(child_index)
			var child_info: Dictionary = _build_scene_tree_node(child, current_depth + 1, max_depth, scene_root)
			children.append(child_info)
		node_info["children"] = children
	
	return node_info

static func _count_all_nodes(node: Node) -> int:
	var count: int = 1
	for child_index in range(node.get_child_count()):
		var child: Node = node.get_child(child_index)
		count += _count_all_nodes(child)
	return count

# ===========================================
# 节点工具增强 - 新增工具
# ===========================================

func _register_duplicate_node(server_core: RefCounted) -> void:
	server_core.register_tool(
		"duplicate_node",
		"Duplicate a node and its children in the scene tree. Returns the new node path.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the node to duplicate (e.g. '/root/MainScene/Player')"
				},
				"new_name": {
					"type": "string",
					"description": "Name for the duplicated node. If empty, auto-generates a unique name."
				}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_duplicate_node"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"original_path": {"type": "string"},
				"new_node_path": {"type": "string"},
				"new_node_name": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"core", "Node-Write"
	)

func _tool_duplicate_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var new_name: String = params.get("new_name", "")

	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	var parent: Node = target_node.get_parent()
	if not parent:
		return {"error": "Cannot duplicate root node"}

	var new_node: Node = target_node.duplicate()
	if not new_node:
		return {"error": "Failed to duplicate node"}

	if not new_name.is_empty():
		new_node.name = new_name
	else:
		var base_name: String = str(target_node.name)
		var counter: int = 2
		var candidate_name: String = base_name + str(counter)
		while parent.has_node(candidate_name):
			counter += 1
			candidate_name = base_name + str(counter)
		new_node.name = candidate_name

	parent.add_child(new_node)

	var scene_root: Node = _get_user_scene_root()
	if scene_root:
		new_node.owner = scene_root

	editor_interface.mark_scene_as_unsaved()

	return {
		"status": "success",
		"original_path": node_path,
		"new_node_path": _make_friendly_path(new_node, scene_root),
		"new_node_name": str(new_node.name)
	}

func _register_move_node(server_core: RefCounted) -> void:
	server_core.register_tool(
		"move_node",
		"Move a node to a new parent in the scene tree. Optionally preserves global transform.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the node to move (e.g. '/root/MainScene/Player')"
				},
				"new_parent_path": {
					"type": "string",
					"description": "Path to the new parent node (e.g. '/root/MainScene/Enemies')"
				},
				"keep_global_transform": {
					"type": "boolean",
					"description": "Whether to preserve global transform. Default is true."
				}
			},
			"required": ["node_path", "new_parent_path"]
		},
		Callable(self, "_tool_move_node"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"node_path": {"type": "string"},
				"new_parent_path": {"type": "string"},
				"new_node_path": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"core", "Node-Write"
	)

func _tool_move_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var new_parent_path: String = params.get("new_parent_path", "")
	var keep_global_transform: bool = params.get("keep_global_transform", true)

	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	if new_parent_path.is_empty():
		return {"error": "Missing required parameter: new_parent_path"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	var new_parent: Node = _resolve_node_path(new_parent_path)
	if not new_parent:
		return {"error": "New parent not found: " + new_parent_path}

	if target_node == new_parent:
		return {"error": "Cannot move node to itself"}

	if target_node.is_ancestor_of(new_parent):
		return {"error": "Cannot move node to its own descendant"}

	if keep_global_transform:
		target_node.reparent(new_parent, true)
	else:
		var old_parent: Node = target_node.get_parent()
		if old_parent:
			old_parent.remove_child(target_node)
		new_parent.add_child(target_node)

	var scene_root: Node = _get_user_scene_root()
	if scene_root:
		target_node.owner = scene_root

	editor_interface.mark_scene_as_unsaved()

	return {
		"status": "success",
		"node_path": node_path,
		"new_parent_path": new_parent_path,
		"new_node_path": _make_friendly_path(target_node, scene_root)
	}

func _register_rename_node(server_core: RefCounted) -> void:
	server_core.register_tool(
		"rename_node",
		"Rename a node in the scene tree. The new name must be unique among siblings.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the node to rename (e.g. '/root/MainScene/Player')"
				},
				"new_name": {
					"type": "string",
					"description": "New name for the node"
				}
			},
			"required": ["node_path", "new_name"]
		},
		Callable(self, "_tool_rename_node"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"old_name": {"type": "string"},
				"new_name": {"type": "string"},
				"node_path": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"core", "Node-Write"
	)

func _tool_rename_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var new_name: String = params.get("new_name", "")

	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	if new_name.is_empty():
		return {"error": "Missing required parameter: new_name"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	var old_name: String = str(target_node.name)

	if old_name == new_name:
		return {
			"status": "success",
			"old_name": old_name,
			"new_name": new_name,
			"node_path": node_path
		}

	var parent: Node = target_node.get_parent()
	if parent and parent.has_node(new_name):
		return {"error": "Name '" + new_name + "' already exists in parent"}

	target_node.name = new_name

	var scene_root: Node = _get_user_scene_root()
	editor_interface.mark_scene_as_unsaved()

	return {
		"status": "success",
		"old_name": old_name,
		"new_name": new_name,
		"node_path": _make_friendly_path(target_node, scene_root)
	}

func _register_add_resource(server_core: RefCounted) -> void:
	server_core.register_tool(
		"add_resource",
		"Add a resource child node (e.g. CollisionShape2D, MeshInstance3D) to a target node.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the target parent node (e.g. '/root/MainScene/Player')"
				},
				"resource_type": {
					"type": "string",
					"description": "Type of resource node to add (e.g. 'CollisionShape2D', 'CollisionShape3D', 'MeshInstance3D', 'Sprite2D')"
				},
				"resource_name": {
					"type": "string",
					"description": "Name for the new resource node. If empty, uses the type as name."
				},
				"properties": {
					"type": "object",
					"description": "Optional property values to set on the new node after creation (e.g. {\"shape\": \"RectangleShape2D\"})"
				}
			},
			"required": ["node_path", "resource_type"]
		},
		Callable(self, "_tool_add_resource"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"node_path": {"type": "string"},
				"resource_node_path": {"type": "string"},
				"resource_type": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"supplementary", "Node-Write-Advanced"
	)

func _tool_add_resource(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var resource_type: String = params.get("resource_type", "")
	var resource_name: String = params.get("resource_name", "")

	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	if resource_type.is_empty():
		return {"error": "Missing required parameter: resource_type"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	if not ClassDB.class_exists(resource_type):
		return {"error": "Unknown resource type: " + resource_type}

	if not ClassDB.is_parent_class(resource_type, "Node"):
		return {"error": "Resource type must be a Node type: " + resource_type}

	var resource_node: Node = ClassDB.instantiate(resource_type)
	if not resource_node:
		return {"error": "Failed to instantiate resource type: " + resource_type}

	var final_name: String = resource_name
	if final_name.is_empty():
		final_name = resource_type
	if target_node.has_node(final_name):
		var suffix: int = 2
		while target_node.has_node(final_name + str(suffix)):
			suffix += 1
		final_name = final_name + str(suffix)
	resource_node.name = final_name

	target_node.add_child(resource_node)

	var scene_root: Node = _get_user_scene_root()
	if scene_root:
		resource_node.owner = scene_root
	
	# Apply optional property values after creation
	var properties: Dictionary = params.get("properties", {})
	if properties is Dictionary and not properties.is_empty():
		for prop_name in properties:
			var prop_value: Variant = properties[prop_name]
			if prop_name in resource_node:
				var converted: Variant = _convert_value_for_property(resource_node, prop_name, prop_value)
				resource_node.set(prop_name, converted)

	editor_interface.mark_scene_as_unsaved()

	return {
		"status": "success",
		"node_path": node_path,
		"resource_node_path": _make_friendly_path(resource_node, scene_root),
		"resource_type": resource_node.get_class()
	}

func _register_set_anchor_preset(server_core: RefCounted) -> void:
	server_core.register_tool(
		"set_anchor_preset",
		"Set the anchor preset for a Control node. Only works on Control-derived nodes.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the Control node (e.g. '/root/MainScene/UI/Panel')"
				},
				"preset": {
					"type": "integer",
					"description": "LayoutPreset value (0-15): 0=TOP_LEFT, 1=TOP_RIGHT, 2=BOTTOM_LEFT, 3=BOTTOM_RIGHT, 4=CENTER_LEFT, 5=CENTER_TOP, 6=CENTER_RIGHT, 7=CENTER_BOTTOM, 8=CENTER, 9=LEFT_WIDE, 10=TOP_WIDE, 11=RIGHT_WIDE, 12=BOTTOM_WIDE, 13=VCENTER_WIDE, 14=HCENTER_WIDE, 15=FULL_RECT"
				},
				"keep_offsets": {
					"type": "boolean",
					"description": "Whether to keep current offsets. Default is false."
				}
			},
			"required": ["node_path", "preset"]
		},
		Callable(self, "_tool_set_anchor_preset"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"preset_name": {"type": "string"},
				"preset_value": {"type": "integer"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Node-Write-Advanced"
	)

func _tool_set_anchor_preset(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var preset: int = params.get("preset", 0)
	var keep_offsets: bool = params.get("keep_offsets", false)

	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	if not target_node is Control:
		return {"error": "Node is not a Control: " + node_path}

	if preset < 0 or preset > 15:
		return {"error": "Invalid preset value. Must be 0-15, got: " + str(preset)}

	var preset_names: Dictionary = {
		0: "TOP_LEFT", 1: "TOP_RIGHT", 2: "BOTTOM_LEFT", 3: "BOTTOM_RIGHT",
		4: "CENTER_LEFT", 5: "CENTER_TOP", 6: "CENTER_RIGHT", 7: "CENTER_BOTTOM",
		8: "CENTER", 9: "LEFT_WIDE", 10: "TOP_WIDE", 11: "RIGHT_WIDE",
		12: "BOTTOM_WIDE", 13: "VCENTER_WIDE", 14: "HCENTER_WIDE", 15: "FULL_RECT"
	}

	var control: Control = target_node as Control
	control.set_anchors_preset(preset, keep_offsets)

	editor_interface.mark_scene_as_unsaved()

	return {
		"status": "success",
		"preset_name": preset_names.get(preset, "UNKNOWN"),
		"preset_value": preset
	}

func _register_connect_signal(server_core: RefCounted) -> void:
	server_core.register_tool(
		"connect_signal",
		"Connect a signal from one node to a method on another node.",
		{
			"type": "object",
			"properties": {
				"emitter_path": {
					"type": "string",
					"description": "Path to the node that emits the signal (e.g. '/root/MainScene/Button')"
				},
				"signal_name": {
					"type": "string",
					"description": "Name of the signal to connect (e.g. 'pressed', 'body_entered')"
				},
				"receiver_path": {
					"type": "string",
					"description": "Path to the node that receives the signal (e.g. '/root/MainScene/Game')"
				},
				"receiver_method": {
					"type": "string",
					"description": "Name of the method to call when the signal fires (e.g. '_on_button_pressed')"
				},
				"flags": {
					"type": "integer",
					"description": "Connection flags: 0=DEFAULT, 1=DEFERRED, 2=ONE_SHOT, 4=PERSIST. Default is 0."
				}
			},
			"required": ["emitter_path", "signal_name", "receiver_path", "receiver_method"]
		},
		Callable(self, "_tool_connect_signal"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"emitter": {"type": "string"},
				"signal": {"type": "string"},
				"receiver": {"type": "string"},
				"method": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"supplementary", "Node-Write-Advanced"
	)

func _tool_connect_signal(params: Dictionary) -> Dictionary:
	var emitter_path: String = params.get("emitter_path", "")
	var signal_name: String = params.get("signal_name", "")
	var receiver_path: String = params.get("receiver_path", "")
	var receiver_method: String = params.get("receiver_method", "")
	var flags: int = params.get("flags", 0)

	# Collect all missing required parameters at once
	var missing_params: Array[String] = []
	if emitter_path.is_empty():
		missing_params.append("emitter_path")
	if signal_name.is_empty():
		missing_params.append("signal_name")
	if receiver_path.is_empty():
		missing_params.append("receiver_path")
	if receiver_method.is_empty():
		missing_params.append("receiver_method")
	if missing_params.size() > 0:
		return {"error": "Missing required parameters: " + ", ".join(missing_params)}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var emitter: Node = _resolve_node_path(emitter_path)
	if not emitter:
		return {"error": "Emitter not found: " + emitter_path}

	var receiver: Node = _resolve_node_path(receiver_path)
	if not receiver:
		return {"error": "Receiver not found: " + receiver_path}

	var signal_list: Array = emitter.get_signal_list()
	var signal_exists: bool = false
	for sig in signal_list:
		if sig.get("name", "") == signal_name:
			signal_exists = true
			break

	if not signal_exists:
		return {"error": "Signal '" + signal_name + "' not found on " + emitter_path}

	var callable: Callable = Callable(receiver, receiver_method)

	if emitter.is_connected(signal_name, callable):
		return {"error": "Signal '" + signal_name + "' is already connected to " + receiver_method}

	var err: int = emitter.connect(signal_name, callable, flags)
	if err != OK:
		return {"error": "Failed to connect signal: error code " + str(err)}

	editor_interface.mark_scene_as_unsaved()

	var result: Dictionary = {
		"status": "success",
		"emitter": emitter_path,
		"signal": signal_name,
		"receiver": receiver_path,
		"method": receiver_method
	}
	if flags & CONNECT_PERSIST:
		result["warning"] = "PERSIST flag is set. If the receiver script also connects this signal in _ready(), it will fire twice at runtime."
	return result

func _register_disconnect_signal(server_core: RefCounted) -> void:
	server_core.register_tool(
		"disconnect_signal",
		"Disconnect a signal connection between two nodes.",
		{
			"type": "object",
			"properties": {
				"emitter_path": {
					"type": "string",
					"description": "Path to the node that emits the signal (e.g. '/root/MainScene/Button')"
				},
				"signal_name": {
					"type": "string",
					"description": "Name of the signal to disconnect (e.g. 'pressed')"
				},
				"receiver_path": {
					"type": "string",
					"description": "Path to the node that receives the signal (e.g. '/root/MainScene/Game')"
				},
				"receiver_method": {
					"type": "string",
					"description": "Name of the method that was connected (e.g. '_on_button_pressed')"
				}
			},
			"required": ["emitter_path", "signal_name", "receiver_path", "receiver_method"]
		},
		Callable(self, "_tool_disconnect_signal"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"disconnected": {"type": "boolean"},
				"emitter": {"type": "string"},
				"signal": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Node-Write-Advanced"
	)

func _tool_disconnect_signal(params: Dictionary) -> Dictionary:
	var emitter_path: String = params.get("emitter_path", "")
	var signal_name: String = params.get("signal_name", "")
	var receiver_path: String = params.get("receiver_path", "")
	var receiver_method: String = params.get("receiver_method", "")

	if emitter_path.is_empty():
		return {"error": "Missing required parameter: emitter_path"}
	if signal_name.is_empty():
		return {"error": "Missing required parameter: signal_name"}
	if receiver_path.is_empty():
		return {"error": "Missing required parameter: receiver_path"}
	if receiver_method.is_empty():
		return {"error": "Missing required parameter: receiver_method"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var emitter: Node = _resolve_node_path(emitter_path)
	if not emitter:
		return {"error": "Emitter not found: " + emitter_path}

	var receiver: Node = _resolve_node_path(receiver_path)
	if not receiver:
		return {"error": "Receiver not found: " + receiver_path}

	var callable: Callable = Callable(receiver, receiver_method)

	if not emitter.is_connected(signal_name, callable):
		return {
			"status": "not_connected",
			"disconnected": false,
			"emitter": emitter_path,
			"signal": signal_name,
			"message": "Connection does not exist"
		}

	emitter.disconnect(signal_name, callable)

	editor_interface.mark_scene_as_unsaved()

	return {
		"status": "success",
		"disconnected": true,
		"emitter": emitter_path,
		"signal": signal_name
	}

func _register_get_node_groups(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_node_groups",
		"Get all groups that a node belongs to.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the node (e.g. '/root/MainScene/Player')"
				}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_get_node_groups"),
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"groups": {"type": "array", "items": {"type": "string"}},
				"group_count": {"type": "integer"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Node-Advanced"
	)

func _tool_get_node_groups(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")

	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	var groups: Array[StringName] = target_node.get_groups()
	var groups_array: Array = []
	for group in groups:
		groups_array.append(str(group))

	return {
		"node_path": node_path,
		"groups": groups_array,
		"group_count": groups_array.size()
	}

func _register_set_node_groups(server_core: RefCounted) -> void:
	server_core.register_tool(
		"set_node_groups",
		"Set group memberships for a node. Can add and/or remove groups.",
		{
			"type": "object",
			"properties": {
				"node_path": {
					"type": "string",
					"description": "Path to the node (e.g. '/root/MainScene/Player')"
				},
				"groups": {
					"type": "array",
					"items": {"type": "string"},
					"description": "List of group names to add the node to."
				},
				"remove_groups": {
					"type": "array",
					"items": {"type": "string"},
					"description": "List of group names to remove the node from."
				},
				"persistent": {
					"type": "boolean",
					"description": "Whether group membership persists when saving the scene. Default is false."
				},
				"clear_existing": {
					"type": "boolean",
					"description": "Whether to clear all existing groups before adding new ones. Default is false."
				}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_set_node_groups"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"added_groups": {"type": "array", "items": {"type": "string"}},
				"removed_groups": {"type": "array", "items": {"type": "string"}},
				"current_groups": {"type": "array", "items": {"type": "string"}}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"supplementary", "Node-Write-Advanced"
	)

func _tool_set_node_groups(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var groups: Array = params.get("groups", [])
	var remove_groups: Array = params.get("remove_groups", [])
	var persistent: bool = params.get("persistent", false)
	var clear_existing: bool = params.get("clear_existing", false)

	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	var added_groups: Array = []
	var removed_groups: Array = []

	if clear_existing:
		var current_groups: Array[StringName] = target_node.get_groups()
		for group in current_groups:
			target_node.remove_from_group(group)
			removed_groups.append(str(group))

	for group_name in remove_groups:
		if target_node.is_in_group(group_name):
			target_node.remove_from_group(group_name)
			removed_groups.append(group_name)

	for group_name in groups:
		if not target_node.is_in_group(group_name):
			target_node.add_to_group(group_name, persistent)
			added_groups.append(group_name)

	var current_groups: Array[StringName] = target_node.get_groups()
	var current_groups_array: Array = []
	for group in current_groups:
		current_groups_array.append(str(group))

	editor_interface.mark_scene_as_unsaved()

	return {
		"status": "success",
		"added_groups": added_groups,
		"removed_groups": removed_groups,
		"current_groups": current_groups_array
	}

func _register_find_nodes_in_group(server_core: RefCounted) -> void:
	server_core.register_tool(
		"find_nodes_in_group",
		"Find all nodes that belong to a specific group in the current scene.",
		{
			"type": "object",
			"properties": {
				"group": {
					"type": "string",
					"description": "Name of the group to search for (e.g. 'enemies', 'player')"
				},
				"node_type": {
					"type": "string",
					"description": "Optional filter by node type (e.g. 'Node2D', 'CharacterBody2D')"
				}
			},
			"required": ["group"]
		},
		Callable(self, "_tool_find_nodes_in_group"),
		{
			"type": "object",
			"properties": {
				"group": {"type": "string"},
				"nodes": {"type": "array"},
				"node_count": {"type": "integer"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Node-Advanced"
	)

func _tool_find_nodes_in_group(params: Dictionary) -> Dictionary:
	var group: String = params.get("group", "")
	var node_type: String = params.get("node_type", "")

	if group.is_empty():
		return {"error": "Missing required parameter: group"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	var nodes_array: Array[Node] = scene_root.get_tree().get_nodes_in_group(group)

	var result_nodes: Array = []
	var scene_root_ref: Node = scene_root

	for node in nodes_array:
		if not node_type.is_empty() and node.get_class() != node_type:
			continue

		var node_info: Dictionary = {
			"name": str(node.name),
			"type": node.get_class(),
			"path": _make_friendly_path(node, scene_root_ref)
		}
		result_nodes.append(node_info)

	return {
		"group": group,
		"nodes": result_nodes,
		"node_count": result_nodes.size()
	}
