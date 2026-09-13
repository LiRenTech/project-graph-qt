# scene_tools_native.gd - Scene Tools原生实现
# 根据godot-dev-guide添加完整的类型提示
# 根据mcp-builder添加outputSchema和annotations

@tool
class_name SceneToolsNative
extends RefCounted

const VIBE_CODING_POLICY = preload("res://addons/godot_mcp/utils/vibe_coding_policy.gd")

var _editor_interface: EditorInterface = null
var _scene_operation_in_progress: bool = false

func initialize(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface

func _get_editor_interface() -> EditorInterface:
	if _editor_interface:
		return _editor_interface
	if Engine.has_meta("GodotMCPPlugin"):
		var plugin = Engine.get_meta("GodotMCPPlugin")
		if plugin and plugin.has_method("get_editor_interface"):
			return plugin.get_editor_interface()
	return null

func _is_vibe_coding_mode() -> bool:
	if Engine.has_meta("GodotMCPPlugin"):
		var plugin = Engine.get_meta("GodotMCPPlugin")
		if plugin and plugin.get("vibe_coding_mode") != null:
			return bool(plugin.vibe_coding_mode)
	return true

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

# ============================================================================
# 工具注册
# ============================================================================

func register_tools(server_core: RefCounted) -> void:
	# 注册create_scene工具
	_register_create_scene(server_core)
	
	# 注册save_scene工具
	_register_save_scene(server_core)
	
	# 注册open_scene工具
	_register_open_scene(server_core)
	
	# 注册get_current_scene工具
	_register_get_current_scene(server_core)
	
	# 注册get_scene_structure工具
	_register_get_scene_structure(server_core)
	
	# 注册list_project_scenes工具
	_register_list_project_scenes(server_core)
	_register_list_open_scenes(server_core)
	_register_close_scene_tab(server_core)

# ============================================================================
# create_scene - 创建新场�?
# ============================================================================

func _register_create_scene(server_core: RefCounted) -> void:
	var tool_name: String = "create_scene"
	var description: String = "Create a new Godot scene with a root node. The scene is saved to the specified path."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"scene_path": {
				"type": "string",
				"description": "Path where the scene will be saved (e.g. 'res://scenes/NewScene.tscn')"
			},
			"root_node_type": {
				"type": "string",
				"description": "Type of the root node (e.g. 'Node3D', 'Node2D', 'Control'). Default is 'Node'.",
				"default": "Node"
			}
		},
		"required": ["scene_path"]
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"scene_path": {"type": "string"},
			"root_node_type": {"type": "string"}
		}
	}
	
	# annotations
	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": false,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_create_scene"),
						  output_schema, annotations,
						  "core", "Scene")

func _tool_create_scene(params: Dictionary) -> Dictionary:
	# 参数提取
	var scene_path: String = params.get("scene_path", "")
	var root_node_type: String = params.get("root_node_type", "Node")
	
	# 参数验证
	if scene_path.is_empty():
		return {"error": "Missing required parameter: scene_path"}
	
	# 使用PathValidator验证路径安全�?
	var validation: Dictionary = PathValidator.validate_file_path(scene_path, [".tscn"])
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	
	# 使用清理后的路径
	scene_path = validation["sanitized"]
	
	# 验证节点类型
	if not ClassDB.class_exists(root_node_type):
		return {"error": "Invalid node type: " + root_node_type}
	
	# 创建根节�?
	var root_node: Node = ClassDB.instantiate(root_node_type)
	root_node.name = scene_path.get_file().get_basename()
	
	# 创建PackedScene
	var packed_scene: PackedScene = PackedScene.new()
	
	# 设置owner并打�?
	root_node.owner = root_node  # 临时设置
	packed_scene.pack(root_node)
	
	# 保存场景
	var error: Error = ResourceSaver.save(packed_scene, scene_path)
	
	# 清理
	root_node.free()
	
	if error != OK:
		return {"error": "Failed to save scene: " + error_string(error)}
	
	return {
		"status": "success",
		"scene_path": scene_path,
		"root_node_type": root_node_type
	}

# ============================================================================
# save_scene - 保存当前场景
# ============================================================================

func _register_save_scene(server_core: RefCounted) -> void:
	var tool_name: String = "save_scene"
	var description: String = "Save the current scene to disk. If no path is provided, saves to the current scene's path."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"file_path": {
				"type": "string",
				"description": "Optional path to save the scene (e.g. 'res://scenes/MyScene.tscn'). If not provided, uses current scene path."
			}
		}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"saved_path": {"type": "string"},
			"operation": {"type": "string", "description": "'save' for same-path save, 'save_as' for different-path export"}
		}
	}
	
	# annotations
	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_save_scene"),
						  output_schema, annotations,
						  "core", "Scene")

func _tool_save_scene(params: Dictionary) -> Dictionary:
	if _scene_operation_in_progress:
		return {"error": "Scene operation in progress, please retry"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	var file_path: String = params.get("file_path", "")

	if file_path.is_empty():
		# Use current scene path
		var current_scene_path: String = scene_root.scene_file_path
		if current_scene_path.is_empty():
			return {"error": "Scene has no file path. Please provide a file_path parameter."}
		file_path = current_scene_path

	# Validate and sanitize path
	var validation: Dictionary = PathValidator.validate_file_path(file_path, [".tscn"])
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}

	file_path = validation["sanitized"]

	# Detect save-as: target path differs from current scene path
	var current_path: String = scene_root.scene_file_path
	var is_save_as: bool = not current_path.is_empty() and current_path != file_path

	# Pack the scene tree
	var packed_scene: PackedScene = PackedScene.new()
	var error: Error = packed_scene.pack(scene_root)

	if error != OK:
		return {"error": "Failed to pack scene: " + error_string(error)}

	# Save to file
	error = ResourceSaver.save(packed_scene, file_path)

	if error != OK:
		return {"error": "Failed to save scene: " + error_string(error)}

	return {
		"status": "success",
		"saved_path": file_path,
		"operation": "save_as" if is_save_as else "save"
	}

# ============================================================================
# open_scene - 打开场景
# ============================================================================

func _register_open_scene(server_core: RefCounted) -> void:
	var tool_name: String = "open_scene"
	var description: String = "Open a scene file from the project. Closes the current scene if one is open."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"scene_path": {
				"type": "string",
				"description": "Path to the scene file to open (e.g. 'res://scenes/Main.tscn')"
			},
			"allow_ui_focus": {
				"type": "boolean",
				"description": "Allow this call to change the active editor scene when Vibe Coding mode is enabled.",
				"default": false
			}
		},
		"required": ["scene_path"]
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"scene_path": {"type": "string"},
			"root_node_type": {"type": "string"},
			"verification_tip": {"type": "string"}
		}
	}
	
	# annotations
	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": true,  # will close current scene
		"idempotentHint": false,
		"openWorldHint": false
	}
	
	# register tool
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_open_scene"),
						  output_schema, annotations,
						  "core", "Scene")

func _tool_open_scene(params: Dictionary) -> Dictionary:
	var policy_result: Dictionary = VIBE_CODING_POLICY.evaluate_editor_focus(_is_vibe_coding_mode(), params)
	if policy_result.get("blocked", false):
		return policy_result

	if _scene_operation_in_progress:
		return {"error": "Scene operation in progress, please retry"}
	_scene_operation_in_progress = true
	
	var scene_path: String = params.get("scene_path", "")
	
	if scene_path.is_empty():
		_scene_operation_in_progress = false
		return {"error": "Missing required parameter: scene_path"}
	
	var validation: Dictionary = PathValidator.validate_file_path(scene_path, [".tscn"])
	if not validation["valid"]:
		_scene_operation_in_progress = false
		return {"error": "Invalid path: " + validation["error"]}
	
	scene_path = validation["sanitized"]
	
	if not FileAccess.file_exists(scene_path):
		_scene_operation_in_progress = false
		return {"error": "Scene file not found: " + scene_path}
	
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		_scene_operation_in_progress = false
		return {"error": "Editor interface not available"}
	
	editor_interface.open_scene_from_path(scene_path)

	var opened_scene_root: Node = _get_user_scene_root()
	if not opened_scene_root:
		_scene_operation_in_progress = false
		return {"error": "Failed to open scene: " + scene_path}

	var scene_root: Node = _get_user_scene_root()
	var root_type: String = scene_root.get_class() if scene_root else "Unknown"

	_scene_operation_in_progress = false
	return {
		"status": "success",
		"scene_path": scene_path,
		"root_node_type": root_type,
		"verification_tip": "Call get_editor_logs(source='editor_panel', type=['Error']) to check for scene loading errors. Then call get_current_scene() to confirm the correct scene is active."
	}

# ============================================================================
# get_current_scene - 获取当前场景信息
# ============================================================================

func _register_get_current_scene(server_core: RefCounted) -> void:
	var tool_name: String = "get_current_scene"
	var description: String = "Get information about the currently open scene, including name, path, and root node type."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"scene_name": {"type": "string"},
			"scene_path": {"type": "string"},
			"root_node_type": {"type": "string"},
			"node_count": {"type": "integer"},
			"is_modified": {"type": "boolean"}
		}
	}
	
	# annotations - readOnlyHint = true
	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_current_scene"),
						  output_schema, annotations,
						  "core", "Scene")

func _tool_get_current_scene(params: Dictionary) -> Dictionary:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	# 获取当前场景根节�?
	var scene_root: Node = _get_user_scene_root()
	
	if not scene_root:
		return {"error": "No scene is currently open"}
	
	# 获取场景信息
	var scene_name: String = scene_root.name
	var scene_path: String = scene_root.scene_file_path
	var root_node_type: String = scene_root.get_class()
	var node_count: int = _count_nodes(scene_root)
	
	var is_modified: bool = false
	var undo_redo_mgr: EditorUndoRedoManager = editor_interface.get_editor_undo_redo()
	if undo_redo_mgr and scene_root:
		var history_id: int = undo_redo_mgr.get_object_history_id(scene_root)
		var undo_redo: UndoRedo = undo_redo_mgr.get_history_undo_redo(history_id)
		if undo_redo:
			is_modified = undo_redo.has_undo()
	
	return {
		"scene_name": scene_name,
		"scene_path": scene_path,
		"root_node_type": root_node_type,
		"node_count": node_count,
		"is_modified": is_modified
	}

# ============================================================================
# get_scene_structure - 获取场景树结�?
# ============================================================================

func _register_get_scene_structure(server_core: RefCounted) -> void:
	var tool_name: String = "get_scene_structure"
	var description: String = "Get the complete structure of the current scene as a tree. Returns node types, names, and hierarchy."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"max_depth": {
				"type": "integer",
				"description": "Maximum depth to traverse. -1 means no limit."
			}
		}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"scene_name": {"type": "string"},
			"root_node": {"type": "object"},
			"total_nodes": {"type": "integer"}
		}
	}
	
	# annotations - readOnlyHint = true
	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema, 
						  Callable(self, "_tool_get_scene_structure"),
						  output_schema, annotations,
						  "supplementary", "Scene-Advanced")

func _tool_get_scene_structure(params: Dictionary) -> Dictionary:
	var max_depth: int = params.get("max_depth", -1)
	
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	# 获取场景根节�?
	var scene_root: Node = _get_user_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}
	
	# 构建场景结构
	var scene_structure: Dictionary = {
		"scene_name": scene_root.name,
		"root_node": _build_node_tree(scene_root, 0, max_depth, scene_root),
		"total_nodes": _count_nodes(scene_root)
	}
	
	return scene_structure

# 辅助函数：递归构建节点�?
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

static func _build_node_tree(node: Node, current_depth: int, max_depth: int, scene_root: Node = null) -> Dictionary:
	var node_info: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": _make_friendly_path(node, scene_root),
		"children": []
	}
	
	# 检查是否达到最大深�?
	if max_depth >= 0 and current_depth >= max_depth:
		node_info["children_truncated"] = true
		return node_info
	
	# 递归处理子节�?
	for child_index in range(node.get_child_count()):
		var child: Node = node.get_child(child_index)
		var child_tree: Dictionary = _build_node_tree(child, current_depth + 1, max_depth, scene_root)
		node_info["children"].append(child_tree)
	
	return node_info

# 辅助函数：计算节点总数
static func _count_nodes(node: Node) -> int:
	var count: int = 1  # 当前节点
	
	for child_index in range(node.get_child_count()):
		var child: Node = node.get_child(child_index)
		count += _count_nodes(child)
	
	return count

# ============================================================================
# list_project_scenes - 列出项目中的所有场�?
# ============================================================================

func _register_list_project_scenes(server_core: RefCounted) -> void:
	var tool_name: String = "list_project_scenes"
	var description: String = "List all scene files (.tscn) in the project. Returns paths relative to res://."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {
				"type": "string",
				"description": "Optional subpath to search (e.g. 'res://scenes/'). Default is 'res://'.",
				"default": "res://"
			}
		}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"scenes": {
				"type": "array",
				"items": {"type": "string"}
			},
			"count": {"type": "integer"}
		}
	}
	
	# annotations - readOnlyHint = true
	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_list_project_scenes"),
						  output_schema, annotations,
						  "supplementary", "Scene-Advanced")

func _tool_list_project_scenes(params: Dictionary) -> Dictionary:
	# 参数提取
	var search_path: String = params.get("search_path", "res://")
	
	# 使用PathValidator验证路径安全�?
	var validation: Dictionary = PathValidator.validate_directory_path(search_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	
	# 使用清理后的路径
	search_path = validation["sanitized"]
	
	# 转换为文件系统路�?
	var fs_path: String = search_path
	
	# 使用DirAccess递归查找所�?tscn文件
	var scenes: Array[String] = []
	_collect_scenes(fs_path, scenes)
	
	# 排序
	scenes.sort()
	
	return {
		"scenes": scenes,
		"count": scenes.size()
	}

# ============================================================================
# list_open_scenes - 列出当前已打开的场景 tab
# ============================================================================

func _register_list_open_scenes(server_core: RefCounted) -> void:
	var tool_name: String = "list_open_scenes"
	var description: String = "List scene tabs currently open in the Godot editor."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"active_scene": {"type": "string"},
			"count": {"type": "integer"},
			"open_scenes": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_list_open_scenes"),
						  output_schema, annotations,
						  "supplementary", "Scene-Advanced")

func _tool_list_open_scenes(params: Dictionary) -> Dictionary:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var open_scene_paths: PackedStringArray = editor_interface.get_open_scenes()
	var open_scene_roots: Array = editor_interface.get_open_scene_roots()
	var active_root: Node = editor_interface.get_edited_scene_root()
	var active_scene_path: String = active_root.scene_file_path if active_root else ""

	var open_scenes: Array = []
	for i in range(open_scene_paths.size()):
		var scene_path: String = str(open_scene_paths[i])
		var root_name: String = ""
		var root_type: String = ""
		if i < open_scene_roots.size():
			var root_node: Node = open_scene_roots[i]
			if root_node:
				root_name = root_node.name
				root_type = root_node.get_class()
		open_scenes.append({
			"index": i,
			"scene_path": scene_path,
			"root_name": root_name,
			"root_type": root_type,
			"is_active": scene_path == active_scene_path
		})

	return {
		"active_scene": active_scene_path,
		"count": open_scenes.size(),
		"open_scenes": open_scenes
	}

# ============================================================================
# close_scene_tab - 关闭当前或指定场景 tab
# ============================================================================

func _register_close_scene_tab(server_core: RefCounted) -> void:
	var tool_name: String = "close_scene_tab"
	var description: String = "Close the active scene tab, or activate a specified scene tab and close it."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"scene_path": {
				"type": "string",
				"description": "Optional scene path to close. If omitted, closes the currently active scene."
			},
			"allow_ui_focus": {
				"type": "boolean",
				"description": "Allow this call to activate or close editor scene tabs when Vibe Coding mode is enabled.",
				"default": false
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"closed_scene": {"type": "string"},
			"remaining_count": {"type": "integer"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": true,
		"idempotentHint": false,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_close_scene_tab"),
						  output_schema, annotations,
						  "supplementary", "Scene-Advanced")

func _tool_close_scene_tab(params: Dictionary) -> Dictionary:
	var policy_result: Dictionary = VIBE_CODING_POLICY.evaluate_editor_focus(_is_vibe_coding_mode(), params)
	if policy_result.get("blocked", false):
		return policy_result

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var scene_path: String = str(params.get("scene_path", "")).strip_edges()
	if not scene_path.is_empty():
		var validation: Dictionary = PathValidator.validate_file_path(scene_path, [".tscn"])
		if not validation["valid"]:
			return {"error": "Invalid path: " + validation["error"]}
		scene_path = validation["sanitized"]

		var open_scene_paths: PackedStringArray = editor_interface.get_open_scenes()
		if not open_scene_paths.has(scene_path):
			return {"error": "Scene is not currently open: " + scene_path}
		editor_interface.open_scene_from_path(scene_path)

	var active_root: Node = editor_interface.get_edited_scene_root()
	var closed_scene: String = active_root.scene_file_path if active_root else scene_path
	var close_error: Error = editor_interface.close_scene()
	if close_error != OK:
		return {"error": "Failed to close scene: " + error_string(close_error)}

	return {
		"status": "success",
		"closed_scene": closed_scene,
		"remaining_count": editor_interface.get_open_scenes().size()
	}

# 辅助函数：递归收集场景文件
func _collect_scenes(directory_path: String, result: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(directory_path)
	
	if not dir:
		return
	
	# 列出所有文件和目录
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	
	while not file_name.is_empty():
		# 跳过特殊目录
		if file_name != "." and file_name != "..":
			var full_path: String = directory_path
			if not full_path.ends_with("/"):
				full_path += "/"
			full_path += file_name
			
			if dir.current_is_dir():
				# 递归处理子目�?
				_collect_scenes(full_path, result)
			elif file_name.ends_with(".tscn"):
				# 添加场景文件
				result.append(full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
