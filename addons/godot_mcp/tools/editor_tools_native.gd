# editor_tools_native.gd - Editor Tools原生实现
# 根据godot-dev-guide添加完整的类型提示

@tool
class_name EditorToolsNative
extends RefCounted

const VIBE_CODING_POLICY = preload("res://addons/godot_mcp/utils/vibe_coding_policy.gd")

var _editor_interface: EditorInterface = null
var _editor_operation_in_progress: bool = false

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

func _get_debugger_bridge() -> RefCounted:
	if Engine.has_meta("GodotMCPPlugin"):
		var plugin = Engine.get_meta("GodotMCPPlugin")
		if plugin and plugin.has_method("get_debugger_bridge"):
			return plugin.get_debugger_bridge()
	return null

# True once a played game child has connected back to the editor's debug server.
# The editor only reports an active session when the play actually spawned and
# connected a child process — a missing/failed scene leaves it inactive.
func _has_active_debugger_session() -> bool:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return false
	for session in bridge.get_sessions_info():
		if bool(session.get("active", false)):
			return true
	return false

func _get_export_templates_root() -> String:
	var editor_interface: EditorInterface = _get_editor_interface()
	if editor_interface:
		var editor_paths: EditorPaths = editor_interface.get_editor_paths()
		if editor_paths:
			return editor_paths.get_export_templates_dir()
	var os_name: String = OS.get_name()
	if os_name == "Windows":
		var appdata: String = OS.get_environment("APPDATA")
		if not appdata.is_empty():
			return appdata.path_join("Godot").path_join("export_templates")
	elif os_name == "Linux" or os_name == "FreeBSD":
		var home: String = OS.get_environment("HOME")
		if not home.is_empty():
			return home.path_join(".local/share/godot/export_templates")
	elif os_name == "macOS":
		var home: String = OS.get_environment("HOME")
		if not home.is_empty():
			return home.path_join("Library/Application Support/Godot/export_templates")
	return ""

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

# ============================================================================
# 工具注册
# ============================================================================

func register_tools(server_core: RefCounted) -> void:
	_register_get_editor_state(server_core)
	_register_run_project(server_core)
	_register_stop_project(server_core)
	_register_get_selected_nodes(server_core)
	_register_select_node(server_core)
	_register_select_file(server_core)
	_register_get_inspector_properties(server_core)
	_register_set_editor_setting(server_core)
	_register_get_editor_screenshot(server_core)
	_register_get_signals(server_core)
	_register_reload_project(server_core)
	_register_list_export_presets(server_core)
	_register_inspect_export_templates(server_core)
	_register_validate_export_preset(server_core)
	_register_run_export(server_core)

# ============================================================================
# get_editor_state - 获取编辑器状态
# ============================================================================

func _register_get_editor_state(server_core: RefCounted) -> void:
	var tool_name: String = "get_editor_state"
	var description: String = "Get the current state of the Godot editor, including active scene and selection info."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"active_scene": {"type": "string"},
			"selected_nodes": {
				"type": "array",
				"items": {"type": "object"}
			},
			"editor_mode": {"type": "string"},
			"selected_count": {"type": "integer"}
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
						  Callable(self, "_tool_get_editor_state"),
						  output_schema, annotations,
						  "core", "Editor")

func _tool_get_editor_state(params: Dictionary) -> Dictionary:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var scene_root: Node = _get_user_scene_root()
	var active_scene: String = scene_root.name if scene_root else ""
	
	var selected_nodes: Array = []
	var selection: EditorSelection = editor_interface.get_selection()
	if selection:
		var selected: Array[Node] = selection.get_selected_nodes()
		for node in selected:
			var node_info: Dictionary = {
				"path": _make_friendly_path(node, scene_root),
				"type": node.get_class()
			}
			var node_script: Variant = node.get_script()
			if node_script and node_script is Script:
				node_info["script_path"] = node_script.resource_path
			selected_nodes.append(node_info)
	
	var editor_mode: String = "editor"
	if editor_interface.is_playing_scene():
		editor_mode = "playing"
	
	return {
		"active_scene": active_scene,
		"selected_nodes": selected_nodes,
		"editor_mode": editor_mode,
		"selected_count": selected_nodes.size()
	}

# ============================================================================
# run_project - 运行项目
# ============================================================================

func _register_run_project(server_core: RefCounted) -> void:
	var tool_name: String = "run_project"
	var description: String = "Run the current project or a specific scene. Launches the game in play mode."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"scene_path": {
				"type": "string",
				"description": "Optional path to a specific scene to run. If not provided, runs the main scene."
			},
			"allow_window": {
				"type": "boolean",
				"description": "Allow this call to open or control the runtime window when Vibe Coding mode is enabled.",
				"default": false
			}
		}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"mode": {"type": "string"},
			"scene": {"type": "string"},
			"session_active": {"type": "boolean"},
			"probe_ready": {"type": "boolean"}
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
						  Callable(self, "_tool_run_project"),
						  output_schema, annotations,
						  "core", "Editor")

func _tool_run_project(params: Dictionary) -> Dictionary:
	var policy_result: Dictionary = VIBE_CODING_POLICY.evaluate_runtime_window(_is_vibe_coding_mode(), params)
	if policy_result.get("blocked", false):
		return policy_result

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	if editor_interface.is_playing_scene():
		return {"error": "Project is already running. Stop it first with stop_project."}

	var scene_path: String = params.get("scene_path", "")
	var played_scene: String = ""

	if not scene_path.is_empty():
		if not FileAccess.file_exists(scene_path):
			return {"error": "Scene file not found: " + scene_path}
		played_scene = scene_path
		editor_interface.play_custom_scene(scene_path)
	else:
		var scene_root: Node = _get_user_scene_root()
		if scene_root:
			played_scene = scene_root.scene_file_path
			editor_interface.play_current_scene()
		else:
			played_scene = String(ProjectSettings.get_setting("application/run/main_scene", ""))
			editor_interface.play_main_scene()

	# Verify the play actually launched a debuggable child. Without this guard a
	# failed play (e.g. application/run/main_scene pointing at a missing file)
	# reports a fake success and leaves callers stuck retrying runtime tools (#172).
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var connected: bool = false
	var connect_deadline: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < connect_deadline:
		if _has_active_debugger_session():
			connected = true
			break
		if tree:
			await tree.process_frame
		else:
			break
	if not connected:
		return {
			"status": "error",
			"error": "Play was requested but no debugger session became active within the timeout. The scene likely failed to load — check ProjectSettings application/run/main_scene.",
			"scene": played_scene
		}

	# Give the runtime probe a brief window to signal ready so callers can use
	# runtime tools (scene tree, screenshot, expression eval) right away.
	var bridge: RefCounted = _get_debugger_bridge()
	var probe_ready: bool = bridge.is_probe_ready() if bridge else false
	var probe_deadline: int = Time.get_ticks_msec() + 2000
	while not probe_ready and tree and Time.get_ticks_msec() < probe_deadline:
		await tree.process_frame
		probe_ready = bridge.is_probe_ready() if bridge else false

	return {
		"status": "success",
		"mode": "playing",
		"scene": played_scene,
		"session_active": true,
		"probe_ready": probe_ready
	}

# ============================================================================
# stop_project - 停止运行
# ============================================================================

func _register_stop_project(server_core: RefCounted) -> void:
	var tool_name: String = "stop_project"
	var description: String = "Stop the currently running project and return to editor mode."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"allow_window": {
				"type": "boolean",
				"description": "Allow this call to control the runtime window when Vibe Coding mode is enabled.",
				"default": false
			}
		}
	}
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"mode": {"type": "string"},
			"stopped_after_ms": {"type": "integer"}
		}
	}
	
	# annotations
	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	# register tool
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_stop_project"),
						  output_schema, annotations,
						  "core", "Editor")

func _tool_stop_project(params: Dictionary) -> Dictionary:
	var policy_result: Dictionary = VIBE_CODING_POLICY.evaluate_runtime_window(_is_vibe_coding_mode(), params)
	if policy_result.get("blocked", false):
		return policy_result

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	if not editor_interface.is_playing_scene():
		return {"error": "Project is not currently running."}

	editor_interface.stop_playing_scene()

	# Wait for the process to fully exit (up to 5s)
	var max_wait_ms: int = 5000
	var wait_interval_ms: int = 200
	var waited_ms: int = 0
	while editor_interface.is_playing_scene() and waited_ms < max_wait_ms:
		OS.delay_msec(wait_interval_ms)
		waited_ms += wait_interval_ms

	return {
		"status": "success",
		"mode": "editor",
		"stopped_after_ms": waited_ms
	}

# ============================================================================
# get_selected_nodes - 获取选中的节点
# ============================================================================

func _register_get_selected_nodes(server_core: RefCounted) -> void:
	var tool_name: String = "get_selected_nodes"
	var description: String = "Get the list of currently selected nodes in the editor."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"selected_nodes": {
				"type": "array",
				"items": {"type": "object"}
			},
			"count": {"type": "integer"}
		}
	}
	
	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_selected_nodes"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_get_selected_nodes(params: Dictionary) -> Dictionary:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var selected_nodes: Array = []
	var selection: EditorSelection = editor_interface.get_selection()
	var scene_root: Node = _get_user_scene_root()
	
	if selection:
		var selected: Array[Node] = selection.get_selected_nodes()
		for node in selected:
			var node_info: Dictionary = {
				"path": _make_friendly_path(node, scene_root),
				"type": node.get_class()
			}
			var node_script: Variant = node.get_script()
			if node_script and node_script is Script:
				node_info["script_path"] = node_script.resource_path
			selected_nodes.append(node_info)
	
	if selected_nodes.is_empty():
		var edited_scene: Node = editor_interface.get_edited_scene_root()
		if edited_scene:
			selected_nodes.append({
				"path": _make_friendly_path(edited_scene, scene_root),
				"type": edited_scene.get_class()
			})
	
	return {
		"selected_nodes": selected_nodes,
		"count": selected_nodes.size()
	}

# ============================================================================
# select_node - 选择并在 Inspector 中编辑节点
# ============================================================================

func _register_select_node(server_core: RefCounted) -> void:
	var tool_name: String = "select_node"
	var description: String = "Select a node in the current edited scene and focus it in the Inspector."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"node_path": {
				"type": "string",
				"description": "Node path such as '/root/MainScene/Player'."
			},
			"clear_existing": {
				"type": "boolean",
				"description": "Whether to clear the existing editor selection before selecting the node. Default is true.",
				"default": true
			},
			"allow_ui_focus": {
				"type": "boolean",
				"description": "Allow this call to change editor selection/focus when Vibe Coding mode is enabled.",
				"default": false
			}
		},
		"required": ["node_path"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"node_path": {"type": "string"},
			"node_type": {"type": "string"},
			"selected_count": {"type": "integer"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_select_node"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_select_node(params: Dictionary) -> Dictionary:
	var policy_result: Dictionary = VIBE_CODING_POLICY.evaluate_editor_focus(_is_vibe_coding_mode(), params)
	if policy_result.get("blocked", false):
		return policy_result

	var node_path: String = str(params.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}

	var clear_existing: bool = params.get("clear_existing", true)
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(editor_interface, node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	var selection: EditorSelection = editor_interface.get_selection()
	if selection:
		if clear_existing:
			selection.clear()
		selection.add_node(target_node)

	editor_interface.edit_node(target_node)

	var selected_count: int = 1
	if selection:
		selected_count = selection.get_selected_nodes().size()

	return {
		"status": "success",
		"node_path": _make_friendly_path(target_node, _get_user_scene_root()),
		"node_type": target_node.get_class(),
		"selected_count": selected_count
	}

# ============================================================================
# select_file - 在 FileSystem dock 中选择文件
# ============================================================================

func _register_select_file(server_core: RefCounted) -> void:
	var tool_name: String = "select_file"
	var description: String = "Select a project file in the Godot FileSystem dock."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"file_path": {
				"type": "string",
				"description": "Project file path such as 'res://scenes/Main.tscn'."
			},
			"allow_ui_focus": {
				"type": "boolean",
				"description": "Allow this call to change the editor FileSystem selection when Vibe Coding mode is enabled.",
				"default": false
			}
		},
		"required": ["file_path"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"file_path": {"type": "string"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_select_file"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_select_file(params: Dictionary) -> Dictionary:
	var policy_result: Dictionary = VIBE_CODING_POLICY.evaluate_editor_focus(_is_vibe_coding_mode(), params)
	if policy_result.get("blocked", false):
		return policy_result

	var file_path: String = str(params.get("file_path", "")).strip_edges()
	if file_path.is_empty():
		return {"error": "Missing required parameter: file_path"}

	var validation: Dictionary = PathValidator.validate_path(file_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	file_path = validation["sanitized"]

	if not FileAccess.file_exists(file_path):
		return {"error": "File not found: " + file_path}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	editor_interface.select_file(file_path)
	return {
		"status": "success",
		"file_path": file_path
	}

# ============================================================================
# get_inspector_properties - 获取 Inspector 风格的属性元数据
# ============================================================================

func _register_get_inspector_properties(server_core: RefCounted) -> void:
	var tool_name: String = "get_inspector_properties"
	var description: String = "Inspect a node or resource and return property metadata and serialized values similar to the Inspector."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"node_path": {
				"type": "string",
				"description": "Optional node path to inspect."
			},
			"resource_path": {
				"type": "string",
				"description": "Optional resource path to inspect."
			},
			"property_filter": {
				"type": "string",
				"description": "Optional substring filter for property names."
			},
			"include_values": {
				"type": "boolean",
				"description": "Whether to include current property values. Default is true.",
				"default": true
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"target_kind": {"type": "string"},
			"target_path": {"type": "string"},
			"class_name": {"type": "string"},
			"property_count": {"type": "integer"},
			"properties": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_inspector_properties"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_get_inspector_properties(params: Dictionary) -> Dictionary:
	var node_path: String = str(params.get("node_path", "")).strip_edges()
	var resource_path: String = str(params.get("resource_path", "")).strip_edges()
	var property_filter: String = str(params.get("property_filter", "")).strip_edges().to_lower()
	var include_values: bool = params.get("include_values", true)

	if node_path.is_empty() and resource_path.is_empty():
		return {"error": "Provide node_path or resource_path"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_object: Object = null
	var target_kind: String = ""
	var target_path: String = ""

	if not node_path.is_empty():
		var target_node: Node = _resolve_node_path(editor_interface, node_path)
		if not target_node:
			return {"error": "Node not found: " + node_path}
		editor_interface.edit_node(target_node)
		editor_interface.inspect_object(target_node)
		target_object = target_node
		target_kind = "node"
		target_path = _make_friendly_path(target_node, _get_user_scene_root())
	else:
		var validation: Dictionary = PathValidator.validate_path(resource_path)
		if not validation["valid"]:
			return {"error": "Invalid path: " + validation["error"]}
		resource_path = validation["sanitized"]
		if not FileAccess.file_exists(resource_path):
			return {"error": "File not found: " + resource_path}
		var resource: Resource = load(resource_path)
		if not resource:
			return {"error": "Failed to load resource: " + resource_path}
		editor_interface.inspect_object(resource)
		target_object = resource
		target_kind = "resource"
		target_path = resource_path

	var properties: Array = []
	for property_info_variant in target_object.get_property_list():
		var property_info: Dictionary = property_info_variant
		var property_name: String = str(property_info.get("name", ""))
		if property_name.is_empty():
			continue
		if not property_filter.is_empty() and not property_name.to_lower().contains(property_filter):
			continue

		var serialized: Dictionary = {
			"name": property_name,
			"type": int(property_info.get("type", TYPE_NIL)),
			"usage": int(property_info.get("usage", 0)),
			"hint": int(property_info.get("hint", PROPERTY_HINT_NONE)),
			"hint_string": str(property_info.get("hint_string", "")),
			"class_name": str(property_info.get("class_name", ""))
		}
		if include_values:
			serialized["value"] = _serialize_editor_value(target_object.get(property_name))
		properties.append(serialized)

	return {
		"target_kind": target_kind,
		"target_path": target_path,
		"class_name": target_object.get_class(),
		"property_count": properties.size(),
		"properties": properties
	}

# ============================================================================
# list_export_presets - 列出导出预设
# ============================================================================

func _register_list_export_presets(server_core: RefCounted) -> void:
	var tool_name: String = "list_export_presets"
	var description: String = "List export presets from export_presets.cfg."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"config_path": {"type": "string"},
			"count": {"type": "integer"},
			"presets": {
				"type": "array",
				"items": {"type": "object"}
			}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_list_export_presets"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_list_export_presets(params: Dictionary) -> Dictionary:
	var preset_data: Dictionary = _load_export_presets()
	if preset_data.has("error"):
		return preset_data
	return {
		"config_path": preset_data["config_path"],
		"count": preset_data["presets"].size(),
		"presets": preset_data["presets"]
	}

# ============================================================================
# inspect_export_templates - 检查本机导出模板
# ============================================================================

func _register_inspect_export_templates(server_core: RefCounted) -> void:
	var tool_name: String = "inspect_export_templates"
	var description: String = "Inspect locally installed Godot export templates for the current editor version."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"templates_root": {"type": "string"},
			"current_version": {"type": "string"},
			"matching_version_installed": {"type": "boolean"},
			"installed_versions": {"type": "array"},
			"detected_files": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_inspect_export_templates"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_inspect_export_templates(params: Dictionary) -> Dictionary:
	return _inspect_export_templates()

# ============================================================================
# validate_export_preset - 校验导出预设
# ============================================================================

func _register_validate_export_preset(server_core: RefCounted) -> void:
	var tool_name: String = "validate_export_preset"
	var description: String = "Validate an export preset against export_presets.cfg and local template availability."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"preset": {
				"type": "string",
				"description": "Preset name or section, e.g. 'Windows Desktop' or 'preset.0'."
			}
		},
		"required": ["preset"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"valid": {"type": "boolean"},
			"preset": {"type": "object"},
			"errors": {"type": "array"},
			"warnings": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_validate_export_preset"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_validate_export_preset(params: Dictionary) -> Dictionary:
	var preset_name: String = str(params.get("preset", "")).strip_edges()
	if preset_name.is_empty():
		return {"error": "Missing required parameter: preset"}

	var preset_data: Dictionary = _load_export_presets()
	if preset_data.has("error"):
		return preset_data

	var preset: Dictionary = _find_export_preset(preset_data["presets"], preset_name)
	if preset.is_empty():
		return {
			"valid": false,
			"errors": ["Export preset not found: " + preset_name],
			"warnings": [],
			"preset": {}
		}

	var errors: Array[String] = []
	var warnings: Array[String] = []
	if str(preset.get("platform", "")).is_empty():
		errors.append("Preset is missing platform")
	if str(preset.get("name", "")).is_empty():
		errors.append("Preset is missing name")
	if str(preset.get("export_path", "")).is_empty():
		warnings.append("Preset does not define export_path; run_export must receive output_path")

	var template_info: Dictionary = _inspect_export_templates()
	if not bool(template_info.get("matching_version_installed", false)):
		warnings.append("Matching export templates are not installed for current Godot version")

	return {
		"valid": errors.is_empty(),
		"preset": preset,
		"errors": errors,
		"warnings": warnings,
		"template_info": template_info
	}

# ============================================================================
# run_export - 执行导出
# ============================================================================

func _register_run_export(server_core: RefCounted) -> void:
	var tool_name: String = "run_export"
	var description: String = "Run a Godot CLI export for a configured preset."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"preset": {
				"type": "string",
				"description": "Preset name or section."
			},
			"output_path": {
				"type": "string",
				"description": "Optional absolute or res:// output path override."
			},
			"mode": {
				"type": "string",
				"enum": ["release", "debug", "pack", "patch"],
				"default": "release"
			}
		},
		"required": ["preset"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"success": {"type": "boolean"},
			"exit_code": {"type": "integer"},
			"command": {"type": "array"},
			"output_path": {"type": "string"},
			"logs": {"type": "array"},
			"errors": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": false,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_run_export"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_run_export(params: Dictionary) -> Dictionary:
	var preset_name: String = str(params.get("preset", "")).strip_edges()
	if preset_name.is_empty():
		return {"error": "Missing required parameter: preset"}

	var mode: String = str(params.get("mode", "release")).strip_edges().to_lower()
	var mode_to_flag: Dictionary = {
		"release": "--export-release",
		"debug": "--export-debug",
		"pack": "--export-pack",
		"patch": "--export-patch"
	}
	if not mode_to_flag.has(mode):
		return {"error": "Invalid mode: " + mode}

	var preset_data: Dictionary = _load_export_presets()
	if preset_data.has("error"):
		return preset_data

	var preset: Dictionary = _find_export_preset(preset_data["presets"], preset_name)
	if preset.is_empty():
		return {"error": "Export preset not found: " + preset_name}

	var output_path: String = str(params.get("output_path", "")).strip_edges()
	if output_path.is_empty():
		output_path = str(preset.get("export_path", "")).strip_edges()
	if output_path.is_empty():
		return {"error": "Export preset has no export_path and output_path was not provided"}

	if output_path.begins_with("res://"):
		output_path = ProjectSettings.globalize_path(output_path)

	var output_dir: String = output_path.get_base_dir()
	if not output_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(output_dir)

	var executable_path: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	var args: Array[String] = [
		"--headless",
		"--path", project_path,
		str(mode_to_flag[mode]),
		str(preset.get("name", "")),
		output_path
	]

	var logs: Array = []
	var exit_code: int = OS.execute(executable_path, args, logs, true)
	var sanitized_logs: Array[String] = []
	for line in logs:
		sanitized_logs.append(_sanitize_cli_output(str(line)))
	var error_lines: Array[String] = []
	for text_line in sanitized_logs:
		if text_line.contains("ERROR:") or text_line.contains("Export failed") or text_line.contains("No export template"):
			error_lines.append(text_line)

	return {
		"success": exit_code == OK,
		"exit_code": exit_code,
		"command": [executable_path] + args,
		"output_path": output_path,
		"preset": preset,
		"logs": sanitized_logs,
		"errors": error_lines
	}

func _load_export_presets() -> Dictionary:
	var config_path: String = "res://export_presets.cfg"
	if not FileAccess.file_exists(config_path):
		return {
			"config_path": config_path,
			"presets": []
		}

	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(config_path)
	if load_error != OK:
		return {"error": "Failed to load export_presets.cfg: " + error_string(load_error)}

	var presets: Array = []
	for raw_section in config.get_sections():
		var section_name: String = str(raw_section)
		if not section_name.begins_with("preset.") or section_name.ends_with(".options"):
			continue

		var preset: Dictionary = {
			"section": section_name,
			"name": str(config.get_value(section_name, "name", "")),
			"platform": str(config.get_value(section_name, "platform", "")),
			"export_path": str(config.get_value(section_name, "export_path", "")),
			"runnable": bool(config.get_value(section_name, "runnable", false))
		}
		presets.append(preset)

	return {
		"config_path": config_path,
		"presets": presets
	}

func _inspect_export_templates() -> Dictionary:
	var version_info: Dictionary = Engine.get_version_info()
	var version_variants: Array[String] = []
	var base_version: String = "%d.%d.%d.%s" % [
		int(version_info.get("major", 0)),
		int(version_info.get("minor", 0)),
		int(version_info.get("patch", 0)),
		str(version_info.get("status", "stable"))
	]
	version_variants.append(base_version)
	version_variants.append(base_version + ".mono")

	var templates_root: String = _get_export_templates_root()
	var installed_versions: Array[String] = []
	var detected_files: Array[String] = []
	var matching_version_installed: bool = false

	var root_dir: DirAccess = DirAccess.open(templates_root)
	if root_dir:
		root_dir.list_dir_begin()
		var entry: String = root_dir.get_next()
		while entry != "":
			if root_dir.current_is_dir() and not entry.begins_with("."):
				installed_versions.append(entry)
				if version_variants.has(entry):
					matching_version_installed = true
					var version_dir_path: String = templates_root.path_join(entry)
					var version_dir: DirAccess = DirAccess.open(version_dir_path)
					if version_dir:
						version_dir.list_dir_begin()
						var file_name: String = version_dir.get_next()
						while file_name != "":
							if not version_dir.current_is_dir():
								detected_files.append(version_dir_path.path_join(file_name))
							file_name = version_dir.get_next()
						version_dir.list_dir_end()
			entry = root_dir.get_next()
		root_dir.list_dir_end()

	installed_versions.sort()
	detected_files.sort()

	return {
		"templates_root": templates_root,
		"current_version": base_version,
		"matching_version_installed": matching_version_installed,
		"expected_versions": version_variants,
		"installed_versions": installed_versions,
		"detected_files": detected_files
	}

func _find_export_preset(presets: Array, preset_name: String) -> Dictionary:
	for preset_value in presets:
		var preset: Dictionary = preset_value
		if str(preset.get("section", "")) == preset_name:
			return preset
		if str(preset.get("name", "")) == preset_name:
			return preset
	return {}

func _sanitize_cli_output(text: String) -> String:
	var sanitized: String = ""
	for i in range(text.length()):
		var codepoint: int = text.unicode_at(i)
		var keep_char: bool = codepoint >= 32 and codepoint != 127
		if codepoint == 9 or codepoint == 10 or codepoint == 13:
			keep_char = true
		if codepoint >= 0xE000 and codepoint <= 0xF8FF:
			keep_char = false
		if keep_char:
			sanitized += String.chr(codepoint)
	return sanitized

# ============================================================================
# set_editor_setting - 设置编辑器属性
# ============================================================================

func _register_set_editor_setting(server_core: RefCounted) -> void:
	var tool_name: String = "set_editor_setting"
	var description: String = "Set an editor setting value. Requires editor restart for some settings to take effect."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"setting_name": {
				"type": "string",
				"description": "Name of the setting (e.g. 'interface/theme/accent_color')"
			},
			"setting_value": {
				"description": "New value for the setting"
			}
		},
		"required": ["setting_name", "setting_value"]
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"setting_name": {"type": "string"},
			"old_value": {"type": "string"},
			"new_value": {"type": "string"}
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
						  Callable(self, "_tool_set_editor_setting"),
						  output_schema, annotations,
						  "supplementary", "Editor-Advanced")

func _tool_set_editor_setting(params: Dictionary) -> Dictionary:
	var setting_name: String = params.get("setting_name", "")
	var setting_value: Variant = params.get("setting_value", null)
	
	if setting_name.is_empty():
		return {"error": "Missing required parameter: setting_name"}
	if setting_value == null:
		return {"error": "Missing required parameter: setting_value"}
	
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var editor_settings: EditorSettings = editor_interface.get_editor_settings()
	if not editor_settings:
		return {"error": "Failed to get EditorSettings"}
	
	var old_value: Variant = null
	if editor_settings.has_setting(setting_name):
		old_value = editor_settings.get_setting(setting_name)
	editor_settings.set_setting(setting_name, setting_value)
	if editor_settings.has_method("save"):
		editor_settings.save()
	
	return {
		"status": "success",
		"setting_name": setting_name,
		"old_value": str(old_value) if old_value != null else "null",
		"new_value": str(setting_value)
	}

# ============================================================================
# get_editor_screenshot - 截取编辑器视口
# ============================================================================

func _register_get_editor_screenshot(server_core: RefCounted) -> void:
	var tool_name: String = "get_editor_screenshot"
	var description: String = "Capture a screenshot of the editor viewport and save it to a file."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"viewport_type": {
				"type": "string",
				"description": "Viewport type: '3d' or '2d'. Default is '3d'.",
				"enum": ["3d", "2d"]
			},
			"viewport_index": {
				"type": "integer",
				"description": "3D viewport index (0-3). Default is 0."
			},
			"save_path": {
				"type": "string",
				"description": "Path to save the screenshot (e.g. 'res://screenshots/editor.png')."
			},
			"format": {
				"type": "string",
				"description": "Image format: 'png' or 'jpg'. Default is 'jpg'.",
				"enum": ["png", "jpg"]
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"save_path": {"type": "string"},
			"size": {"type": "string"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": false,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
		Callable(self, "_tool_get_editor_screenshot"),
		output_schema, annotations,
		"supplementary", "Editor-Advanced")

func _tool_get_editor_screenshot(params: Dictionary) -> Dictionary:
	var viewport_type: String = params.get("viewport_type", "3d")
	var viewport_index: int = params.get("viewport_index", 0)
	var save_path: String = params.get("save_path", "res://screenshot_editor.png")
	var format: String = params.get("format", "jpg")

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var path_validation: Dictionary = PathValidator.validate_path(save_path)
	if not path_validation["valid"]:
		return {"error": "Invalid save path: " + path_validation["error"]}
	save_path = path_validation["sanitized"]

	# Switch the main screen editor to the target viewport type so the
	# SubViewport is visible and actively rendering. Without this, the
	# viewport may show stale content when the editor is in the background.
	editor_interface.set_main_screen_editor(viewport_type.to_upper())

	var viewport: SubViewport = null
	if viewport_type == "3d":
		viewport = editor_interface.get_editor_viewport_3d(viewport_index)
	else:
		viewport = editor_interface.get_editor_viewport_2d()

	if not viewport:
		return {"error": "Failed to get editor viewport"}

	# Temporarily force the viewport to always update so it renders even
	# when the editor window is in the background or minimized.
	var original_update_mode: int = viewport.render_target_update_mode
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Wait one frame for the SubViewport to render, then force a flush.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.process_frame
	RenderingServer.force_draw()

	var texture: ViewportTexture = viewport.get_texture()
	# Restore the original update mode after capturing.
	viewport.render_target_update_mode = original_update_mode
	if not texture:
		return {"error": "Failed to get viewport texture"}

	var image: Image = texture.get_image()
	if not image:
		return {"error": "Failed to capture viewport image"}

	var save_dir: String = save_path.get_base_dir()
	if not save_dir.is_empty() and not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var err: Error = OK
	if format == "jpg":
		err = image.save_jpg(save_path, 0.9)
	else:
		err = image.save_png(save_path)

	if err != OK:
		return {"error": "Failed to save screenshot: error " + str(err)}

	return {
		"status": "success",
		"save_path": save_path,
		"size": str(image.get_width()) + "x" + str(image.get_height())
	}

# ============================================================================
# get_signals - 获取节点的所有信号及连接
# ============================================================================

func _register_get_signals(server_core: RefCounted) -> void:
	var tool_name: String = "get_signals"
	var description: String = "Get all signals and their connections for a node."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"node_path": {
				"type": "string",
				"description": "Path to the node (e.g. '/root/MainScene/Player')"
			},
			"include_connections": {
				"type": "boolean",
				"description": "Whether to include connection details. Default is true."
			}
		},
		"required": ["node_path"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"node_path": {"type": "string"},
			"signals": {"type": "array"},
			"signal_count": {"type": "integer"},
			"connection_count": {"type": "integer"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
		Callable(self, "_tool_get_signals"),
		output_schema, annotations,
		"supplementary", "Editor-Advanced")

func _tool_get_signals(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var include_connections: bool = params.get("include_connections", true)

	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var target_node: Node = _resolve_node_path(editor_interface, node_path)
	if not target_node:
		return {"error": "Node not found: " + node_path}

	var signal_list: Array = target_node.get_signal_list()
	var signals: Array = []
	var total_connections: int = 0

	for sig in signal_list:
		var signal_info: Dictionary = {
			"name": sig.get("name", ""),
			"arguments": sig.get("args", []).size()
		}

		if include_connections:
			var connections: Array = target_node.get_signal_connection_list(sig.get("name", ""))
			var connection_list: Array = []
			for conn in connections:
				connection_list.append({
					"callable": str(conn.get("callable", "")),
					"flags": conn.get("flags", 0)
				})
				total_connections += 1
			signal_info["connections"] = connection_list
			signal_info["connection_count"] = connection_list.size()

		signals.append(signal_info)

	return {
		"node_path": node_path,
		"signals": signals,
		"signal_count": signals.size(),
		"connection_count": total_connections
	}

func _resolve_node_path(editor_interface: EditorInterface, path: String) -> Node:
	var edited_scene: Node = editor_interface.get_edited_scene_root()
	if not edited_scene:
		return null
	if path == str(edited_scene.get_path()) or path == "/root/" + edited_scene.name:
		return edited_scene
	if path.begins_with("/root/" + edited_scene.name + "/"):
		var relative: String = path.substr(("/root/" + edited_scene.name + "/").length())
		return edited_scene.get_node_or_null(relative)
	return edited_scene.get_node_or_null(path)

func _serialize_editor_value(value: Variant) -> Variant:
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
			var array_result: Array = []
			for item in value:
				array_result.append(_serialize_editor_value(item))
			return array_result
		TYPE_DICTIONARY:
			var dict_result: Dictionary = {}
			for key in value:
				dict_result[str(key)] = _serialize_editor_value(value[key])
			return dict_result
		_:
			return str(value)

# ============================================================================
# reload_project - 重新扫描文件系统并重新加载脚本
# ============================================================================

func _register_reload_project(server_core: RefCounted) -> void:
	var tool_name: String = "reload_project"
	var description: String = "Rescan the project filesystem and reload scripts. Useful after external file changes."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"full_scan": {
				"type": "boolean",
				"description": "Whether to perform a full scan (true) or source-only scan (false). Default is false."
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"scan_type": {"type": "string"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": false,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
		Callable(self, "_tool_reload_project"),
		output_schema, annotations,
		"supplementary", "Editor-Advanced")

func _tool_reload_project(params: Dictionary) -> Dictionary:
	var full_scan: bool = params.get("full_scan", false)

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var fs: EditorFileSystem = editor_interface.get_resource_filesystem()
	if not fs:
		return {"error": "Failed to get EditorFileSystem"}

	if fs.is_scanning():
		return {
			"status": "already_scanning",
			"progress": fs.get_scanning_progress(),
			"message": "Filesystem scan is already in progress"
		}

	if full_scan:
		fs.scan()
		return {"status": "success", "scan_type": "full"}
	else:
		fs.scan_sources()
		return {"status": "success", "scan_type": "sources_only"}
