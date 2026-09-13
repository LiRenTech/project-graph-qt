# debug_tools_native.gd - Debug Tools原生实现

@tool
class_name DebugToolsNative
extends RefCounted

var _editor_interface: EditorInterface = null
var _log_buffer: Array[String] = []
var _max_log_lines: int = 1000
var _server_core: RefCounted = null
var _log_mutex: Mutex = Mutex.new()
var _execution_mutex: Mutex = Mutex.new()
var _pending_runtime_probe_requests: Dictionary = {}

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

func _get_user_scene_root() -> Node:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return null
	var scene_root: Node = editor_interface.get_edited_scene_root()
	if _is_user_scene_root(scene_root):
		return scene_root
	var open_scene_roots: Array = editor_interface.get_open_scene_roots()
	for root in open_scene_roots:
		var node_root: Node = root
		if _is_user_scene_root(node_root):
			return node_root
	return null

func _is_user_scene_root(node: Node) -> bool:
	if not node:
		return false
	if node.name.begins_with("@") or node.get_class() == "PanelContainer":
		return false
	return not String(node.scene_file_path).is_empty()

func _to_runtime_friendly_path(node: Node, scene_root: Node = null) -> String:
	if not node:
		return ""
	var resolved_scene_root: Node = scene_root
	if not resolved_scene_root:
		resolved_scene_root = _get_user_scene_root()
	if not resolved_scene_root:
		return str(node.get_path())
	var root_name: String = String(resolved_scene_root.name)
	if root_name.is_empty():
		return str(node.get_path())
	if node == resolved_scene_root:
		return "/root/" + root_name
	var node_path: String = str(node.get_path())
	var scene_root_path: String = str(resolved_scene_root.get_path())
	if node_path.begins_with(scene_root_path + "/"):
		return "/root/" + root_name + node_path.substr(scene_root_path.length())
	return node_path

# ============================================================================
# 工具注册
# ============================================================================

func register_tools(server_core: RefCounted) -> void:
	_server_core = server_core
	if server_core.has_signal("log_message"):
		server_core.log_message.connect(_on_log_message)
	
	_register_get_editor_logs(server_core)
	_register_execute_script(server_core)
	_register_get_performance_metrics(server_core)
	_register_debug_print(server_core)
	_register_execute_editor_script(server_core)
	_register_clear_output(server_core)
	_register_get_debugger_sessions(server_core)
	_register_get_debug_threads(server_core)
	_register_set_debugger_breakpoint(server_core)
	_register_send_debugger_message(server_core)
	_register_toggle_debugger_profiler(server_core)
	_register_get_debugger_messages(server_core)
	_register_get_debug_state_events(server_core)
	_register_get_debug_output(server_core)
	_register_add_debugger_capture_prefix(server_core)
	_register_get_debug_stack_frames(server_core)
	_register_get_debug_stack_variables(server_core)
	_register_get_debug_scopes(server_core)
	_register_get_debug_variables(server_core)
	_register_expand_debug_variable(server_core)
	_register_evaluate_debug_expression(server_core)
	_register_install_runtime_probe(server_core)
	_register_remove_runtime_probe(server_core)
	_register_request_debug_break(server_core)
	_register_send_debug_command(server_core)
	_register_debug_step_into(server_core)
	_register_debug_step_over(server_core)
	_register_debug_step_out(server_core)
	_register_debug_continue(server_core)
	_register_debug_step_into_and_wait(server_core)
	_register_debug_step_over_and_wait(server_core)
	_register_debug_step_out_and_wait(server_core)
	_register_debug_continue_and_wait(server_core)
	_register_await_debugger_state(server_core)
	_register_get_runtime_info(server_core)
	_register_await_scene_ready(server_core)
	_register_get_runtime_performance_snapshot(server_core)
	_register_get_runtime_memory_trend(server_core)
	_register_get_runtime_scene_tree(server_core)
	_register_inspect_runtime_node(server_core)
	_register_create_runtime_node(server_core)
	_register_delete_runtime_node(server_core)
	_register_update_runtime_node_property(server_core)
	_register_call_runtime_node_method(server_core)
	_register_evaluate_runtime_expression(server_core)
	_register_simulate_runtime_input_event(server_core)
	_register_simulate_runtime_input_action(server_core)
	_register_list_runtime_input_actions(server_core)
	_register_upsert_runtime_input_action(server_core)
	_register_remove_runtime_input_action(server_core)
	_register_list_runtime_animations(server_core)
	_register_play_runtime_animation(server_core)
	_register_stop_runtime_animation(server_core)
	_register_get_runtime_animation_state(server_core)
	_register_get_runtime_animation_tree_state(server_core)
	_register_set_runtime_animation_tree_active(server_core)
	_register_travel_runtime_animation_tree(server_core)
	_register_get_runtime_material_state(server_core)
	_register_get_runtime_theme_item(server_core)
	_register_set_runtime_theme_override(server_core)
	_register_clear_runtime_theme_override(server_core)
	_register_get_runtime_shader_parameters(server_core)
	_register_set_runtime_shader_parameter(server_core)
	_register_list_runtime_tilemap_layers(server_core)
	_register_get_runtime_tilemap_cell(server_core)
	_register_set_runtime_tilemap_cell(server_core)
	_register_list_runtime_audio_buses(server_core)
	_register_get_runtime_audio_bus(server_core)
	_register_update_runtime_audio_bus(server_core)
	_register_get_runtime_screenshot(server_core)
	_register_await_runtime_condition(server_core)
	_register_assert_runtime_condition(server_core)

func _on_log_message(level: String, message: String) -> void:
	var log_entry: String = "[%s] %s" % [level, message]
	_log_mutex.lock()
	_log_buffer.append(log_entry)
	if _log_buffer.size() > _max_log_lines:
		_log_buffer = _log_buffer.slice(_log_buffer.size() - _max_log_lines)
	_log_mutex.unlock()

# ============================================================================
# get_editor_logs - 获取编辑器日志
# ============================================================================

func _register_get_editor_logs(server_core: RefCounted) -> void:
	var tool_name: String = "get_editor_logs"
	var description: String = "Get recent log messages from the editor or runtime. Supports filtering by source, type, and pagination."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"source": {
				"type": "string",
				"description": "Log source: 'mcp' (MCP server logs, default), 'runtime' (user://logs/godot.log), 'editor_panel' (Godot editor output panel including print/errors/warnings).",
				"default": "mcp",
				"enum": ["mcp", "runtime", "editor_panel"]
			},
			"type": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Filter by log types (e.g. ['Error', 'Warning', 'Info']). Only applies to MCP source. Empty array returns all."
			},
			"count": {
				"type": "integer",
				"description": "Maximum number of log lines to return. Default is 100.",
				"default": 100
			},
			"offset": {
				"type": "integer",
				"description": "Number of log entries to skip. Default is 0.",
				"default": 0
			},
			"order": {
				"type": "string",
				"description": "Sort order: 'desc' (newest first, default) or 'asc' (oldest first).",
				"default": "desc",
				"enum": ["desc", "asc"]
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"logs": {
				"type": "array",
				"items": {"type": "object"}
			},
			"count": {"type": "integer"},
			"total_available": {"type": "integer"},
			"source": {"type": "string"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_editor_logs"),
						  output_schema, annotations, "core", "Debug")

func _tool_get_editor_logs(params: Dictionary) -> Dictionary:
	var source: String = params.get("source", "mcp")
	var types: Array = params.get("type", [])
	var count: int = params.get("count", 100)
	var offset: int = params.get("offset", 0)
	var order: String = params.get("order", "desc")

	if source == "runtime":
		return _get_runtime_logs(types, count, offset, order)
	elif source == "editor_panel":
		return _get_editor_panel_logs(types, count, offset, order)

	return _get_mcp_logs(types, count, offset, order)

func _get_debugger_bridge() -> RefCounted:
	if Engine.has_meta("GodotMCPPlugin"):
		var plugin = Engine.get_meta("GodotMCPPlugin")
		if plugin and plugin.has_method("get_debugger_bridge"):
			return plugin.get_debugger_bridge()
	return null

func _register_get_debugger_sessions(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debugger_sessions",
		"List Godot editor debugger sessions and their active/break state.",
		{"type": "object", "properties": {}},
		Callable(self, "_tool_get_debugger_sessions"),
		{"type": "object", "properties": {"sessions": {"type": "array"}, "count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debugger_sessions(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var sessions: Array = bridge.get_sessions_info()
	return {"sessions": sessions, "count": sessions.size()}

func _register_set_debugger_breakpoint(server_core: RefCounted) -> void:
	server_core.register_tool(
		"set_debugger_breakpoint",
		"Enable or disable a breakpoint in active Godot debugger sessions.",
		{
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "Script path, e.g. res://player.gd"},
				"line": {"type": "integer", "description": "1-based line number"},
				"enabled": {"type": "boolean", "description": "Whether the breakpoint is enabled"},
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all sessions."}
			},
			"required": ["path", "line", "enabled"]
		},
		Callable(self, "_tool_set_debugger_breakpoint"),
		{"type": "object", "properties": {"status": {"type": "string"}, "sessions_updated": {"type": "integer"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_set_debugger_breakpoint(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var line: int = params.get("line", 0)
	var enabled: bool = params.get("enabled", true)
	var session_id: int = params.get("session_id", -1)
	if path.is_empty():
		return {"error": "Missing required parameter: path"}
	if line < 1:
		return {"error": "line must be >= 1"}
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	return bridge.set_breakpoint(path, line, enabled, session_id)

func _register_get_debug_threads(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debug_threads",
		"Return DAP-style debugger threads visible from the active Godot debug session.",
		{"type": "object", "properties": {}},
		Callable(self, "_tool_get_debug_threads"),
		{"type": "object", "properties": {"threads": {"type": "array"}, "count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debug_threads(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var threads: Array = bridge.get_threads()
	return {"threads": threads, "count": threads.size()}

func _register_send_debugger_message(server_core: RefCounted) -> void:
	server_core.register_tool(
		"send_debugger_message",
		"Send a custom debugger message to active Godot debugger sessions.",
		{
			"type": "object",
			"properties": {
				"message": {"type": "string"},
				"data": {"type": "array", "items": {"type": "object"}},
				"session_id": {"type": "integer"}
			},
			"required": ["message"]
		},
		Callable(self, "_tool_send_debugger_message"),
		{"type": "object", "properties": {"status": {"type": "string"}, "sessions_updated": {"type": "integer"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_send_debugger_message(params: Dictionary) -> Dictionary:
	var message: String = params.get("message", "")
	var data: Array = params.get("data", [])
	var session_id: int = params.get("session_id", -1)
	if message.is_empty():
		return {"error": "Missing required parameter: message"}
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	return bridge.send_debugger_message(message, data, session_id)

func _register_toggle_debugger_profiler(server_core: RefCounted) -> void:
	server_core.register_tool(
		"toggle_debugger_profiler",
		"Toggle an EngineProfiler in active Godot debugger sessions.",
		{
			"type": "object",
			"properties": {
				"profiler": {"type": "string", "description": "Profiler name"},
				"enabled": {"type": "boolean"},
				"data": {"type": "array", "items": {"type": "object"}},
				"session_id": {"type": "integer"}
			},
			"required": ["profiler", "enabled"]
		},
		Callable(self, "_tool_toggle_debugger_profiler"),
		{"type": "object", "properties": {"status": {"type": "string"}, "sessions_updated": {"type": "integer"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_toggle_debugger_profiler(params: Dictionary) -> Dictionary:
	var profiler: String = params.get("profiler", "")
	var enabled: bool = params.get("enabled", false)
	var data: Array = params.get("data", [])
	var session_id: int = params.get("session_id", -1)
	if profiler.is_empty():
		return {"error": "Missing required parameter: profiler"}
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	return bridge.toggle_profiler(profiler, enabled, data, session_id)

func _register_get_debugger_messages(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debugger_messages",
		"Read custom messages captured by the Godot debugger bridge.",
		{
			"type": "object",
			"properties": {
				"count": {"type": "integer", "default": 100},
				"offset": {"type": "integer", "default": 0},
				"order": {"type": "string", "enum": ["asc", "desc"], "default": "desc"}
			}
		},
		Callable(self, "_tool_get_debugger_messages"),
		{"type": "object", "properties": {"messages": {"type": "array"}, "count": {"type": "integer"}, "total_available": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debugger_messages(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	return bridge.get_captured_messages(params.get("count", 100), params.get("offset", 0), params.get("order", "desc"))

func _register_get_debug_state_events(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debug_state_events",
		"Read recorded debugger break/resume/stop state transitions from the bridge.",
		{
			"type": "object",
			"properties": {
				"count": {"type": "integer", "default": 100},
				"offset": {"type": "integer", "default": 0},
				"order": {"type": "string", "enum": ["asc", "desc"], "default": "desc"}
			}
		},
		Callable(self, "_tool_get_debug_state_events"),
		{"type": "object", "properties": {"events": {"type": "array"}, "count": {"type": "integer"}, "total_available": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debug_state_events(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	return bridge.get_state_events(params.get("count", 100), params.get("offset", 0), params.get("order", "desc"))

func _register_get_debug_output(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debug_output",
		"Read categorized runtime debugger output captured by the editor bridge.",
		{
			"type": "object",
			"properties": {
				"count": {"type": "integer", "default": 100},
				"offset": {"type": "integer", "default": 0},
				"order": {"type": "string", "enum": ["asc", "desc"], "default": "desc"},
				"category": {"type": "string", "enum": ["", "stdout", "stderr", "stdout_rich"], "default": ""}
			}
		},
		Callable(self, "_tool_get_debug_output"),
		{"type": "object", "properties": {"events": {"type": "array"}, "count": {"type": "integer"}, "total_available": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debug_output(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	return bridge.get_output_events(params.get("count", 100), params.get("offset", 0), params.get("order", "desc"), str(params.get("category", "")))

func _register_add_debugger_capture_prefix(server_core: RefCounted) -> void:
	server_core.register_tool(
		"add_debugger_capture_prefix",
		"Allow the debugger bridge to capture custom EngineDebugger messages with the given prefix.",
		{
			"type": "object",
			"properties": {
				"prefix": {"type": "string", "description": "Message prefix without the trailing colon, or * for all prefixes."}
			},
			"required": ["prefix"]
		},
		Callable(self, "_tool_add_debugger_capture_prefix"),
		{"type": "object", "properties": {"status": {"type": "string"}, "prefixes": {"type": "array"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_add_debugger_capture_prefix(params: Dictionary) -> Dictionary:
	var prefix: String = params.get("prefix", "")
	if prefix.is_empty():
		return {"error": "Missing required parameter: prefix"}
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	bridge.add_capture_prefix(prefix)
	return {"status": "success", "prefixes": bridge.get_capture_prefixes()}

func _register_get_debug_stack_frames(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debug_stack_frames",
		"Return the latest captured script stack frames and request a fresh stack dump from breaked sessions.",
		{
			"type": "object",
			"properties": {
				"refresh": {"type": "boolean", "default": true},
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all active sessions."}
			}
		},
		Callable(self, "_tool_get_debug_stack_frames"),
		{"type": "object", "properties": {"frames": {"type": "array"}, "count": {"type": "integer"}, "refresh_result": {"type": "object"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debug_stack_frames(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var refresh_result: Dictionary = {}
	if params.get("refresh", true):
		refresh_result = bridge.request_stack_dump(params.get("session_id", -1))
	var frames: Array = bridge.get_latest_stack_dump()
	return {"frames": frames, "count": frames.size(), "refresh_result": refresh_result}

func _register_get_debug_stack_variables(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debug_stack_variables",
		"Return latest captured local/member/global variables for a stack frame and request a fresh variable dump.",
		{
			"type": "object",
			"properties": {
				"frame": {"type": "integer", "default": 0},
				"refresh": {"type": "boolean", "default": true},
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all active sessions."}
			}
		},
		Callable(self, "_tool_get_debug_stack_variables"),
		{"type": "object", "properties": {"frame": {"type": "integer"}, "variables": {"type": "array"}, "count": {"type": "integer"}, "refresh_result": {"type": "object"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debug_stack_variables(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var frame: int = params.get("frame", 0)
	if frame < 0:
		return {"error": "frame must be >= 0"}
	var refresh_result: Dictionary = {}
	if params.get("refresh", true):
		refresh_result = bridge.request_stack_frame_vars(frame, params.get("session_id", -1))
	var variables: Array = bridge.get_latest_stack_variables(frame)
	return {"frame": frame, "variables": variables, "count": variables.size(), "refresh_result": refresh_result}

func _register_get_debug_scopes(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debug_scopes",
		"Group latest captured stack variables into DAP-like scopes for a frame.",
		{
			"type": "object",
			"properties": {
				"frame": {"type": "integer", "default": 0},
				"refresh": {"type": "boolean", "default": true},
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all active sessions."}
			}
		},
		Callable(self, "_tool_get_debug_scopes"),
		{"type": "object", "properties": {"frame": {"type": "integer"}, "scopes": {"type": "array"}, "count": {"type": "integer"}, "refresh_result": {"type": "object"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debug_scopes(params: Dictionary) -> Dictionary:
	var variables_result: Dictionary = _tool_get_debug_stack_variables(params)
	if variables_result.has("error"):
		return variables_result
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var frame: int = int(variables_result.get("frame", 0))
	var grouped: Dictionary = {}
	for variable_entry in variables_result.get("variables", []):
		var scope_name: String = str(variable_entry.get("scope", "unknown"))
		if not grouped.has(scope_name):
			grouped[scope_name] = []
		grouped[scope_name].append(variable_entry)

	var scopes: Array = []
	for scope_name in ["local", "member", "global", "constant", "unknown"]:
		if not grouped.has(scope_name):
			continue
		var dap_variables_reference: int = bridge.get_scope_variables_reference(frame, scope_name)
		scopes.append({
			"name": scope_name,
			"frame": frame,
			"variables_reference": "%d:%s" % [frame, scope_name],
			"dap_variables_reference": dap_variables_reference,
			"named_variables": grouped[scope_name].size(),
			"indexed_variables": 0,
			"presentation_hint": _debug_scope_presentation_hint(scope_name),
			"expensive": false
		})

	return {
		"frame": frame,
		"scopes": scopes,
		"count": scopes.size(),
		"refresh_result": variables_result.get("refresh_result", {})
	}

func _register_get_debug_variables(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_debug_variables",
		"Resolve a DAP-style variablesReference into child variables, with optional pagination for large arrays and dictionaries.",
		{
			"type": "object",
			"properties": {
				"variables_reference": {"type": "integer"},
				"offset": {"type": "integer", "default": 0},
				"count": {"type": "integer", "default": 100}
			},
			"required": ["variables_reference"]
		},
		Callable(self, "_tool_get_debug_variables"),
		{"type": "object", "properties": {"variables_reference": {"type": "integer"}, "variables": {"type": "array"}, "count": {"type": "integer"}, "total_available": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_debug_variables(params: Dictionary) -> Dictionary:
	var variables_reference: int = int(params.get("variables_reference", 0))
	if variables_reference <= 0:
		return {"error": "variables_reference must be > 0"}
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var result: Dictionary = bridge.get_variables_by_reference(
		variables_reference,
		int(params.get("count", 100)),
		int(params.get("offset", 0))
	)
	if result.get("total_available", 0) == 0:
		return {"error": "Unknown debug variables reference: " + str(variables_reference)}
	return result

func _register_expand_debug_variable(server_core: RefCounted) -> void:
	server_core.register_tool(
		"expand_debug_variable",
		"Expand a captured debug variable or evaluated expression value by scope and path, with pagination for arrays and dictionaries.",
		{
			"type": "object",
			"properties": {
				"frame": {"type": "integer", "default": 0},
				"scope": {"type": "string", "description": "Scope name such as local, member, global, constant, or evaluation."},
				"variable_path": {"type": "array", "items": {"type": "string"}, "description": "Path segments starting with the top-level variable name or expression text, then child keys or indices."},
				"offset": {"type": "integer", "default": 0},
				"count": {"type": "integer", "default": 100}
			},
			"required": ["scope", "variable_path"]
		},
		Callable(self, "_tool_expand_debug_variable"),
		{"type": "object", "properties": {"frame": {"type": "integer"}, "scope": {"type": "string"}, "variable_path": {"type": "array"}, "entries": {"type": "array"}, "count": {"type": "integer"}, "total_available": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_expand_debug_variable(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var frame: int = int(params.get("frame", 0))
	var scope: String = str(params.get("scope", "")).strip_edges().to_lower()
	var variable_path: Array = params.get("variable_path", [])
	if scope.is_empty():
		return {"error": "Missing required parameter: scope"}
	if variable_path.is_empty():
		return {"error": "Missing required parameter: variable_path"}

	var variables: Array = bridge.get_latest_stack_variables(frame)
	var current_value: Variant = null
	var current_type: String = ""
	if scope == "evaluation":
		var evaluation_entry: Variant = bridge.get_latest_evaluation(str(variable_path[0]))
		if evaluation_entry is Dictionary:
			current_value = evaluation_entry.get("value", null)
			current_type = str(evaluation_entry.get("type", ""))
	else:
		for variable_entry in variables:
			if str(variable_entry.get("scope", "")).to_lower() == scope and str(variable_entry.get("name", "")) == str(variable_path[0]):
				current_value = variable_entry.get("value", null)
				current_type = str(variable_entry.get("type", ""))
				break
	if current_type.is_empty():
		return {"error": "Debug variable not found in scope: " + str(variable_path[0])}

	for i in range(1, variable_path.size()):
		var step: String = str(variable_path[i])
		var resolved: Dictionary = _resolve_debug_path_step(current_value, step)
		if not resolved.get("ok", false):
			return {"error": "Value at path is not expandable: " + JSON.stringify(variable_path.slice(0, i))}
		current_value = resolved.get("value", null)

	var entries: Array = _expand_debug_value_entries(current_value, variable_path)
	var offset: int = max(0, int(params.get("offset", 0)))
	var count: int = max(0, int(params.get("count", 100)))
	var start: int = mini(offset, entries.size())
	var end: int = mini(start + count, entries.size())

	return {
		"frame": frame,
		"scope": scope,
		"variable_path": variable_path,
		"entries": entries.slice(start, end),
		"count": end - start,
		"total_available": entries.size()
	}

func _resolve_debug_path_step(current_value: Variant, step: String) -> Dictionary:
	if current_value is Array:
		if step == "size":
			return {"ok": true, "value": current_value.size()}
		if not step.is_valid_int():
			return {"ok": false}
		var index: int = int(step)
		if index < 0 or index >= current_value.size():
			return {"ok": false}
		return {"ok": true, "value": current_value[index]}
	match typeof(current_value):
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			if step == "size":
				return {"ok": true, "value": current_value.size()}
			if not step.is_valid_int():
				return {"ok": false}
			var packed_index: int = int(step)
			if packed_index < 0 or packed_index >= current_value.size():
				return {"ok": false}
			return {"ok": true, "value": current_value[packed_index]}
	if current_value is Dictionary:
		for key in current_value.keys():
			if str(key) == step:
				return {"ok": true, "value": current_value[key]}
		return {"ok": false}
	match typeof(current_value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			if step == "x" or step == "y":
				return {"ok": true, "value": current_value[step]}
		TYPE_VECTOR3, TYPE_VECTOR3I:
			if step == "x" or step == "y" or step == "z":
				return {"ok": true, "value": current_value[step]}
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_QUATERNION:
			if step == "x" or step == "y" or step == "z" or step == "w":
				return {"ok": true, "value": current_value[step]}
		TYPE_COLOR:
			if step == "r" or step == "g" or step == "b" or step == "a":
				return {"ok": true, "value": current_value[step]}
		TYPE_PLANE:
			if step == "normal":
				return {"ok": true, "value": current_value.normal}
			if step == "d":
				return {"ok": true, "value": current_value.d}
		TYPE_RECT2, TYPE_RECT2I, TYPE_AABB:
			if step == "position" or step == "size" or step == "end":
				return {"ok": true, "value": current_value[step]}
		TYPE_BASIS:
			if step == "x" or step == "y" or step == "z":
				return {"ok": true, "value": current_value[step]}
		TYPE_TRANSFORM2D:
			if step == "x" or step == "y" or step == "origin":
				return {"ok": true, "value": current_value[step]}
		TYPE_TRANSFORM3D:
			if step == "basis" or step == "origin":
				return {"ok": true, "value": current_value[step]}
		TYPE_PROJECTION:
			if step == "x" or step == "y" or step == "z" or step == "w":
				return {"ok": true, "value": current_value[step]}
		TYPE_OBJECT:
			return _resolve_debug_object_path_step(current_value, step)
	return {"ok": false}

func _resolve_debug_object_path_step(current_value: Variant, step: String) -> Dictionary:
	if typeof(current_value) != TYPE_OBJECT or current_value == null:
		return {"ok": false}
	var object_value: Object = current_value
	if not is_instance_valid(object_value):
		return {"ok": false}
	if step == "@class_name":
		return {"ok": true, "value": object_value.get_class()}
	if step == "@instance_id":
		return {"ok": true, "value": object_value.get_instance_id()}
	if step == "@script_path":
		var script: Script = object_value.get_script() as Script
		return {"ok": true, "value": String(script.resource_path) if script else ""}
	if step == "@node_path" and object_value is Node:
		var node_value: Node = object_value as Node
		var node_path: String = str(node_value.get_path())
		if node_path.is_empty() and not String(node_value.name).is_empty():
			node_path = "/" + String(node_value.name)
		return {"ok": true, "value": node_path}
	if step == "@resource_path" and object_value is Resource:
		return {"ok": true, "value": String((object_value as Resource).resource_path)}
	for property_info in object_value.get_property_list():
		var property_name: String = str(property_info.get("name", ""))
		if property_name != step:
			continue
		if property_name == "script" or property_name.begins_with("_") or property_name.contains("/"):
			return {"ok": false}
		var usage: int = int(property_info.get("usage", 0))
		var include_property: bool = (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 or (usage & PROPERTY_USAGE_STORAGE) != 0
		if not include_property:
			return {"ok": false}
		return {"ok": true, "value": object_value.get(property_name)}
	return {"ok": false}

func _register_evaluate_debug_expression(server_core: RefCounted) -> void:
	server_core.register_tool(
		"evaluate_debug_expression",
		"Evaluate an expression in the paused script debugger context for a given frame.",
		{
			"type": "object",
			"properties": {
				"expression": {"type": "string"},
				"frame": {"type": "integer", "default": 0},
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all active sessions."}
			},
			"required": ["expression"]
		},
		Callable(self, "_tool_evaluate_debug_expression"),
		{"type": "object", "properties": {"status": {"type": "string"}, "expression": {"type": "string"}, "frame": {"type": "integer"}, "type": {"type": "string"}, "value": {}, "has_children": {"type": "boolean"}, "refresh_result": {"type": "object"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_evaluate_debug_expression(params: Dictionary) -> Dictionary:
	var expression: String = str(params.get("expression", "")).strip_edges()
	if expression.is_empty():
		return {"error": "Missing required parameter: expression"}
	var frame: int = max(0, int(params.get("frame", 0)))
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var refresh_result: Dictionary = bridge.request_evaluate(expression, frame, int(params.get("session_id", -1)))
	if refresh_result.has("error"):
		return refresh_result
	var evaluation: Variant = bridge.get_latest_evaluation(expression)
	if evaluation == null:
		return {
			"status": "pending",
			"expression": expression,
			"frame": frame,
			"refresh_result": refresh_result
		}
	var value: Variant = evaluation.get("value", null) if evaluation is Dictionary else evaluation
	return {
		"status": "success",
		"expression": expression,
		"frame": frame,
		"type": str(evaluation.get("type", "")),
		"value": _serialize_runtime_value(value),
		"variables_reference": bridge.get_evaluation_variables_reference(expression),
		"named_variables": _debug_named_variable_count(value),
		"indexed_variables": _debug_indexed_variable_count(value),
		"has_children": _debug_value_has_children(value),
		"refresh_result": refresh_result
	}

func _debug_scope_presentation_hint(scope_name: String) -> String:
	match scope_name:
		"local":
			return "locals"
		"member":
			return "members"
		"global":
			return "globals"
		"constant":
			return "constants"
		_:
			return "unknown"

func _debug_named_variable_count(value: Variant) -> int:
	match typeof(value):
		TYPE_DICTIONARY:
			return value.size()
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return 2
		TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_RECT2, TYPE_RECT2I, TYPE_AABB, TYPE_BASIS:
			return 3
		TYPE_PLANE, TYPE_TRANSFORM3D:
			return 2
		TYPE_TRANSFORM2D:
			return 3
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PROJECTION, TYPE_COLOR, TYPE_QUATERNION:
			return 4
		TYPE_OBJECT:
			return _expand_debug_object_entries(value, []).size()
		_:
			return 0

func _debug_indexed_variable_count(value: Variant) -> int:
	match typeof(value):
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return value.size() + 1
		_:
			return 0

func _expand_debug_value_entries(value: Variant, parent_path: Array) -> Array:
	var entries: Array = []
	if value is Array:
		entries.append({
			"name": "size",
			"path": parent_path + ["size"],
			"type": "int",
			"value": value.size(),
			"has_children": false
		})
		for index in range(value.size()):
			var item: Variant = value[index]
			entries.append({
				"name": str(index),
				"path": parent_path + [str(index)],
				"type": type_string(typeof(item)),
				"value": _serialize_runtime_value(item),
				"has_children": _debug_value_has_children(item)
			})
	elif value is Dictionary:
		for key in value.keys():
			var item: Variant = value[key]
			entries.append({
				"name": str(key),
				"path": parent_path + [str(key)],
				"type": type_string(typeof(item)),
				"value": _serialize_runtime_value(item),
				"has_children": _debug_value_has_children(item)
			})
	else:
		match typeof(value):
			TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
				entries.append({
					"name": "size",
					"path": parent_path + ["size"],
					"type": "int",
					"value": value.size(),
					"has_children": false
				})
				for index in range(value.size()):
					var packed_item: Variant = value[index]
					entries.append({
						"name": str(index),
						"path": parent_path + [str(index)],
						"type": type_string(typeof(packed_item)),
						"value": _serialize_runtime_value(packed_item),
						"has_children": _debug_value_has_children(packed_item)
					})
				return entries
		var vector_entries: Array = _expand_debug_struct_fields(value, parent_path)
		if not vector_entries.is_empty():
			return vector_entries
		if typeof(value) == TYPE_OBJECT:
			return _expand_debug_object_entries(value, parent_path)
	return entries

func _expand_debug_struct_fields(value: Variant, parent_path: Array) -> Array:
	var entries: Array = []
	match typeof(value):
		TYPE_VECTOR2:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "float", "value": value.x, "has_children": false},
				{"name": "y", "path": parent_path + ["y"], "type": "float", "value": value.y, "has_children": false}
			])
		TYPE_VECTOR2I:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "int", "value": value.x, "has_children": false},
				{"name": "y", "path": parent_path + ["y"], "type": "int", "value": value.y, "has_children": false}
			])
		TYPE_VECTOR3:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "float", "value": value.x, "has_children": false},
				{"name": "y", "path": parent_path + ["y"], "type": "float", "value": value.y, "has_children": false},
				{"name": "z", "path": parent_path + ["z"], "type": "float", "value": value.z, "has_children": false}
			])
		TYPE_VECTOR3I:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "int", "value": value.x, "has_children": false},
				{"name": "y", "path": parent_path + ["y"], "type": "int", "value": value.y, "has_children": false},
				{"name": "z", "path": parent_path + ["z"], "type": "int", "value": value.z, "has_children": false}
			])
		TYPE_VECTOR4:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "float", "value": value.x, "has_children": false},
				{"name": "y", "path": parent_path + ["y"], "type": "float", "value": value.y, "has_children": false},
				{"name": "z", "path": parent_path + ["z"], "type": "float", "value": value.z, "has_children": false},
				{"name": "w", "path": parent_path + ["w"], "type": "float", "value": value.w, "has_children": false}
			])
		TYPE_VECTOR4I:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "int", "value": value.x, "has_children": false},
				{"name": "y", "path": parent_path + ["y"], "type": "int", "value": value.y, "has_children": false},
				{"name": "z", "path": parent_path + ["z"], "type": "int", "value": value.z, "has_children": false},
				{"name": "w", "path": parent_path + ["w"], "type": "int", "value": value.w, "has_children": false}
			])
		TYPE_PROJECTION:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "Vector4", "value": _serialize_runtime_value(value.x), "has_children": true},
				{"name": "y", "path": parent_path + ["y"], "type": "Vector4", "value": _serialize_runtime_value(value.y), "has_children": true},
				{"name": "z", "path": parent_path + ["z"], "type": "Vector4", "value": _serialize_runtime_value(value.z), "has_children": true},
				{"name": "w", "path": parent_path + ["w"], "type": "Vector4", "value": _serialize_runtime_value(value.w), "has_children": true}
			])
		TYPE_PLANE:
			entries.append_array([
				{"name": "normal", "path": parent_path + ["normal"], "type": "Vector3", "value": _serialize_runtime_value(value.normal), "has_children": true},
				{"name": "d", "path": parent_path + ["d"], "type": "float", "value": value.d, "has_children": false}
			])
		TYPE_RECT2:
			entries.append_array([
				{"name": "position", "path": parent_path + ["position"], "type": "Vector2", "value": _serialize_runtime_value(value.position), "has_children": true},
				{"name": "size", "path": parent_path + ["size"], "type": "Vector2", "value": _serialize_runtime_value(value.size), "has_children": true},
				{"name": "end", "path": parent_path + ["end"], "type": "Vector2", "value": _serialize_runtime_value(value.end), "has_children": true}
			])
		TYPE_RECT2I:
			entries.append_array([
				{"name": "position", "path": parent_path + ["position"], "type": "Vector2i", "value": _serialize_runtime_value(value.position), "has_children": true},
				{"name": "size", "path": parent_path + ["size"], "type": "Vector2i", "value": _serialize_runtime_value(value.size), "has_children": true},
				{"name": "end", "path": parent_path + ["end"], "type": "Vector2i", "value": _serialize_runtime_value(value.end), "has_children": true}
			])
		TYPE_AABB:
			entries.append_array([
				{"name": "position", "path": parent_path + ["position"], "type": "Vector3", "value": _serialize_runtime_value(value.position), "has_children": true},
				{"name": "size", "path": parent_path + ["size"], "type": "Vector3", "value": _serialize_runtime_value(value.size), "has_children": true},
				{"name": "end", "path": parent_path + ["end"], "type": "Vector3", "value": _serialize_runtime_value(value.end), "has_children": true}
			])
		TYPE_BASIS:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "Vector3", "value": _serialize_runtime_value(value.x), "has_children": true},
				{"name": "y", "path": parent_path + ["y"], "type": "Vector3", "value": _serialize_runtime_value(value.y), "has_children": true},
				{"name": "z", "path": parent_path + ["z"], "type": "Vector3", "value": _serialize_runtime_value(value.z), "has_children": true}
			])
		TYPE_COLOR:
			entries.append_array([
				{"name": "r", "path": parent_path + ["r"], "type": "float", "value": value.r, "has_children": false},
				{"name": "g", "path": parent_path + ["g"], "type": "float", "value": value.g, "has_children": false},
				{"name": "b", "path": parent_path + ["b"], "type": "float", "value": value.b, "has_children": false},
				{"name": "a", "path": parent_path + ["a"], "type": "float", "value": value.a, "has_children": false}
			])
		TYPE_QUATERNION:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "float", "value": value.x, "has_children": false},
				{"name": "y", "path": parent_path + ["y"], "type": "float", "value": value.y, "has_children": false},
				{"name": "z", "path": parent_path + ["z"], "type": "float", "value": value.z, "has_children": false},
				{"name": "w", "path": parent_path + ["w"], "type": "float", "value": value.w, "has_children": false}
			])
		TYPE_TRANSFORM2D:
			entries.append_array([
				{"name": "x", "path": parent_path + ["x"], "type": "Vector2", "value": _serialize_runtime_value(value.x), "has_children": true},
				{"name": "y", "path": parent_path + ["y"], "type": "Vector2", "value": _serialize_runtime_value(value.y), "has_children": true},
				{"name": "origin", "path": parent_path + ["origin"], "type": "Vector2", "value": _serialize_runtime_value(value.origin), "has_children": true}
			])
		TYPE_TRANSFORM3D:
			entries.append_array([
				{"name": "basis", "path": parent_path + ["basis"], "type": "Basis", "value": _serialize_runtime_value(value.basis), "has_children": true},
				{"name": "origin", "path": parent_path + ["origin"], "type": "Vector3", "value": _serialize_runtime_value(value.origin), "has_children": true}
			])
	return entries

func _expand_debug_object_entries(value: Variant, parent_path: Array) -> Array:
	if typeof(value) != TYPE_OBJECT or value == null:
		return []
	var object_value: Object = value
	if not is_instance_valid(object_value):
		return []
	var entries: Array = []
	var seen: Dictionary = {}
	entries.append({
		"name": "@class_name",
		"path": parent_path + ["@class_name"],
		"type": "String",
		"value": object_value.get_class(),
		"has_children": false
	})
	entries.append({
		"name": "@instance_id",
		"path": parent_path + ["@instance_id"],
		"type": "int",
		"value": object_value.get_instance_id(),
		"has_children": false
	})
	var script: Script = object_value.get_script() as Script
	entries.append({
		"name": "@script_path",
		"path": parent_path + ["@script_path"],
		"type": "String",
		"value": String(script.resource_path) if script else "",
		"has_children": false
	})
	if object_value is Node:
		var node_value: Node = object_value as Node
		var node_path: String = str(node_value.get_path())
		if node_path.is_empty() and not String(node_value.name).is_empty():
			node_path = "/" + String(node_value.name)
		entries.append({
			"name": "@node_path",
			"path": parent_path + ["@node_path"],
			"type": "NodePath",
			"value": node_path,
			"has_children": false
		})
	elif object_value is Resource:
		entries.append({
			"name": "@resource_path",
			"path": parent_path + ["@resource_path"],
			"type": "String",
			"value": String((object_value as Resource).resource_path),
			"has_children": false
		})
	for property_info in object_value.get_property_list():
		var property_name: String = str(property_info.get("name", ""))
		if property_name.is_empty() or seen.has(property_name):
			continue
		if property_name == "script" or property_name.begins_with("_") or property_name.contains("/"):
			continue
		var usage: int = int(property_info.get("usage", 0))
		var include_property: bool = (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 or (usage & PROPERTY_USAGE_STORAGE) != 0
		if not include_property:
			continue
		seen[property_name] = true
		var property_value: Variant = object_value.get(property_name)
		entries.append({
			"name": property_name,
			"path": parent_path + [property_name],
			"type": type_string(typeof(property_value)),
			"value": _serialize_runtime_value(property_value),
			"has_children": _debug_value_has_children(property_value)
		})
	return entries

func _debug_value_has_children(value: Variant) -> bool:
	match typeof(value):
		TYPE_ARRAY, TYPE_DICTIONARY, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PROJECTION, TYPE_PLANE, TYPE_RECT2, TYPE_RECT2I, TYPE_AABB, TYPE_BASIS, TYPE_COLOR, TYPE_QUATERNION, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D:
			return true
		TYPE_OBJECT:
			return not _expand_debug_object_entries(value, []).is_empty()
		_:
			return false

func _serialize_runtime_value(value: Variant) -> Variant:
	if value == null:
		return null
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return str(value)
		TYPE_NODE_PATH:
			return str(value)
		TYPE_RID:
			return {
				"id": value.get_id(),
				"valid": value.is_valid()
			}
		TYPE_CALLABLE:
			return _serialize_runtime_callable(value)
		TYPE_SIGNAL:
			return _serialize_runtime_signal(value)
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR4:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_VECTOR4I:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_PROJECTION:
			return {
				"x": _serialize_runtime_value(value.x),
				"y": _serialize_runtime_value(value.y),
				"z": _serialize_runtime_value(value.z),
				"w": _serialize_runtime_value(value.w)
			}
		TYPE_PLANE:
			return {
				"normal": _serialize_runtime_value(value.normal),
				"d": value.d
			}
		TYPE_RECT2:
			return {
				"position": _serialize_runtime_value(value.position),
				"size": _serialize_runtime_value(value.size),
				"end": _serialize_runtime_value(value.end)
			}
		TYPE_RECT2I:
			return {
				"position": _serialize_runtime_value(value.position),
				"size": _serialize_runtime_value(value.size),
				"end": _serialize_runtime_value(value.end)
			}
		TYPE_AABB:
			return {
				"position": _serialize_runtime_value(value.position),
				"size": _serialize_runtime_value(value.size),
				"end": _serialize_runtime_value(value.end)
			}
		TYPE_BASIS:
			return {
				"x": _serialize_runtime_value(value.x),
				"y": _serialize_runtime_value(value.y),
				"z": _serialize_runtime_value(value.z)
			}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_QUATERNION:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_TRANSFORM2D:
			return {
				"x": _serialize_runtime_value(value.x),
				"y": _serialize_runtime_value(value.y),
				"origin": _serialize_runtime_value(value.origin)
			}
		TYPE_TRANSFORM3D:
			return {
				"basis": _serialize_runtime_value(value.basis),
				"origin": _serialize_runtime_value(value.origin)
			}
		TYPE_OBJECT:
			return _serialize_runtime_object(value)
		TYPE_ARRAY:
			var array_result: Array = []
			for item in value:
				array_result.append(_serialize_runtime_value(item))
			return array_result
		TYPE_DICTIONARY:
			var dict_result: Dictionary = {}
			for key in value:
				dict_result[str(key)] = _serialize_runtime_value(value[key])
			return dict_result
		_:
			return str(value)

func _serialize_runtime_object(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_OBJECT or value == null:
		return {}
	var object_value: Object = value
	if not is_instance_valid(object_value):
		return {"class_name": "<freed>"}
	var properties: Dictionary = {}
	for entry in _expand_debug_object_entries(object_value, []):
		properties[str(entry.get("name", ""))] = entry.get("value", null)
	var serialized: Dictionary = {
		"class_name": object_value.get_class(),
		"instance_id": object_value.get_instance_id(),
		"script_path": "",
		"properties": properties
	}
	var script: Script = object_value.get_script() as Script
	if script:
		serialized["script_path"] = String(script.resource_path)
	if object_value is Node:
		var node_value: Node = object_value as Node
		var node_path: String = str(node_value.get_path())
		if node_path.is_empty() and not String(node_value.name).is_empty():
			node_path = "/" + String(node_value.name)
		serialized["node_path"] = node_path
	elif object_value is Resource:
		serialized["resource_path"] = String((object_value as Resource).resource_path)
	return serialized

func _serialize_runtime_callable(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_CALLABLE:
		return {}
	var callable_value: Callable = value
	var target: Object = callable_value.get_object()
	return {
		"method": callable_value.get_method(),
		"object_id": callable_value.get_object_id(),
		"object_class": target.get_class() if is_instance_valid(target) else "",
		"is_custom": callable_value.is_custom(),
		"is_standard": callable_value.is_standard(),
		"is_null": callable_value.is_null(),
		"is_valid": callable_value.is_valid(),
		"bound_argument_count": callable_value.get_bound_arguments_count()
	}

func _serialize_runtime_signal(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_SIGNAL:
		return {}
	var signal_value: Signal = value
	var target: Object = signal_value.get_object()
	return {
		"name": signal_value.get_name(),
		"object_id": target.get_instance_id() if is_instance_valid(target) else 0,
		"object_class": target.get_class() if is_instance_valid(target) else "",
		"is_null": signal_value.is_null()
	}

func _register_install_runtime_probe(server_core: RefCounted) -> void:
	server_core.register_tool(
		"install_runtime_probe",
		"Register the MCP runtime probe as an Autoload singleton so the running game can answer debugger messages. Survives scene changes.",
		{
			"type": "object",
			"properties": {
				"node_name": {"type": "string", "default": "MCPRuntimeProbe"}
			}
		},
		Callable(self, "_tool_install_runtime_probe"),
		{"type": "object", "properties": {"status": {"type": "string"}, "node_path": {"type": "string"}, "autoload": {"type": "boolean"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_install_runtime_probe(params: Dictionary) -> Dictionary:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}
	
	var node_name: String = params.get("node_name", "MCPRuntimeProbe")
	if node_name.is_empty():
		return {"error": "node_name cannot be empty"}
	
	# Register the probe as an Autoload singleton via ProjectSettings.
	# Using the "*" prefix marks it as a global singleton that survives
	# scene changes and is never written into .tscn files.
	var autoload_key: String = "autoload/" + node_name
	var autoload_path: String = "*res://addons/godot_mcp/runtime/mcp_runtime_probe.gd"
	
	if ProjectSettings.has_setting(autoload_key):
		return {"status": "already_installed", "node_path": node_name}
	
	ProjectSettings.set_setting(autoload_key, autoload_path)
	ProjectSettings.save()
	
	return {"status": "success", "node_path": node_name, "autoload": true}

func _register_remove_runtime_probe(server_core: RefCounted) -> void:
	server_core.register_tool(
		"remove_runtime_probe",
		"Remove the MCP runtime probe node from the current scene.",
		{
			"type": "object",
			"properties": {
				"node_name": {"type": "string", "default": "MCPRuntimeProbe"}
			}
		},
		Callable(self, "_tool_remove_runtime_probe"),
		{"type": "object", "properties": {"status": {"type": "string"}, "removed_node": {"type": "string"}}},
		{"readOnlyHint": false, "destructiveHint": true, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_remove_runtime_probe(params: Dictionary) -> Dictionary:
	var node_name: String = params.get("node_name", "MCPRuntimeProbe")
	var autoload_key: String = "autoload/" + node_name
	
	if not ProjectSettings.has_setting(autoload_key):
		return {"status": "not_installed", "removed_node": ""}
	
	ProjectSettings.clear(autoload_key)
	ProjectSettings.save()
	return {"status": "success", "removed_node": node_name}

func _register_request_debug_break(server_core: RefCounted) -> void:
	server_core.register_tool(
		"request_debug_break",
		"Ask the MCP runtime probe to enter Godot's script debugger break loop.",
		{
			"type": "object",
			"properties": {
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all active sessions."}
			}
		},
		Callable(self, "_tool_request_debug_break"),
		{"type": "object", "properties": {"status": {"type": "string"}, "sessions_updated": {"type": "integer"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_request_debug_break(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	return bridge.send_debugger_message("mcp:debug_break", [], params.get("session_id", -1))

func _register_send_debug_command(server_core: RefCounted) -> void:
	server_core.register_tool(
		"send_debug_command",
		"Send a raw Godot script-debugger command to active breaked sessions. Commands are handled by Godot's debug loop.",
		{
			"type": "object",
			"properties": {
				"command": {"type": "string", "enum": ["step", "next", "out", "continue", "get_stack_dump", "get_stack_frame_vars"]},
				"data": {"type": "array", "items": {"type": "object"}, "description": "Command payload, e.g. [0] for get_stack_frame_vars frame 0."},
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all active sessions."}
			},
			"required": ["command"]
		},
		Callable(self, "_tool_send_debug_command"),
		{"type": "object", "properties": {"status": {"type": "string"}, "sessions_updated": {"type": "integer"}, "note": {"type": "string"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_send_debug_command(params: Dictionary) -> Dictionary:
	var command: String = params.get("command", "")
	var allowed: Array[String] = ["step", "next", "out", "continue", "get_stack_dump", "get_stack_frame_vars"]
	if not allowed.has(command):
		return {"error": "Unsupported debug command: " + command}
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var result: Dictionary = bridge.send_debugger_message(command, params.get("data", []), params.get("session_id", -1))
	if command.begins_with("get_stack"):
		result["note"] = "Godot may route stack responses to the built-in ScriptEditorDebugger UI instead of EditorDebuggerPlugin captures."
	return result

func _register_debug_step_into(server_core: RefCounted) -> void:
	_register_debug_execution_control_tool(
		server_core,
		"debug_step_into",
		"Step into the next statement in the active Godot script debugger session.",
		"step",
		"breaked"
	)

func _register_debug_step_over(server_core: RefCounted) -> void:
	_register_debug_execution_control_tool(
		server_core,
		"debug_step_over",
		"Step over the next statement in the active Godot script debugger session.",
		"next",
		"breaked"
	)

func _register_debug_step_out(server_core: RefCounted) -> void:
	_register_debug_execution_control_tool(
		server_core,
		"debug_step_out",
		"Step out of the current frame in the active Godot script debugger session.",
		"out",
		"breaked"
	)

func _register_debug_continue(server_core: RefCounted) -> void:
	_register_debug_execution_control_tool(
		server_core,
		"debug_continue",
		"Resume execution in the active Godot script debugger session.",
		"continue",
		"running"
	)

func _register_debug_execution_control_tool(server_core: RefCounted, tool_name: String, description: String, command: String, target_state: String) -> void:
	server_core.register_tool(
		tool_name,
		description,
		{
			"type": "object",
			"properties": {
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all active sessions."}
			}
		},
		func(params: Dictionary) -> Dictionary:
			return _tool_debug_execution_control(params, command, target_state),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"sessions_updated": {"type": "integer"},
				"command": {"type": "string"},
				"target_state": {"type": "string"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_debug_execution_control(params: Dictionary, command: String, target_state: String) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var result: Dictionary = bridge.send_debugger_message(command, [], params.get("session_id", -1))
	result["command"] = command
	result["target_state"] = target_state
	return result

func _register_debug_step_into_and_wait(server_core: RefCounted) -> void:
	_register_debug_execution_wait_tool(server_core, "debug_step_into_and_wait", "Send a step-into command and wait for the debugger to report a breaked state.", "step", "breaked")

func _register_debug_step_over_and_wait(server_core: RefCounted) -> void:
	_register_debug_execution_wait_tool(server_core, "debug_step_over_and_wait", "Send a step-over command and wait for the debugger to report a breaked state.", "next", "breaked")

func _register_debug_step_out_and_wait(server_core: RefCounted) -> void:
	_register_debug_execution_wait_tool(server_core, "debug_step_out_and_wait", "Send a step-out command and wait for the debugger to report a breaked state.", "out", "breaked")

func _register_debug_continue_and_wait(server_core: RefCounted) -> void:
	_register_debug_execution_wait_tool(server_core, "debug_continue_and_wait", "Send a continue command and wait for the debugger to report a running state.", "continue", "running")

func _register_debug_execution_wait_tool(server_core: RefCounted, tool_name: String, description: String, command: String, target_state: String) -> void:
	server_core.register_tool(
		tool_name,
		description,
		{
			"type": "object",
			"properties": {
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for all active sessions."},
				"timeout_ms": {"type": "integer", "default": 3000},
				"poll_interval_ms": {"type": "integer", "default": 100}
			}
		},
		func(params: Dictionary) -> Dictionary:
			return _tool_debug_execution_and_wait(params, command, target_state),
		{"type": "object", "properties": {"status": {"type": "string"}, "command": {"type": "string"}, "target_state": {"type": "string"}, "matched_state": {"type": "object"}, "sessions": {"type": "array"}, "state_events": {"type": "array"}, "attempts": {"type": "integer"}, "elapsed_ms": {"type": "integer"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_debug_execution_and_wait(params: Dictionary, command: String, target_state: String) -> Dictionary:
	var command_result: Dictionary = _tool_debug_execution_control(params, command, target_state)
	if command_result.has("error"):
		return command_result
	var wait_params: Dictionary = {
		"target_state": target_state,
		"session_id": params.get("session_id", -1),
		"timeout_ms": params.get("timeout_ms", 3000),
		"poll_interval_ms": params.get("poll_interval_ms", 100)
	}
	var wait_result: Dictionary = _tool_await_debugger_state(wait_params)
	wait_result["command"] = command
	wait_result["target_state"] = target_state
	wait_result["command_result"] = command_result
	return wait_result

func _register_await_debugger_state(server_core: RefCounted) -> void:
	server_core.register_tool(
		"await_debugger_state",
		"Check whether debugger sessions have reached the target execution state using the latest bridge snapshots. Call repeatedly from the client after continue/step/next/out/break actions.",
		{
			"type": "object",
			"properties": {
				"target_state": {"type": "string", "enum": ["breaked", "running", "stopped"], "default": "breaked"},
				"session_id": {"type": "integer", "description": "Optional debugger session id. Omit or use -1 for any session."},
				"timeout_ms": {"type": "integer", "default": 3000},
				"poll_interval_ms": {"type": "integer", "default": 100}
			}
		},
		Callable(self, "_tool_await_debugger_state"),
		{"type": "object", "properties": {"status": {"type": "string"}, "target_state": {"type": "string"}, "matched_state": {"type": "object"}, "sessions": {"type": "array"}, "state_events": {"type": "array"}, "attempts": {"type": "integer"}, "elapsed_ms": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"supplementary", "Debug-Advanced"
	)

func _tool_await_debugger_state(params: Dictionary) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var target_state: String = str(params.get("target_state", "breaked"))
	var timeout_ms: int = max(1, int(params.get("timeout_ms", 3000)))
	var session_id: int = int(params.get("session_id", -1))
	var last_sessions: Array = bridge.get_sessions_info()
	var state_events: Array = bridge.get_state_events(20, 0, "desc").get("events", [])
	var matched_state: Dictionary = _find_matching_debug_state(target_state, last_sessions, state_events, session_id)
	if not matched_state.is_empty():
		return {
			"status": "success",
			"target_state": target_state,
			"matched_state": matched_state,
			"sessions": last_sessions,
			"state_events": state_events,
			"attempts": 1,
			"elapsed_ms": 0
		}
	return {
		"status": "pending",
		"target_state": target_state,
		"matched_state": {},
		"sessions": last_sessions,
		"state_events": state_events,
		"attempts": 1,
		"elapsed_ms": timeout_ms
	}

func _find_matching_debug_state(target_state: String, sessions: Array, state_events: Array, session_id: int) -> Dictionary:
	match target_state:
		"breaked":
			for session in sessions:
				if session_id >= 0 and int(session.get("session_id", -1)) != session_id:
					continue
				if session.get("breaked", false):
					var result: Dictionary = session.duplicate(true)
					result["state"] = "breaked"
					for event in state_events:
						if event.get("state", "") == "breaked":
							result["reason"] = event.get("reason", "")
							result["has_stackdump"] = event.get("has_stackdump", false)
							break
					return result
		"running":
			for session in sessions:
				if session_id >= 0 and int(session.get("session_id", -1)) != session_id:
					continue
				if session.get("active", false) and not session.get("breaked", false):
					var result: Dictionary = session.duplicate(true)
					result["state"] = "running"
					for event in state_events:
						if event.get("state", "") == "running":
							result["reason"] = event.get("reason", "")
							break
					return result
		"stopped":
			if session_id >= 0:
				for session in sessions:
					if int(session.get("session_id", -1)) == session_id:
						return {}
			if sessions.is_empty():
				for event in state_events:
					if event.get("state", "") == "stopped":
						return event.duplicate(true)
				return {"state": "stopped"}
	return {}

func _register_get_runtime_info(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_info",
		"Query the running game instance through the MCP runtime probe and return runtime metrics.",
		{"type": "object", "properties": {"session_id": {"type": "integer"}, "timeout_ms": {"type": "integer", "default": 1500}}},
		Callable(self, "_tool_get_runtime_info"),
		{"type": "object", "properties": {"fps": {"type": "number"}, "physics_frames": {"type": "integer"}, "process_frames": {"type": "integer"}, "debugger_active": {"type": "boolean"}, "current_scene": {"type": "string"}, "node_count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_info(params: Dictionary) -> Dictionary:
	var result: Dictionary = await _request_runtime_probe_poll("get_runtime_info", [], ["mcp:runtime_info"], params)
	if result.get("status", "") in ["pending", "stale"]:
		var bridge: RefCounted = _get_debugger_bridge()
		if bridge:
			var latest_runtime_info: Variant = bridge.get_latest_message_payload("mcp:runtime_info")
			if latest_runtime_info is Dictionary:
				var stale_runtime: Dictionary = latest_runtime_info.duplicate(true)
				stale_runtime["status"] = "stale"
				stale_runtime["stale"] = true
				stale_runtime["refresh_result"] = result.get("refresh_result", {})
				return stale_runtime
			var probe_ready: Variant = bridge.get_latest_message_payload("mcp:probe_ready")
			if probe_ready is Dictionary:
				var fallback: Dictionary = probe_ready.duplicate(true)
				fallback["status"] = "stale"
				fallback["stale"] = true
				fallback["refresh_result"] = result.get("refresh_result", {})
				return fallback
	return result

func _register_await_scene_ready(server_core: RefCounted) -> void:
	server_core.register_tool(
		"await_scene_ready",
		"Poll the runtime until the specified scene is loaded and ready. Internally checks get_runtime_info().current_scene until it matches the requested scene name.",
		{
			"type": "object",
			"properties": {
				"scene_name": {
					"type": "string",
					"description": "The expected scene name (e.g. 'Main', 'GameLevel'). The tool waits until current_scene contains this name."
				},
				"timeout_sec": {
					"type": "number",
					"description": "Maximum time to wait in seconds.",
					"default": 10
				},
				"session_id": {"type": "integer"}
			},
			"required": ["scene_name"]
		},
		Callable(self, "_tool_await_scene_ready"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"scene_name": {"type": "string"},
				"elapsed_sec": {"type": "number"},
				"timeout": {"type": "boolean"},
				"attempts": {"type": "integer"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_await_scene_ready(params: Dictionary) -> Dictionary:
	var scene_name: String = params.get("scene_name", "")
	if scene_name.is_empty():
		return {"error": "Missing required parameter: scene_name"}

	var timeout_sec: float = float(params.get("timeout_sec", 10.0))
	var timeout_ms: int = int(timeout_sec * 1000)
	var poll_interval_ms: int = 200
	var deadline_ms: int = Time.get_ticks_msec() + timeout_ms
	var attempts: int = 0

	while Time.get_ticks_msec() < deadline_ms:
		attempts += 1
		var runtime_info: Dictionary = await _tool_get_runtime_info(params)

		if runtime_info.has("error"):
			# Probe might not be ready yet, wait and retry
			if Time.get_ticks_msec() + poll_interval_ms < deadline_ms:
				var tree: SceneTree = Engine.get_main_loop() as SceneTree
				if tree:
					await tree.process_frame
				else:
					OS.delay_msec(poll_interval_ms)
				continue
			else:
				return {
					"status": "timeout",
					"scene_name": scene_name,
					"elapsed_sec": timeout_sec,
					"timeout": true,
					"error": "Timeout waiting for scene: " + runtime_info.get("error", "probe not available"),
					"attempts": attempts
				}

		var current_scene_path: String = runtime_info.get("current_scene", "")
		if not current_scene_path.is_empty() and current_scene_path.contains(scene_name):
			var elapsed: float = (Time.get_ticks_msec() - (deadline_ms - timeout_ms)) / 1000.0
			return {
				"status": "success",
				"scene_name": scene_name,
				"elapsed_sec": elapsed,
				"timeout": false,
				"attempts": attempts
			}

		# Wait before next poll
		if Time.get_ticks_msec() + poll_interval_ms < deadline_ms:
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			if tree:
				await tree.process_frame
			else:
				OS.delay_msec(poll_interval_ms)

	return {
		"status": "timeout",
		"scene_name": scene_name,
		"elapsed_sec": timeout_sec,
		"timeout": true,
		"attempts": attempts,
		"error": "Timeout: scene '" + scene_name + "' not ready after " + str(timeout_sec) + " seconds"
	}

func _register_get_runtime_performance_snapshot(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_performance_snapshot",
		"Capture a runtime performance snapshot from the running game, including frame timing, object counts, and memory usage.",
		{"type": "object", "properties": {"session_id": {"type": "integer"}, "timeout_ms": {"type": "integer", "default": 1500}}},
		Callable(self, "_tool_get_runtime_performance_snapshot"),
		{"type": "object", "properties": {"fps": {"type": "number"}, "frame_time_sec": {"type": "number"}, "physics_frame_time_sec": {"type": "number"}, "object_count": {"type": "integer"}, "resource_count": {"type": "integer"}, "rendered_objects_in_frame": {"type": "integer"}, "memory_static_bytes": {"type": "integer"}, "memory_static_mb": {"type": "number"}, "current_scene": {"type": "string"}, "node_count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_performance_snapshot(params: Dictionary) -> Dictionary:
	var result: Dictionary = await _request_runtime_probe_poll("get_performance_snapshot", [], ["mcp:performance_snapshot"], params)
	if result.get("status", "") == "pending":
		var bridge: RefCounted = _get_debugger_bridge()
		if bridge:
			var latest_snapshot: Variant = bridge.get_latest_message_payload("mcp:performance_snapshot")
			if latest_snapshot is Dictionary:
				var stale_snapshot: Dictionary = latest_snapshot.duplicate(true)
				stale_snapshot["status"] = "stale"
				stale_snapshot["refresh_result"] = result.get("refresh_result", {})
				return stale_snapshot
	return result

func _register_get_runtime_memory_trend(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_memory_trend",
		"Capture a short runtime memory and object-count trend from the running game over multiple samples.",
		{
			"type": "object",
			"properties": {
				"sample_count": {"type": "integer", "default": 5},
				"sample_interval_ms": {"type": "integer", "default": 100},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 3000}
			}
		},
		Callable(self, "_tool_get_runtime_memory_trend"),
		{
			"type": "object",
			"properties": {
				"sample_count": {"type": "integer"},
				"sample_interval_ms": {"type": "integer"},
				"memory_static_delta_bytes": {"type": "integer"},
				"object_count_delta": {"type": "integer"},
				"resource_count_delta": {"type": "integer"},
				"current_scene": {"type": "string"},
				"samples": {"type": "array"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_memory_trend(params: Dictionary) -> Dictionary:
	var sample_count: int = max(int(params.get("sample_count", 5)), 1)
	var sample_interval_ms: int = max(int(params.get("sample_interval_ms", 100)), 0)
	var result: Dictionary = await _request_runtime_probe_poll(
		"get_memory_trend",
		[sample_count, sample_interval_ms],
		["mcp:memory_trend"],
		params,
		{
			"sample_count": sample_count,
			"sample_interval_ms": sample_interval_ms
		}
	)
	if result.get("status", "") == "pending":
		var bridge: RefCounted = _get_debugger_bridge()
		if bridge:
			var latest_trend: Variant = bridge.get_latest_message_payload("mcp:memory_trend")
			if latest_trend is Dictionary \
					and int(latest_trend.get("sample_count", -1)) == sample_count \
					and int(latest_trend.get("sample_interval_ms", -1)) == sample_interval_ms:
				var stale_trend: Dictionary = latest_trend.duplicate(true)
				stale_trend["status"] = "stale"
				stale_trend["refresh_result"] = result.get("refresh_result", {})
				return stale_trend
	return result

func _register_get_runtime_scene_tree(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_scene_tree",
		"Read the live runtime scene tree from the running game instance.",
		{"type": "object", "properties": {"max_depth": {"type": "integer", "default": 6}, "session_id": {"type": "integer"}, "timeout_ms": {"type": "integer", "default": 1500}}},
		Callable(self, "_tool_get_runtime_scene_tree"),
		{"type": "object", "properties": {"name": {"type": "string"}, "type": {"type": "string"}, "path": {"type": "string"}, "child_count": {"type": "integer"}, "children": {"type": "array"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_scene_tree(params: Dictionary) -> Dictionary:
	var result: Dictionary = await _request_runtime_probe_poll("get_scene_tree", [params.get("max_depth", 6)], ["mcp:scene_tree"], params)
	if result.get("status", "") in ["pending", "stale"]:
		# Check runtime info to verify game session is alive
		var runtime_info: Dictionary = await _tool_get_runtime_info(params)
		var is_stale: bool = runtime_info.get("stale", false) or result.get("stale", false)
		if is_stale or result.get("status", "") == "stale":
			return {
				"status": "stale",
				"stale": true,
				"scene_tree": {},
				"message": "Game session is no longer active. The returned scene tree may be cached data from a previous session.",
				"node_count": 0
			}
	return result

func _register_inspect_runtime_node(server_core: RefCounted) -> void:
	server_core.register_tool(
		"inspect_runtime_node",
		"Inspect a live runtime node and its serializable properties through the runtime probe.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_inspect_runtime_node"),
		{"type": "object", "properties": {"name": {"type": "string"}, "type": {"type": "string"}, "path": {"type": "string"}, "properties": {"type": "object"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_inspect_runtime_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("inspect_node", [node_path], ["mcp:node"], params, {"path": node_path})

func _register_create_runtime_node(server_core: RefCounted) -> void:
	server_core.register_tool(
		"create_runtime_node",
		"Create a new runtime node under an existing parent node in the running game.",
		{
			"type": "object",
			"properties": {
				"parent_path": {"type": "string", "description": "Runtime node path for the parent, e.g. /root/MainScene"},
				"node_type": {"type": "string", "description": "Godot node class name to instantiate, e.g. Node2D or Sprite2D."},
				"node_name": {"type": "string", "description": "Name for the new runtime node."},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["parent_path", "node_type", "node_name"]
		},
		Callable(self, "_tool_create_runtime_node"),
		{"type": "object", "properties": {"parent_path": {"type": "string"}, "node_path": {"type": "string"}, "node_type": {"type": "string"}, "node_name": {"type": "string"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_create_runtime_node(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var node_type: String = params.get("node_type", "")
	var node_name: String = params.get("node_name", "")
	if parent_path.is_empty():
		return {"error": "Missing required parameter: parent_path"}
	if node_type.is_empty():
		return {"error": "Missing required parameter: node_type"}
	if node_name.is_empty():
		return {"error": "Missing required parameter: node_name"}
	return await _request_runtime_probe_poll("create_node", [parent_path, node_type, node_name], ["mcp:runtime_node_created"], params, {"node_path": parent_path.path_join(node_name)})

func _register_delete_runtime_node(server_core: RefCounted) -> void:
	server_core.register_tool(
		"delete_runtime_node",
		"Delete a runtime node from the running game. The runtime scene root and MCPRuntimeProbe node are protected.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string", "description": "Runtime node path to delete, e.g. /root/MainScene/Enemy"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_delete_runtime_node"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "node_type": {"type": "string"}}},
		{"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_delete_runtime_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("delete_node", [node_path], ["mcp:runtime_node_deleted"], params, {"node_path": node_path})

func _register_update_runtime_node_property(server_core: RefCounted) -> void:
	server_core.register_tool(
		"update_runtime_node_property",
		"Modify a property on a live runtime node through the runtime probe.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"property_name": {"type": "string"},
				"property_value": {},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "property_name", "property_value"]
		},
		Callable(self, "_tool_update_runtime_node_property"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "property_name": {"type": "string"}, "old_value": {}, "new_value": {}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_update_runtime_node_property(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var property_name: String = params.get("property_name", "")
	if node_path.is_empty() or property_name.is_empty() or not params.has("property_value"):
		return {"error": "node_path, property_name, and property_value are required"}
	return await _request_runtime_probe_poll("set_node_property", [node_path, property_name, params.get("property_value")], ["mcp:node_property_updated"], params, {"node_path": node_path, "property_name": property_name})

func _register_call_runtime_node_method(server_core: RefCounted) -> void:
	server_core.register_tool(
		"call_runtime_node_method",
		"Call a method on a live runtime node and return the serialized result.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"method_name": {"type": "string"},
				"arguments": {"type": "array", "items": {"type": "object"}},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "method_name"]
		},
		Callable(self, "_tool_call_runtime_node_method"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "method_name": {"type": "string"}, "arguments": {"type": "array", "items": {"type": "object"}}, "result": {}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_call_runtime_node_method(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var method_name: String = params.get("method_name", "")
	if node_path.is_empty() or method_name.is_empty():
		return {"error": "node_path and method_name are required"}
	return await _request_runtime_probe_poll("call_node_method", [node_path, method_name, params.get("arguments", [])], ["mcp:node_method_result"], params, {"node_path": node_path, "method_name": method_name})

func _register_evaluate_runtime_expression(server_core: RefCounted) -> void:
	server_core.register_tool(
		"evaluate_runtime_expression",
		"Evaluate a GDScript Expression in the running game, optionally relative to a target node.",
		{
			"type": "object",
			"properties": {
				"expression": {"type": "string"},
				"node_path": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["expression"]
		},
		Callable(self, "_tool_evaluate_runtime_expression"),
		{"type": "object", "properties": {"expression": {"type": "string"}, "node_path": {"type": "string"}, "value": {}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_evaluate_runtime_expression(params: Dictionary) -> Dictionary:
	var expression: String = params.get("expression", "")
	if expression.is_empty():
		return {"error": "Missing required parameter: expression"}
	var payload: Array = [expression, params.get("node_path", "")]
	return await _request_runtime_probe_poll("evaluate_expression", payload, ["mcp:expression_result"], params, {"expression": expression})

func _register_simulate_runtime_input_event(server_core: RefCounted) -> void:
	server_core.register_tool(
		"simulate_runtime_input_event",
		"Inject a structured InputEvent into the running game through Input.parse_input_event().",
		{
			"type": "object",
			"properties": {
				"event": {
					"type": "object",
					"description": "Structured input event payload. Supported types: action, key, mouse_button, mouse_motion."
				},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["event"]
		},
		Callable(self, "_tool_simulate_runtime_input_event"),
		{"type": "object", "properties": {"type": {"type": "string"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_simulate_runtime_input_event(params: Dictionary) -> Dictionary:
	var event_payload: Variant = params.get("event", null)
	if not (event_payload is Dictionary):
		return {"error": "Missing required parameter: event"}

	# Build match_fields from the event payload to distinguish press/release responses.
	# Without this, a stale cached response from a previous call could be returned.
	var match_fields: Dictionary = {}
	if event_payload.has("type"):
		match_fields["type"] = event_payload["type"]
	if event_payload.has("button_index"):
		match_fields["button_index"] = event_payload["button_index"]
	if event_payload.has("pressed"):
		match_fields["pressed"] = event_payload["pressed"]

	return await _request_runtime_probe_poll("simulate_input_event", [event_payload], ["mcp:input_event_simulated"], params, match_fields)

func _register_simulate_runtime_input_action(server_core: RefCounted) -> void:
	server_core.register_tool(
		"simulate_runtime_input_action",
		"Inject an InputEventAction into the running game through Input.parse_input_event(). runtime_pressed is only meaningful when the action exists in InputMap.",
		{
			"type": "object",
			"properties": {
				"action_name": {"type": "string"},
				"pressed": {"type": "boolean", "default": true},
				"strength": {"type": "number", "default": 1.0},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["action_name"]
		},
		Callable(self, "_tool_simulate_runtime_input_action"),
		{"type": "object", "properties": {"action_name": {"type": "string"}, "action_exists": {"type": "boolean"}, "pressed": {"type": "boolean"}, "strength": {"type": "number"}, "runtime_pressed": {"type": "boolean"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_simulate_runtime_input_action(params: Dictionary) -> Dictionary:
	var action_name: String = params.get("action_name", "")
	if action_name.is_empty():
		return {"error": "Missing required parameter: action_name"}
	var pressed: bool = bool(params.get("pressed", true))
	var strength: float = float(params.get("strength", 1.0 if pressed else 0.0))
	return await _request_runtime_probe_poll("simulate_input_action", [action_name, pressed, strength], ["mcp:input_action_simulated"], params, {"action_name": action_name})

func _register_list_runtime_input_actions(server_core: RefCounted) -> void:
	server_core.register_tool(
		"list_runtime_input_actions",
		"List InputMap actions available in the running game, including serialized input events.",
		{
			"type": "object",
			"properties": {
				"action_name": {"type": "string", "description": "Optional exact action name filter."},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			}
		},
		Callable(self, "_tool_list_runtime_input_actions"),
		{"type": "object", "properties": {"actions": {"type": "array"}, "count": {"type": "integer"}, "filter": {"type": "string"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_list_runtime_input_actions(params: Dictionary) -> Dictionary:
	var action_name: String = params.get("action_name", "")
	return await _request_runtime_probe_poll("list_input_actions", [action_name], ["mcp:input_actions"], params, {"filter": action_name})

func _register_upsert_runtime_input_action(server_core: RefCounted) -> void:
	server_core.register_tool(
		"upsert_runtime_input_action",
		"Create or update an InputMap action in the running game. Supports replacing existing events.",
		{
			"type": "object",
			"properties": {
				"action_name": {"type": "string"},
				"deadzone": {"type": "number", "default": 0.5},
				"erase_existing": {"type": "boolean", "default": false},
				"events": {"type": "array", "items": {"type": "object"}, "description": "Optional structured input event payloads to add to the action."},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["action_name"]
		},
		Callable(self, "_tool_upsert_runtime_input_action"),
		{"type": "object", "properties": {"action_name": {"type": "string"}, "existed_before": {"type": "boolean"}, "deadzone": {"type": "number"}, "event_count": {"type": "integer"}, "events": {"type": "array", "items": {"type": "object"}}, "added_events": {"type": "array", "items": {"type": "object"}}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_upsert_runtime_input_action(params: Dictionary) -> Dictionary:
	var action_name: String = params.get("action_name", "")
	if action_name.is_empty():
		return {"error": "Missing required parameter: action_name"}
	var deadzone: float = float(params.get("deadzone", 0.5))
	var erase_existing: bool = bool(params.get("erase_existing", false))
	var events: Array = params.get("events", [])
	return await _request_runtime_probe_poll("upsert_input_action", [action_name, deadzone, erase_existing, events], ["mcp:input_action_updated"], params, {"action_name": action_name})

func _register_remove_runtime_input_action(server_core: RefCounted) -> void:
	server_core.register_tool(
		"remove_runtime_input_action",
		"Remove an InputMap action from the running game.",
		{
			"type": "object",
			"properties": {
				"action_name": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["action_name"]
		},
		Callable(self, "_tool_remove_runtime_input_action"),
		{"type": "object", "properties": {"action_name": {"type": "string"}, "removed": {"type": "boolean"}, "event_count": {"type": "integer"}}},
		{"readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_remove_runtime_input_action(params: Dictionary) -> Dictionary:
	var action_name: String = params.get("action_name", "")
	if action_name.is_empty():
		return {"error": "Missing required parameter: action_name"}
	return await _request_runtime_probe_poll("remove_input_action", [action_name], ["mcp:input_action_removed"], params, {"action_name": action_name})

func _register_list_runtime_animations(server_core: RefCounted) -> void:
	server_core.register_tool(
		"list_runtime_animations",
		"List animations available on a runtime AnimationPlayer node.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_list_runtime_animations"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "animations": {"type": "array"}, "count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_list_runtime_animations(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("list_animations", [node_path], ["mcp:animation_list"], params, {"node_path": node_path})

func _register_play_runtime_animation(server_core: RefCounted) -> void:
	server_core.register_tool(
		"play_runtime_animation",
		"Play an animation on a runtime AnimationPlayer node.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"animation_name": {"type": "string"},
				"custom_blend": {"type": "number", "default": -1.0},
				"custom_speed": {"type": "number", "default": 1.0},
				"from_end": {"type": "boolean", "default": false},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "animation_name"]
		},
		Callable(self, "_tool_play_runtime_animation"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "current_animation": {"type": "string"}, "is_playing": {"type": "boolean"}, "current_position": {"type": "number"}, "current_length": {"type": "number"}, "speed_scale": {"type": "number"}, "playing_speed": {"type": "number"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_play_runtime_animation(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var animation_name: String = params.get("animation_name", "")
	if node_path.is_empty() or animation_name.is_empty():
		return {"error": "node_path and animation_name are required"}
	return await _request_runtime_probe_poll("play_animation", [node_path, animation_name, float(params.get("custom_blend", -1.0)), float(params.get("custom_speed", 1.0)), bool(params.get("from_end", false))], ["mcp:animation_started"], params, {"node_path": node_path, "current_animation": animation_name})

func _register_stop_runtime_animation(server_core: RefCounted) -> void:
	server_core.register_tool(
		"stop_runtime_animation",
		"Stop playback on a runtime AnimationPlayer node.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"keep_state": {"type": "boolean", "default": false},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_stop_runtime_animation"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "current_animation": {"type": "string"}, "is_playing": {"type": "boolean"}, "current_position": {"type": "number"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_stop_runtime_animation(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("stop_animation", [node_path, bool(params.get("keep_state", false))], ["mcp:animation_stopped"], params, {"node_path": node_path})

func _register_get_runtime_animation_state(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_animation_state",
		"Return the current playback state of a runtime AnimationPlayer node.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_get_runtime_animation_state"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "current_animation": {"type": "string"}, "is_playing": {"type": "boolean"}, "current_position": {"type": "number"}, "current_length": {"type": "number"}, "speed_scale": {"type": "number"}, "playing_speed": {"type": "number"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_animation_state(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("get_animation_state", [node_path], ["mcp:animation_state"], params, {"node_path": node_path})

func _register_get_runtime_animation_tree_state(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_animation_tree_state",
		"Return the current state of a runtime AnimationTree node, including playback metadata when available.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_get_runtime_animation_tree_state"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "active": {"type": "boolean"}, "anim_player": {"type": "string"}, "tree_root_type": {"type": "string"}, "has_playback": {"type": "boolean"}, "current_node": {"type": "string"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_animation_tree_state(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("get_animation_tree_state", [node_path], ["mcp:animation_tree_state"], params, {"node_path": node_path})

func _register_set_runtime_animation_tree_active(server_core: RefCounted) -> void:
	server_core.register_tool(
		"set_runtime_animation_tree_active",
		"Enable or disable a runtime AnimationTree node.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"active": {"type": "boolean"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "active"]
		},
		Callable(self, "_tool_set_runtime_animation_tree_active"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "active": {"type": "boolean"}, "tree_root_type": {"type": "string"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_set_runtime_animation_tree_active(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	if not params.has("active"):
		return {"error": "Missing required parameter: active"}
	return await _request_runtime_probe_poll("set_animation_tree_active", [node_path, bool(params.get("active"))], ["mcp:animation_tree_active_updated"], params, {"node_path": node_path})

func _register_travel_runtime_animation_tree(server_core: RefCounted) -> void:
	server_core.register_tool(
		"travel_runtime_animation_tree",
		"Travel a runtime AnimationTree state machine playback to a target node.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"state_name": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "state_name"]
		},
		Callable(self, "_tool_travel_runtime_animation_tree"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "current_node": {"type": "string"}, "travel_path": {"type": "array"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_travel_runtime_animation_tree(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var state_name: String = params.get("state_name", "")
	if node_path.is_empty() or state_name.is_empty():
		return {"error": "node_path and state_name are required"}
	return await _request_runtime_probe_poll("travel_animation_tree", [node_path, state_name], ["mcp:animation_tree_travelled"], params, {"node_path": node_path})

func _register_get_runtime_material_state(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_material_state",
		"Resolve a runtime node material binding and return material metadata.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"material_target": {"type": "string", "enum": ["auto", "material", "material_override", "surface_override"], "default": "auto"},
				"surface_index": {"type": "integer", "default": 0},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_get_runtime_material_state"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "material_class": {"type": "string"}, "material_target": {"type": "string"}, "is_shader_material": {"type": "boolean"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_material_state(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("get_material_state", [node_path, str(params.get("material_target", "auto")), int(params.get("surface_index", 0))], ["mcp:material_state"], params, {"node_path": node_path})

func _register_get_runtime_theme_item(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_theme_item",
		"Resolve one runtime Control theme item and report its current value and override status.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"item_type": {"type": "string", "enum": ["color", "constant", "font", "font_size", "stylebox", "icon"]},
				"item_name": {"type": "string"},
				"theme_type": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "item_type", "item_name"]
		},
		Callable(self, "_tool_get_runtime_theme_item"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "item_type": {"type": "string"}, "item_name": {"type": "string"}, "has_override": {"type": "boolean"}, "has_item": {"type": "boolean"}, "value": {}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_theme_item(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var item_type: String = params.get("item_type", "")
	var item_name: String = params.get("item_name", "")
	if node_path.is_empty() or item_type.is_empty() or item_name.is_empty():
		return {"error": "node_path, item_type, and item_name are required"}
	return await _request_runtime_probe_poll("get_theme_item", [node_path, item_type, item_name, str(params.get("theme_type", ""))], ["mcp:theme_item"], params, {"node_path": node_path, "item_type": item_type, "item_name": item_name})

func _register_set_runtime_theme_override(server_core: RefCounted) -> void:
	server_core.register_tool(
		"set_runtime_theme_override",
		"Apply one runtime Control theme override for a color, constant, font, font_size, stylebox, or icon item.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"item_type": {"type": "string", "enum": ["color", "constant", "font", "font_size", "stylebox", "icon"]},
				"item_name": {"type": "string"},
				"value": {},
				"theme_type": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "item_type", "item_name", "value"]
		},
		Callable(self, "_tool_set_runtime_theme_override"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "item_type": {"type": "string"}, "item_name": {"type": "string"}, "has_override": {"type": "boolean"}, "value": {}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_set_runtime_theme_override(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var item_type: String = params.get("item_type", "")
	var item_name: String = params.get("item_name", "")
	if node_path.is_empty() or item_type.is_empty() or item_name.is_empty() or not params.has("value"):
		return {"error": "node_path, item_type, item_name, and value are required"}
	return await _request_runtime_probe_poll("set_theme_override", [node_path, item_type, item_name, params.get("value"), str(params.get("theme_type", ""))], ["mcp:theme_override_updated"], params, {"node_path": node_path, "item_type": item_type, "item_name": item_name})

func _register_clear_runtime_theme_override(server_core: RefCounted) -> void:
	server_core.register_tool(
		"clear_runtime_theme_override",
		"Remove one runtime Control theme override and return the resolved post-clear value.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"item_type": {"type": "string", "enum": ["color", "constant", "font", "font_size", "stylebox", "icon"]},
				"item_name": {"type": "string"},
				"theme_type": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "item_type", "item_name"]
		},
		Callable(self, "_tool_clear_runtime_theme_override"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "item_type": {"type": "string"}, "item_name": {"type": "string"}, "has_override": {"type": "boolean"}, "value": {}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_clear_runtime_theme_override(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var item_type: String = params.get("item_type", "")
	var item_name: String = params.get("item_name", "")
	if node_path.is_empty() or item_type.is_empty() or item_name.is_empty():
		return {"error": "node_path, item_type, and item_name are required"}
	return await _request_runtime_probe_poll("clear_theme_override", [node_path, item_type, item_name, str(params.get("theme_type", ""))], ["mcp:theme_override_cleared"], params, {"node_path": node_path, "item_type": item_type, "item_name": item_name})

func _register_get_runtime_shader_parameters(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_shader_parameters",
		"List shader uniforms and current values from a runtime ShaderMaterial binding.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"material_target": {"type": "string", "enum": ["auto", "material", "material_override", "surface_override"], "default": "auto"},
				"surface_index": {"type": "integer", "default": 0},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_get_runtime_shader_parameters"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "parameters": {"type": "array"}, "count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_shader_parameters(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("get_shader_parameters", [node_path, str(params.get("material_target", "auto")), int(params.get("surface_index", 0))], ["mcp:shader_parameters"], params, {"node_path": node_path})

func _register_set_runtime_shader_parameter(server_core: RefCounted) -> void:
	server_core.register_tool(
		"set_runtime_shader_parameter",
		"Update one shader uniform on a runtime ShaderMaterial binding.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"parameter_name": {"type": "string"},
				"value": {},
				"material_target": {"type": "string", "enum": ["auto", "material", "material_override", "surface_override"], "default": "auto"},
				"surface_index": {"type": "integer", "default": 0},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "parameter_name", "value"]
		},
		Callable(self, "_tool_set_runtime_shader_parameter"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "parameter_name": {"type": "string"}, "old_value": {}, "new_value": {}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_set_runtime_shader_parameter(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var parameter_name: String = params.get("parameter_name", "")
	if node_path.is_empty() or parameter_name.is_empty() or not params.has("value"):
		return {"error": "node_path, parameter_name, and value are required"}
	return await _request_runtime_probe_poll("set_shader_parameter", [node_path, parameter_name, params.get("value"), str(params.get("material_target", "auto")), int(params.get("surface_index", 0))], ["mcp:shader_parameter_updated"], params, {"node_path": node_path, "parameter_name": parameter_name})

func _register_list_runtime_tilemap_layers(server_core: RefCounted) -> void:
	server_core.register_tool(
		"list_runtime_tilemap_layers",
		"List the layers and used-cell counts of a runtime TileMap node.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path"]
		},
		Callable(self, "_tool_list_runtime_tilemap_layers"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "layers": {"type": "array"}, "count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_list_runtime_tilemap_layers(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	return await _request_runtime_probe_poll("list_tilemap_layers", [node_path], ["mcp:tilemap_layers"], params, {"node_path": node_path})

func _register_get_runtime_tilemap_cell(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_tilemap_cell",
		"Return the runtime cell data at one TileMap layer coordinate.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"layer": {"type": "integer"},
				"coords": {"type": "object", "properties": {"x": {"type": "integer"}, "y": {"type": "integer"}}, "required": ["x", "y"]},
				"use_proxies": {"type": "boolean", "default": false},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "layer", "coords"]
		},
		Callable(self, "_tool_get_runtime_tilemap_cell"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "layer": {"type": "integer"}, "coords": {"type": "object"}, "source_id": {"type": "integer"}, "atlas_coords": {"type": "object"}, "alternative_tile": {"type": "integer"}, "is_empty": {"type": "boolean"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_tilemap_cell(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	if not params.has("coords"):
		return {"error": "Missing required parameter: coords"}
	return await _request_runtime_probe_poll("get_tilemap_cell", [node_path, int(params.get("layer", 0)), params.get("coords", {}), bool(params.get("use_proxies", false))], ["mcp:tilemap_cell"], params, {"node_path": node_path, "layer": int(params.get("layer", 0))})

func _register_set_runtime_tilemap_cell(server_core: RefCounted) -> void:
	server_core.register_tool(
		"set_runtime_tilemap_cell",
		"Write or erase a single runtime TileMap cell at one layer coordinate.",
		{
			"type": "object",
			"properties": {
				"node_path": {"type": "string"},
				"layer": {"type": "integer"},
				"coords": {"type": "object", "properties": {"x": {"type": "integer"}, "y": {"type": "integer"}}, "required": ["x", "y"]},
				"source_id": {"type": "integer"},
				"atlas_coords": {"type": "object", "properties": {"x": {"type": "integer"}, "y": {"type": "integer"}}},
				"alternative_tile": {"type": "integer", "default": 0},
				"erase": {"type": "boolean", "default": false},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["node_path", "layer", "coords"]
		},
		Callable(self, "_tool_set_runtime_tilemap_cell"),
		{"type": "object", "properties": {"node_path": {"type": "string"}, "layer": {"type": "integer"}, "coords": {"type": "object"}, "source_id": {"type": "integer"}, "atlas_coords": {"type": "object"}, "alternative_tile": {"type": "integer"}, "is_empty": {"type": "boolean"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_set_runtime_tilemap_cell(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path.is_empty():
		return {"error": "Missing required parameter: node_path"}
	if not params.has("coords"):
		return {"error": "Missing required parameter: coords"}
	var updates: Dictionary = {"erase": bool(params.get("erase", false))}
	if params.has("source_id"):
		updates["source_id"] = int(params.get("source_id"))
	if params.has("atlas_coords"):
		updates["atlas_coords"] = params.get("atlas_coords")
	if params.has("alternative_tile"):
		updates["alternative_tile"] = int(params.get("alternative_tile"))
	return await _request_runtime_probe_poll("set_tilemap_cell", [node_path, int(params.get("layer", 0)), params.get("coords", {}), updates], ["mcp:tilemap_cell_updated"], params, {"node_path": node_path, "layer": int(params.get("layer", 0))})

func _register_list_runtime_audio_buses(server_core: RefCounted) -> void:
	server_core.register_tool(
		"list_runtime_audio_buses",
		"List AudioServer buses available in the running game.",
		{
			"type": "object",
			"properties": {
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			}
		},
		Callable(self, "_tool_list_runtime_audio_buses"),
		{"type": "object", "properties": {"buses": {"type": "array"}, "count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_list_runtime_audio_buses(params: Dictionary) -> Dictionary:
	return await _request_runtime_probe_poll("list_audio_buses", [], ["mcp:audio_buses"], params)

func _register_get_runtime_audio_bus(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_audio_bus",
		"Return the current state of one AudioServer bus in the running game.",
		{
			"type": "object",
			"properties": {
				"bus_name": {"type": "string"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["bus_name"]
		},
		Callable(self, "_tool_get_runtime_audio_bus"),
		{"type": "object", "properties": {"index": {"type": "integer"}, "name": {"type": "string"}, "volume_db": {"type": "number"}, "mute": {"type": "boolean"}, "solo": {"type": "boolean"}, "bypass_effects": {"type": "boolean"}, "send": {"type": "string"}, "effect_count": {"type": "integer"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_audio_bus(params: Dictionary) -> Dictionary:
	var bus_name: String = params.get("bus_name", "")
	if bus_name.is_empty():
		return {"error": "Missing required parameter: bus_name"}
	return await _request_runtime_probe_poll("get_audio_bus", [bus_name], ["mcp:audio_bus"], params, {"name": bus_name})

func _register_update_runtime_audio_bus(server_core: RefCounted) -> void:
	server_core.register_tool(
		"update_runtime_audio_bus",
		"Update mute and/or volume_db on an AudioServer bus in the running game.",
		{
			"type": "object",
			"properties": {
				"bus_name": {"type": "string"},
				"volume_db": {"type": "number"},
				"mute": {"type": "boolean"},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			},
			"required": ["bus_name"]
		},
		Callable(self, "_tool_update_runtime_audio_bus"),
		{"type": "object", "properties": {"index": {"type": "integer"}, "name": {"type": "string"}, "volume_db": {"type": "number"}, "mute": {"type": "boolean"}, "solo": {"type": "boolean"}, "bypass_effects": {"type": "boolean"}, "send": {"type": "string"}, "effect_count": {"type": "integer"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_update_runtime_audio_bus(params: Dictionary) -> Dictionary:
	var bus_name: String = params.get("bus_name", "")
	if bus_name.is_empty():
		return {"error": "Missing required parameter: bus_name"}
	var updates: Dictionary = {}
	if params.has("volume_db"):
		updates["volume_db"] = float(params.get("volume_db"))
	if params.has("mute"):
		updates["mute"] = bool(params.get("mute"))
	return await _request_runtime_probe_poll("update_audio_bus", [bus_name, updates], ["mcp:audio_bus_updated"], params, {"name": bus_name})

func _register_get_runtime_screenshot(server_core: RefCounted) -> void:
	server_core.register_tool(
		"get_runtime_screenshot",
		"Capture the current runtime viewport, or a specific runtime Viewport/SubViewport node, from the running game and save it to a file.",
		{
			"type": "object",
			"properties": {
				"save_path": {"type": "string", "description": "Output path for the screenshot. Must use res:// or user://."},
				"format": {"type": "string", "enum": ["png", "jpg"], "default": "jpg"},
				"viewport_path": {"type": "string", "description": "Optional runtime node path to a Viewport or SubViewport to capture instead of the active root viewport."},
				"session_id": {"type": "integer"},
				"timeout_ms": {"type": "integer", "default": 1500}
			}
		},
		Callable(self, "_tool_get_runtime_screenshot"),
		{"type": "object", "properties": {"save_path": {"type": "string"}, "format": {"type": "string"}, "viewport_path": {"type": "string"}, "width": {"type": "integer"}, "height": {"type": "integer"}, "size": {"type": "string"}, "current_scene": {"type": "string"}}},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_get_runtime_screenshot(params: Dictionary) -> Dictionary:
	var save_path: String = params.get("save_path", "user://mcp_runtime_capture.jpg")
	var path_validation: Dictionary = PathValidator.validate_file_path(save_path, [".png", ".jpg", ".jpeg"])
	if not path_validation.get("valid", false):
		return {"error": "Invalid save path: " + str(path_validation.get("error", "unknown error"))}
	save_path = path_validation["sanitized"]

	var format: String = String(params.get("format", "jpg")).to_lower()
	if not ["png", "jpg"].has(format):
		return {"error": "Unsupported format: " + format}
	if format == "png" and not save_path.to_lower().ends_with(".png"):
		return {"error": "save_path must end with .png when format is png"}
	if format == "jpg" and not (save_path.to_lower().ends_with(".jpg") or save_path.to_lower().ends_with(".jpeg")):
		return {"error": "save_path must end with .jpg or .jpeg when format is jpg"}

	var viewport_path: String = str(params.get("viewport_path", "")).strip_edges()
	var match_fields: Dictionary = {"save_path": save_path}
	if not viewport_path.is_empty():
		match_fields["viewport_path"] = viewport_path
	return await _request_runtime_probe_poll("get_runtime_screenshot", [save_path, format, viewport_path], ["mcp:runtime_screenshot"], params, match_fields)

func _register_await_runtime_condition(server_core: RefCounted) -> void:
	server_core.register_tool(
		"await_runtime_condition",
		"Poll a runtime expression until it becomes truthy or the timeout expires.",
		{
			"type": "object",
			"properties": {
				"expression": {"type": "string"},
				"node_path": {"type": "string"},
				"timeout_ms": {"type": "integer", "default": 3000},
				"poll_interval_ms": {"type": "integer", "default": 100},
				"session_id": {"type": "integer"}
			},
			"required": ["expression"]
		},
		Callable(self, "_tool_await_runtime_condition"),
		{"type": "object", "properties": {"condition_met": {"type": "boolean"}, "attempts": {"type": "integer"}, "elapsed_ms": {"type": "integer"}, "last_value": {}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_await_runtime_condition(params: Dictionary) -> Dictionary:
	var expression: String = params.get("expression", "")
	if expression.is_empty():
		return {"error": "Missing required parameter: expression"}
	
	var timeout_ms: int = maxi(int(params.get("timeout_ms", 10000)), 100)
	var poll_interval_ms: int = maxi(int(params.get("poll_interval_ms", 500)), 50)
	var deadline_ms: int = Time.get_ticks_msec() + timeout_ms
	var attempts: int = 0
	
	while Time.get_ticks_msec() < deadline_ms:
		attempts += 1
		var result: Dictionary = await _tool_evaluate_runtime_expression(params)
		if result.has("error"):
			return result
		if result.get("status", "") == "success":
			var last_value: Variant = result.get("value", null)
			var condition_met: bool = _is_truthy_runtime_value(last_value)
			return {
				"status": "success" if condition_met else "failed",
				"condition_met": condition_met,
				"last_value": last_value,
				"refresh_result": result.get("refresh_result", {}),
				"attempts": attempts,
				"elapsed_ms": timeout_ms - (deadline_ms - Time.get_ticks_msec())
			}
		# If still pending or failed, wait before retrying
		if Time.get_ticks_msec() + poll_interval_ms < deadline_ms:
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			if tree:
				await tree.process_frame
			else:
				OS.delay_msec(poll_interval_ms)
	
	# Timeout reached
	var last_result: Dictionary = await _tool_evaluate_runtime_expression(params)
	var last_value: Variant = last_result.get("value", null) if not last_result.has("error") else null
	return {
		"status": "failed",
		"condition_met": false,
		"last_value": last_value,
		"error": "Timeout waiting for runtime condition: " + expression,
		"attempts": attempts,
		"elapsed_ms": timeout_ms
	}

func _register_assert_runtime_condition(server_core: RefCounted) -> void:
	server_core.register_tool(
		"assert_runtime_condition",
		"Assert that a runtime expression becomes truthy within the timeout window, or matches an expected value when provided.",
		{
			"type": "object",
			"properties": {
				"expression": {"type": "string"},
				"node_path": {"type": "string"},
				"timeout_ms": {"type": "integer", "default": 3000},
				"poll_interval_ms": {"type": "integer", "default": 100},
				"session_id": {"type": "integer"},
				"description": {"type": "string"},
				"expected": {"type": "string", "description": "Expected value to compare against. If provided, asserts expression == expected instead of truthiness."},
				"operator": {"type": "string", "description": "Comparison operator: 'eq' (default), 'ne', 'gt', 'gte', 'lt', 'lte'. Only used when expected is provided.", "default": "eq", "enum": ["eq", "ne", "gt", "gte", "lt", "lte"]}
			},
			"required": ["expression"]
		},
		Callable(self, "_tool_assert_runtime_condition"),
		{"type": "object", "properties": {"status": {"type": "string"}, "description": {"type": "string"}, "attempts": {"type": "integer"}, "elapsed_ms": {"type": "integer"}, "last_value": {}, "passed": {"type": "boolean"}, "expected": {"type": "string"}, "actual": {"type": "string"}}},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": true},
		"supplementary", "Debug-Advanced"
	)

func _tool_assert_runtime_condition(params: Dictionary) -> Dictionary:
	var wait_result: Dictionary = await _tool_await_runtime_condition(params)
	if wait_result.has("error"):
		return wait_result

	var last_value = wait_result.get("last_value", null)
	var expected_raw = params.get("expected", null)
	var attempts: int = wait_result.get("attempts", 0)
	var elapsed_ms: int = wait_result.get("elapsed_ms", 0)

	# If expected is provided, compare using operator instead of truthiness
	if expected_raw != null:
		var operator: String = params.get("operator", "eq")
		var expected_str: String = str(expected_raw)
		var actual_str: String = str(last_value) if last_value != null else "null"
		var passed: bool = _compare_values(actual_str, expected_str, operator)

		return {
			"status": "passed" if passed else "failed",
			"description": params.get("description", params.get("expression", "")),
			"passed": passed,
			"expected": expected_str,
			"actual": actual_str,
			"last_value": last_value,
			"attempts": attempts,
			"elapsed_ms": elapsed_ms
		}

	# Original truthy behavior (no expected parameter)
	if wait_result.get("status", "") == "pending":
		return {
			"status": "pending",
			"description": params.get("description", params.get("expression", "")),
			"last_value": null,
			"refresh_result": wait_result.get("refresh_result", {})
		}
	if not wait_result.get("condition_met", false):
		return {
			"error": "Runtime condition was not met within timeout",
			"description": params.get("description", params.get("expression", "")),
			"last_value": wait_result.get("last_value", null)
		}
	return {
		"status": "success",
		"description": params.get("description", params.get("expression", "")),
		"last_value": wait_result.get("last_value", null),
		"refresh_result": wait_result.get("refresh_result", {})
	}

func _compare_values(actual: String, expected: String, operator: String) -> bool:
	match operator:
		"eq":
			return actual == expected
		"ne":
			return actual != expected
		"gt":
			return float(actual) > float(expected)
		"gte":
			return float(actual) >= float(expected)
		"lt":
			return float(actual) < float(expected)
		"lte":
			return float(actual) <= float(expected)
	return false

func _request_runtime_probe(command: String, payload: Array, response_messages: Array, params: Dictionary, match_fields: Dictionary = {}) -> Dictionary:
	var bridge: RefCounted = _get_debugger_bridge()
	if not bridge:
		return {"error": "Debugger bridge is not available"}
	var session_id: int = int(params.get("session_id", -1))
	var timeout_ms: int = maxi(int(params.get("timeout_ms", 3000)), 1)
	var request_key: String = _make_runtime_probe_request_key(command, payload, session_id, response_messages, match_fields)
	var now_ms: int = Time.get_ticks_msec()
	var pending_entry: Dictionary = _pending_runtime_probe_requests.get(request_key, {})

	if pending_entry.is_empty() or now_ms > int(pending_entry.get("expires_at_ms", 0)):
		if not pending_entry.is_empty():
			_pending_runtime_probe_requests.erase(request_key)
		var baseline_sequence: int = bridge.get_message_sequence() if bridge.has_method("get_message_sequence") else 0
		var refresh_result: Dictionary = bridge.send_debugger_message("mcp:" + command, payload, session_id)
		if refresh_result.has("error"):
			return refresh_result
		if refresh_result.get("status", "") == "no_active_sessions":
			return {"status": "no_active_sessions", "refresh_result": refresh_result}
		pending_entry = {
			"baseline_sequence": baseline_sequence,
			"refresh_result": refresh_result,
			"expires_at_ms": now_ms + timeout_ms
		}
		_pending_runtime_probe_requests[request_key] = pending_entry

	var response: Dictionary = _extract_pending_runtime_probe_response(bridge, pending_entry, response_messages, match_fields)
	if not response.is_empty():
		_pending_runtime_probe_requests.erase(request_key)
		response["refresh_result"] = pending_entry.get("refresh_result", {})
		return response

	return {
		"status": "pending",
		"refresh_result": pending_entry.get("refresh_result", {}),
		"response_messages": response_messages
	}

func _make_runtime_probe_request_key(command: String, payload: Array, session_id: int, response_messages: Array, match_fields: Dictionary) -> String:
	# Use str() concatenation instead of JSON.stringify for lower overhead per call.
	# Include payload only when non-empty to differentiate calls with different
	# arguments (e.g. evaluate_expression with different expressions).
	# Empty payloads (common case) are omitted to keep the key shorter/faster.
	var key: String = command + "|" + str(session_id) + "|" + str(response_messages)
	if not payload.is_empty():
		key += "|" + str(payload)
	if not match_fields.is_empty():
		key += "|" + str(match_fields)
	return key

func _extract_pending_runtime_probe_response(bridge: RefCounted, pending_entry: Dictionary, response_messages: Array, match_fields: Dictionary) -> Dictionary:
	# Force the debugger bridge to refresh captured message visibility before querying
	# for the latest runtime payload. Without this, headless editor sessions can leave
	# freshly received custom EngineDebugger captures invisible until another bridge read.
	bridge.get_captured_messages(1, 0, "desc")

	var response_entry: Dictionary = {}
	if bridge.has_method("get_captured_message_after_sequence"):
		response_entry = bridge.get_captured_message_after_sequence(
			int(pending_entry.get("baseline_sequence", 0)),
			response_messages,
			["mcp:error"],
			match_fields
		)

	if not response_entry.is_empty():
		var message_name: String = str(response_entry.get("message", ""))
		var captured_data: Array = response_entry.get("data", [])
		var runtime_payload: Variant = captured_data[0] if not captured_data.is_empty() else null
		if message_name == "mcp:error":
			return {"error": str(runtime_payload.get("message", runtime_payload)) if runtime_payload is Dictionary else str(runtime_payload)}
		if runtime_payload is Dictionary:
			var response: Dictionary = runtime_payload.duplicate(true)
			response["status"] = "success"
			return response
		if runtime_payload != null:
			return {"status": "success", "value": runtime_payload}

	# No fresh response yet. Return pending so the poll loop keeps waiting for the
	# newly-sent probe response. The eager stale fallback that lived here caused
	# repeated identical expressions to return "stale" immediately, which the poll
	# loop treated as retryable, burning the full timeout window on every call.
	# Stale fallback now happens only after the poll loop times out.
	return {}

func _request_runtime_probe_poll(
	command: String, payload: Array, response_messages: Array,
	params: Dictionary, match_fields: Dictionary = {}
) -> Dictionary:
	# Wait for the runtime probe to signal readiness before sending requests.
	# This avoids the race where a request arrives before the probe has
	# registered its EngineDebugger message capture in the game process.
	var bridge: RefCounted = _get_debugger_bridge()
	if bridge and bridge.has_method("wait_for_probe_ready"):
		var probe_session_id: int = int(params.get("session_id", -1))
		# Fast path: skip await (and its coroutine overhead) when probe is already ready.
		# This saves ~1 frame (~16ms) per runtime tool call after the first.
		if bridge.has_method("is_probe_ready") and bridge.is_probe_ready(probe_session_id):
			pass  # Already ready — no await needed
		else:
			await bridge.wait_for_probe_ready(probe_session_id, 2000)
	# Wraps _request_runtime_probe with a poll loop that retries when pending.
	# Uses await get_tree().process_frame to let the editor main loop advance
	# so EngineDebugger IPC messages are dispatched to _capture().
	var result: Dictionary = _request_runtime_probe(command, payload, response_messages, params, match_fields)
	if result.get("status") in ["pending", "stale"]:
		var timeout_ms: int = maxi(int(params.get("timeout_ms", 3000)), 100)
		var deadline_ms: int = Time.get_ticks_msec() + timeout_ms
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		while Time.get_ticks_msec() < deadline_ms:
			if tree:
				await tree.process_frame
			else:
				OS.delay_msec(16)
			result = _request_runtime_probe(command, payload, response_messages, params, match_fields)
			if result.get("status") not in ["pending", "stale"]:
				break
	# Timeout expired without a fresh response. Fall back to the latest cached
	# payload matching the request (if any) so callers still get data rather than
	# an empty result. This is the only place stale data is served now.
	if result.get("status") in ["pending", "stale"]:
		for message_name in response_messages:
			var cached_payload: Variant = bridge.get_latest_message_payload(message_name, match_fields) if bridge else null
			if cached_payload is Dictionary:
				result = cached_payload.duplicate(true)
				result["status"] = "success"
				result["from_cache"] = true
				result["stale"] = true
				return result
			if cached_payload != null:
				return {"status": "success", "from_cache": true, "stale": true, "value": cached_payload}
		# No cached payload either - return the pending status as-is
		result["status"] = "timeout"
		return result
	return result

func _is_truthy_runtime_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		TYPE_STRING:
			return not String(value).is_empty()
		TYPE_ARRAY:
			return not value.is_empty()
		TYPE_DICTIONARY:
			return not value.is_empty()
		_:
			return true

func _get_mcp_logs(types: Array, count: int, offset: int, order: String) -> Dictionary:
	_log_mutex.lock()
	if _log_buffer.is_empty():
		_log_mutex.unlock()
		return {
			"logs": [],
			"count": 0,
			"total_available": 0,
			"source": "mcp"
		}

	var all_entries: Array = []
	for i in range(_log_buffer.size()):
		var line: String = _log_buffer[i]
		var log_type: String = "Info"
		var message: String = line
		if line.begins_with("[ERROR]"):
			log_type = "Error"
			message = line.substr(7).strip_edges()
		elif line.begins_with("[WARNING]"):
			log_type = "Warning"
			message = line.substr(9).strip_edges()
		elif line.begins_with("[INFO]"):
			log_type = "Info"
			message = line.substr(6).strip_edges()
		elif line.begins_with("[DEBUG]"):
			log_type = "Debug"
			message = line.substr(7).strip_edges()
		all_entries.append({"index": i, "type": log_type, "message": message})

	var total_available: int = all_entries.size()
	_log_mutex.unlock()

	var filtered: Array = all_entries
	if types.size() > 0:
		filtered = []
		for entry in all_entries:
			if types.has(entry["type"]):
				filtered.append(entry)

	if order == "desc":
		filtered.reverse()

	var start: int = mini(offset, filtered.size())
	var end: int = mini(start + count, filtered.size())
	var result_logs: Array = filtered.slice(start, end)

	return {
		"logs": result_logs,
		"count": result_logs.size(),
		"total_available": total_available,
		"source": "mcp"
	}

func _get_runtime_logs(types: Array, count: int, offset: int, order: String) -> Dictionary:
	var log_path: String = "user://logs/godot.log"
	if not FileAccess.file_exists(log_path):
		return {
			"logs": [],
			"count": 0,
			"total_available": 0,
			"source": "runtime",
			"note": "Runtime log file not found: " + log_path
		}

	var file: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	if not file:
		return {
			"logs": [],
			"count": 0,
			"total_available": 0,
			"source": "runtime",
			"note": "Runtime log file not available. Logs are only created after running the project."
		}

	var all_lines: Array = []
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.is_empty():
			all_lines.append(line)
	file.close()

	var total_available: int = all_lines.size()
	if total_available == 0:
		return {
			"logs": [],
			"count": 0,
			"total_available": 0,
			"source": "runtime"
		}

	var entries: Array = []
	if order == "desc":
		for i in range(total_available - 1, -1, -1):
			entries.append({"index": i, "type": "Info", "message": all_lines[i]})
	else:
		for i in range(total_available):
			entries.append({"index": i, "type": "Info", "message": all_lines[i]})

	var start: int = mini(offset, entries.size())
	var end: int = mini(start + count, entries.size())
	var result_logs: Array = entries.slice(start, end)

	return {
		"logs": result_logs,
		"count": result_logs.size(),
		"total_available": total_available,
		"source": "runtime"
	}

# ============================================================================
# execute_script - 执行脚本代码
# ============================================================================

func _register_execute_script(server_core: RefCounted) -> void:
	var tool_name: String = "execute_script"
	var description: String = "Execute a GDScript expression or statement. Uses Godot's Expression class for safe evaluation."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"code": {
				"type": "string",
				"description": "GDScript code to execute (expression or statement)"
			},
			"bind_objects": {
				"type": "object",
				"description": "Optional dictionary of objects to bind to the expression"
			}
		},
		"required": ["code"]
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"result": {"type": "string"},
			"error": {"type": "string"}
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
						  Callable(self, "_tool_execute_script"),
						  output_schema, annotations, "core", "Script")

func _tool_execute_script(params: Dictionary) -> Dictionary:
	var code: String = params.get("code", "")
	var bind_objects: Dictionary = params.get("bind_objects", {})
	
	if code.is_empty():
		return {"error": "Missing required parameter: code"}
	
	# Auto-detect multi-line code and delegate to execute_editor_script path.
	# Capture the last output item as "result" so the response format is
	# consistent with the single-line Expression path.
	if "\n" in code:
		var editor_result: Dictionary = _tool_execute_editor_script(params)
		if editor_result.has("output") and editor_result.get("output", []).size() > 0:
			var output: Array = editor_result["output"]
			editor_result["result"] = str(output[output.size() - 1])
		elif editor_result.get("status") == "success":
			editor_result["result"] = ""
		return editor_result
	
	var expression: Expression = Expression.new()

	var bind_names: PackedStringArray = []
	var bind_values: Array = []
	var singletons: Dictionary = {
		"OS": OS,
		"Engine": Engine,
		"ProjectSettings": ProjectSettings,
		"Input": Input,
		"Time": Time,
		"JSON": JSON,
		"ClassDB": ClassDB,
		"Performance": Performance,
		"ResourceLoader": ResourceLoader,
		"ResourceSaver": ResourceSaver,
		"EditorInterface": EditorInterface,
	}
	for singleton_name in singletons:
		bind_names.append(singleton_name)
		bind_values.append(singletons[singleton_name])

	if not bind_objects.is_empty():
		for key in bind_objects:
			bind_names.append(key)
			bind_values.append(bind_objects[key])

	var parse_error: Error = expression.parse(code, bind_names)

	if parse_error != OK:
		return {
			"status": "error",
			"error": "Parse failed: " + expression.get_error_text()
		}

	var base_instance: RefCounted = self
	_execution_mutex.lock()
	var result: Variant = expression.execute(bind_values, base_instance, true)
	_execution_mutex.unlock()
	
	if expression.has_execute_failed():
		return {
			"status": "error",
			"error": "Execution failed: " + expression.get_error_text()
		}
	
	return {
		"status": "success",
		"result": str(result)
	}

# ============================================================================
# get_performance_metrics - 获取性能指标
# ============================================================================

func _register_get_performance_metrics(server_core: RefCounted) -> void:
	var tool_name: String = "get_performance_metrics"
	var description: String = "Get performance metrics including FPS, memory usage, and object counts."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"fps": {"type": "number"},
			"object_count": {"type": "integer"},
			"resource_count": {"type": "integer"},
			"memory_usage_mb": {"type": "number"}
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
						  Callable(self, "_tool_get_performance_metrics"),
						  output_schema, annotations, "supplementary", "Debug-Advanced")

func _tool_get_performance_metrics(params: Dictionary) -> Dictionary:
	# 使用Performance单例获取性能指标
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var object_count: int = Performance.get_monitor(Performance.OBJECT_COUNT)
	var resource_count: int = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var memory_usage: int = Performance.get_monitor(Performance.MEMORY_STATIC)  # 静态内存
	
	# 转换为MB
	var memory_mb: float = memory_usage / 1024.0 / 1024.0
	
	return {
		"fps": fps,
		"object_count": object_count,
		"resource_count": resource_count,
		"memory_usage_mb": memory_mb
	}

# ============================================================================
# debug_print - 输出调试信息
# ============================================================================

func _register_debug_print(server_core: RefCounted) -> void:
	var tool_name: String = "debug_print"
	var description: String = "Print a debug message to the Godot output console."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"message": {
				"type": "string",
				"description": "Message to print"
			},
			"category": {
				"type": "string",
				"description": "Optional category tag for the message (e.g. 'MCP', 'AI', 'Debug')"
			}
		},
		"required": ["message"]
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"printed_message": {"type": "string"}
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
						  Callable(self, "_tool_debug_print"),
						  output_schema, annotations, "core", "Debug")

func _tool_debug_print(params: Dictionary) -> Dictionary:
	# 参数提取
	var message: String = params.get("message", "")
	var category: String = params.get("category", "")
	
	# 参数验证
	if message.is_empty():
		return {"error": "Missing required parameter: message"}
	
	# 构建打印消息
	var full_message: String
	if category.is_empty():
		full_message = "[MCP Debug] " + message
	else:
		full_message = "[" + category + "] " + message
	
	# 输出到Godot控制台
	printerr(full_message)
	
	return {
		"status": "success",
		"printed_message": full_message
	}

# ============================================================================
# execute_editor_script - 执行完整的编辑器脚本
# ============================================================================

func _register_execute_editor_script(server_core: RefCounted) -> void:
	var tool_name: String = "execute_editor_script"
	var description: String = "Execute a full GDScript in the editor context. Unlike execute_script which only evaluates expressions, this tool can run multi-line scripts with loops, conditionals, and await. Use _custom_print(value) to return output (standard print() goes to editor panel only, not the tool response)."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"code": {
				"type": "string",
				"description": "Full GDScript code to execute. Can contain multiple statements, loops, conditionals, and await. Use _custom_print(value) to send output back to the tool response (standard print() goes to editor panel only)."
			}
		},
		"required": ["code"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"success": {"type": "boolean"},
			"output": {"type": "array", "items": {"type": "string"}},
			"error": {"type": "string"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": true,
		"idempotentHint": false,
		"openWorldHint": true
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_execute_editor_script"),
						  output_schema, annotations, "core", "Editor")

func _tool_execute_editor_script(params: Dictionary) -> Dictionary:
	var code: String = params.get("code", "")
	if code.is_empty():
		return {"success": false, "error": "Missing required parameter: code", "output": []}

	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"success": false, "error": "Editor interface not available", "output": []}

	var normalized_code: String = _normalize_indentation(code)
	normalized_code = _spaces_to_tabs(normalized_code)

	var script: GDScript = GDScript.new()
	var class_level_lines: PackedStringArray = []
	var body_lines: PackedStringArray = []
	var in_block: bool = false
	var block_indent: int = -1
	for line in normalized_code.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			if in_block:
				class_level_lines.append(line)
			else:
				body_lines.append(line)
			continue
		var indent: int = _count_indent(line)
		if in_block:
			if indent > block_indent or (indent == block_indent and (stripped.begins_with("@") or stripped.begins_with("pass"))):
				class_level_lines.append(line)
				continue
			else:
				in_block = false
		if stripped.begins_with("func ") or stripped.begins_with("class ") or stripped.begins_with("enum "):
			in_block = true
			block_indent = indent
			class_level_lines.append(line)
		else:
			body_lines.append(line)

	var wrapped_code: String = "extends RefCounted\n\nvar _output: Array = []\nvar edited_scene: Node = null\n\nfunc _custom_print(msg, msg2 = null) -> void:\n\t_output.append(str(msg))\n\tif msg2 != null: _output.append(str(msg2))\n\nfunc get_tree() -> SceneTree:\n\tif edited_scene:\n\t\treturn edited_scene.get_tree()\n\treturn Engine.get_main_loop() as SceneTree\n\nfunc get_node(path) -> Node:\n\tif edited_scene:\n\t\treturn edited_scene.get_node_or_null(path)\n\treturn null\n\n"
	if not class_level_lines.is_empty():
		for line in class_level_lines:
			wrapped_code += line + "\n"
		wrapped_code += "\n"
	wrapped_code += "func execute() -> Array:\n"
	for line in body_lines:
		wrapped_code += "\t" + line + "\n"
	wrapped_code += "\n\treturn _output\n"

	script.set_source_code(wrapped_code)

	var reload_ok: Error = script.reload()
	if reload_ok != OK:
		return {"success": false, "error": "Script compilation failed. Check syntax.", "output": []}

	var instance: RefCounted = script.new()
	if not instance:
		return {"success": false, "error": "Failed to create script instance", "output": []}

	instance.set("_output", [])
	var edited_scene: Node = editor_interface.get_edited_scene_root()
	if edited_scene:
		instance.set("edited_scene", edited_scene)

	var result_output: Variant = instance.call("execute")

	var output: Array = []
	if result_output is Array:
		output = result_output
	elif result_output != null:
		output.append(str(result_output))

	var instance_output: Variant = instance.get("_output")
	if instance_output is Array:
		for item in instance_output:
			if not output.has(item):
				output.append(item)

	if instance is RefCounted:
		pass

	return {
		"success": true,
		"output": output
	}

func _count_indent(line: String) -> int:
	var count: int = 0
	for c in line:
		if c == "\t":
			count += 4
		elif c == " ":
			count += 1
		else:
			break
	return count

func _normalize_indentation(code: String) -> String:
	var lines: PackedStringArray = code.split("\n")
	var min_indent: int = 999999
	for line in lines:
		if line.strip_edges().is_empty():
			continue
		var indent: int = 0
		for c in line:
			if c == "\t":
				indent += 4
			elif c == " ":
				indent += 1
			else:
				break
		if indent < min_indent:
			min_indent = indent
	if min_indent == 0 or min_indent == 999999:
		return code
	var result_lines: PackedStringArray = []
	for line in lines:
		if line.strip_edges().is_empty():
			result_lines.append("")
			continue
		var removed: int = 0
		var new_line: String = ""
		for c in line:
			if removed >= min_indent:
				new_line += c
			elif c == "\t":
				removed += 4
				if removed > min_indent:
					new_line += " ".repeat(removed - min_indent)
			elif c == " ":
				removed += 1
			else:
				new_line += c
				removed = min_indent
		result_lines.append(new_line)
	return "\n".join(result_lines)

func _spaces_to_tabs(code: String) -> String:
	var lines: PackedStringArray = code.split("\n")
	var result_lines: PackedStringArray = []
	for line in lines:
		if line.is_empty():
			result_lines.append(line)
			continue
		var leading_spaces: int = 0
		for c in line:
			if c == " ":
				leading_spaces += 1
			else:
				break
		if leading_spaces == 0:
			result_lines.append(line)
			continue
		var tab_count: int = leading_spaces / 4
		var remaining_spaces: int = leading_spaces % 4
		var new_line: String = "\t".repeat(tab_count) + " ".repeat(remaining_spaces) + line.substr(leading_spaces)
		result_lines.append(new_line)
	return "\n".join(result_lines)

# ============================================================================
# clear_output - 清除输出面板和日志缓冲区
# ============================================================================

func _register_clear_output(server_core: RefCounted) -> void:
	var tool_name: String = "clear_output"
	var description: String = "Clear the editor output panel and MCP log buffer."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"clear_mcp_buffer": {
				"type": "boolean",
				"description": "Whether to clear the MCP log buffer. Default is true."
			},
			"clear_editor_panel": {
				"type": "boolean",
				"description": "Whether to clear the editor output panel. Default is true."
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"mcp_buffer_cleared": {"type": "boolean"},
			"editor_panel_cleared": {"type": "boolean"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": true,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
		Callable(self, "_tool_clear_output"),
		output_schema, annotations, "core", "Debug")

func _tool_clear_output(params: Dictionary) -> Dictionary:
	var clear_mcp_buffer: bool = params.get("clear_mcp_buffer", true)
	var clear_editor_panel: bool = params.get("clear_editor_panel", true)

	var mcp_cleared: bool = false
	var mcp_panel_cleared: bool = false
	var panel_cleared: bool = false

	if clear_mcp_buffer:
		_log_mutex.lock()
		_log_buffer.clear()
		_log_mutex.unlock()
		mcp_cleared = true
		mcp_panel_cleared = _clear_mcp_panel_log()

	if clear_editor_panel:
		var editor_interface: EditorInterface = _get_editor_interface()
		if editor_interface:
			var base_control: Control = editor_interface.get_base_control()
			if base_control:
				var log_panel: Node = base_control.find_child("*Output*", true, false)
				if log_panel:
					var rich_text: RichTextLabel = _find_rich_text_label(log_panel)
					if rich_text:
						rich_text.clear()
						panel_cleared = true

	return {
		"status": "success",
		"mcp_buffer_cleared": mcp_cleared,
		"mcp_panel_cleared": mcp_panel_cleared,
		"editor_panel_cleared": panel_cleared
	}

func _clear_mcp_panel_log() -> bool:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return false
	var main_screen: Control = editor_interface.get_editor_main_screen()
	if not main_screen:
		return false
	for child in main_screen.get_children():
		if child.get_script() and child.get_script().resource_path.find("mcp_panel_native") >= 0:
			var text_edit: TextEdit = child.find_child("*TextEdit*", true, false)
			if text_edit and not text_edit.editable:
				text_edit.text = ""
				return true
	return false

func _find_rich_text_label(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node as RichTextLabel
	for child in node.get_children():
		var result: RichTextLabel = _find_rich_text_label(child)
		if result:
			return result
	return null

func _find_tree_control(node: Node) -> Tree:
	if node is Tree:
		return node as Tree
	for child in node.get_children():
		var result: Tree = _find_tree_control(child)
		if result:
			return result
	return null

func _find_script_editor_debugger(base: Node) -> Node:
	var pending: Array[Node] = [base]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.get_class() == 'ScriptEditorDebugger':
			return node
		for child in node.get_children():
			pending.append(child)
	return null

func _get_editor_panel_logs(types: Array, count: int, offset: int, order: String) -> Dictionary:
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available", "source": "editor_panel"}
	var base_control: Control = editor_interface.get_base_control()
	if not base_control:
		return {"error": "Could not get base control", "source": "editor_panel"}
	var parsed_lines: Array[Dictionary] = []
	var output_panel: Node = base_control.find_child('*Output*', true, false)
	if output_panel:
		var rich_text: RichTextLabel = _find_rich_text_label(output_panel)
		if rich_text:
			var raw_text: String = rich_text.get_parsed_text() if rich_text.has_method('get_parsed_text') else rich_text.get_text()
			if not raw_text.is_empty():
				var text_lines: PackedStringArray = raw_text.split('\n')
				for j in text_lines.size():
					var text_line: String = text_lines[j].strip_edges()
					if text_line.is_empty(): continue
					parsed_lines.append({'index': parsed_lines.size(), 'message': text_line, 'type': _infer_log_type_from_line(text_line), 'panel': 'output'})
	var errors_panel: Node = base_control.find_child('*Errors*', true, false)
	if not errors_panel:
		errors_panel = base_control.find_child('*Error*', true, false)
	if not errors_panel:
		var script_debugger: Node = _find_script_editor_debugger(base_control)
		if script_debugger:
			errors_panel = script_debugger
	if errors_panel:
		var error_tree: Tree = _find_tree_control(errors_panel)
		if error_tree:
			var root_item: TreeItem = error_tree.get_root()
			if root_item:
				var item: TreeItem = root_item.get_first_child()
				while item:
					var error_text: String = ''
					for col in range(error_tree.get_columns()):
						var col_text: String = item.get_text(col)
						if not col_text.is_empty():
							if not error_text.is_empty(): error_text += ' | '
							error_text += col_text
					if not error_text.is_empty():
						parsed_lines.append({'index': parsed_lines.size(), 'message': error_text, 'type': 'Error', 'panel': 'script_errors'})
					item = item.get_next()
	# Fallback: try reading the editor log file directly when UI panels have no data
	if parsed_lines.is_empty():
		var editor_log_path: String = ""
		if OS.has_feature("windows"):
			var appdata: String = OS.get_environment("APPDATA")
			if not appdata.is_empty():
				editor_log_path = appdata.path_join("Godot").path_join("editor_log-4.6.stable.txt")
		elif OS.has_feature("linux"):
			var home: String = OS.get_environment("HOME")
			if not home.is_empty():
				editor_log_path = home.path_join(".local").path_join("share").path_join("godot").path_join("editor_log-4.6.stable.txt")
		elif OS.has_feature("macos"):
			var home: String = OS.get_environment("HOME")
			if not home.is_empty():
				editor_log_path = home.path_join("Library").path_join("Application Support").path_join("Godot").path_join("editor_log-4.6.stable.txt")
		if not editor_log_path.is_empty() and FileAccess.file_exists(editor_log_path):
			var file: FileAccess = FileAccess.open(editor_log_path, FileAccess.READ)
			if file:
				while not file.eof_reached():
					var log_line: String = file.get_line().strip_edges()
					if log_line.is_empty():
						continue
					parsed_lines.append({
						'index': parsed_lines.size(),
						'message': log_line,
						'type': _infer_log_type_from_line(log_line),
						'panel': 'editor_log_file'
					})
	if not types.is_empty():
		var filtered: Array[Dictionary] = []
		for entry in parsed_lines:
			if types.has(entry['type']): filtered.append(entry)
		parsed_lines = filtered
	var total_available: int = parsed_lines.size()
	if order == 'desc': parsed_lines.reverse()
	var start: int = mini(offset, parsed_lines.size())
	var end: int = mini(start + count, parsed_lines.size())
	var result_lines: Array[Dictionary] = []
	for i in range(start, end): result_lines.append(parsed_lines[i])
	return {"logs": result_lines, "count": result_lines.size(), "total_available": total_available, "source": "editor_panel"}
func _infer_log_type_from_line(line: String) -> String:
	if line.begins_with("ERROR:") or line.begins_with("SCRIPT ERROR:") or line.begins_with("PARSE ERROR:") or line.begins_with("ERROR at") or line.find("error") == 0:
		return "Error"
	if line.begins_with("WARNING:") or line.begins_with("WARN ") or line.find("warning") == 0:
		return "Warning"
	if line.begins_with("DEBUG:") or line.begins_with("DEBUG "):
		return "Debug"
	return "Info"
