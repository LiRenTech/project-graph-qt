extends "res://addons/godot_mcp/native_mcp/mcp_server_core_legacy.gd"

var _shared_tool_registry: ToolRegistry = null
var _shared_tool_executor: ToolExecutor = null

func _ensure_shared_tool_core() -> void:
	if _shared_tool_registry == null:
		_shared_tool_registry = ToolRegistry.new()
	if _shared_tool_executor == null:
		_shared_tool_executor = ToolExecutor.new(_shared_tool_registry)
		_shared_tool_executor.execution_started.connect(Callable(self, "_on_shared_execution_started"))
		_shared_tool_executor.execution_completed.connect(Callable(self, "_on_shared_execution_completed"))
		_shared_tool_executor.execution_failed.connect(Callable(self, "_on_shared_execution_failed"))

func _init_transport() -> bool:
	match _transport_type:
		TransportType.TRANSPORT_STDIO:
			_transport = McpStdioServer.new()
			if _transport.has_method("set_log_callback"):
				_transport.set_log_callback(_log_transport_message)
			_log_info("Initialized stdio transport")
		TransportType.TRANSPORT_HTTP:
			_transport = load("res://addons/godot_mcp/native_mcp/mcp_http_server.gd").new()
			_transport.set_port(_http_port)
			if _auth_manager:
				_transport.set_auth_manager(_auth_manager)
			if _transport.has_method("set_log_callback"):
				_transport.set_log_callback(_log_transport_message)
			_log_info("Initialized HTTP transport on port " + str(_http_port))
		_:
			_log_error("Unknown transport type: " + str(_transport_type))
			return false
	_transport.message_received.connect(func(message: Dictionary, context: Variant):
		_on_transport_message_received(message, context)
	)
	_transport.server_error.connect(_on_transport_error)
	_transport.server_started.connect(_on_transport_started)
	_transport.server_stopped.connect(_on_transport_stopped)
	_log_info("Transport layer initialized: " + str(_transport_type))
	return true

func register_tool(name: String, description: String,
		input_schema: Dictionary, callable: Callable,
		output_schema: Dictionary = {}, annotations: Dictionary = {},
		category: String = "core", group: String = "") -> void:
	super.register_tool(name, description, input_schema, callable, output_schema, annotations, category, group)
	_ensure_shared_tool_core()
	if _tools.has(name):
		_shared_tool_registry.register_tool(ToolDefinition.from_legacy(_tools[name]))

func unregister_tool(name: String) -> void:
	super.unregister_tool(name)
	_ensure_shared_tool_core()
	_shared_tool_registry.unregister_tool(name)

func set_tool_enabled(tool_name: String, enabled: bool) -> void:
	super.set_tool_enabled(tool_name, enabled)
	_sync_tool_policy(tool_name)

func set_group_enabled(group_name: String, enabled: bool) -> int:
	var changed_count: int = super.set_group_enabled(group_name, enabled)
	_refresh_shared_registry()
	return changed_count

func get_tool_registry() -> ToolRegistry:
	_ensure_shared_tool_core()
	if _shared_tool_registry.size() != _tools.size():
		_refresh_shared_registry()
	return _shared_tool_registry

func get_tool_executor() -> ToolExecutor:
	_ensure_shared_tool_core()
	return _shared_tool_executor

func _refresh_shared_registry() -> void:
	_ensure_shared_tool_core()
	_shared_tool_registry.clear()
	for tool_name in _tools:
		_shared_tool_registry.register_tool(ToolDefinition.from_legacy(_tools[tool_name]))

func _sync_tool_policy(tool_name: String) -> void:
	_ensure_shared_tool_core()
	if not _tools.has(tool_name):
		return
	_shared_tool_registry.register_tool(ToolDefinition.from_legacy(_tools[tool_name]))

func _handle_tool_call(message: Dictionary) -> Dictionary:
	var id: Variant = message.get("id")
	var params: Dictionary = message.get("params", {})
	var tool_name: String = params.get("name", "")
	var arguments: Dictionary = params.get("arguments", {})
	_ensure_shared_tool_core()
	_sync_tool_policy(tool_name)
	var context := ToolExecutionContext.new()
	context.caller = "mcp"
	context.request_id = str(id)
	context.apply_confirmed = true
	context.allow_open_world = true
	var result: ToolExecutionResult = await _shared_tool_executor.execute(tool_name, arguments, context)
	var response_result: Dictionary = {
		"content": [{
			"type": "text",
			"text": JSON.stringify(result.data) if result.ok else result.error_message,
		}],
		"isError": not result.ok,
	}
	var definition: ToolDefinition = _shared_tool_registry.get_tool(tool_name)
	if result.ok and definition != null and not definition.output_schema.is_empty():
		response_result["structuredContent"] = result.data
	return MCPTypes.create_response(id, response_result)

func _on_shared_execution_started(tool_name: String, arguments: Dictionary) -> void:
	tool_execution_started.emit(tool_name, arguments)

func _on_shared_execution_completed(tool_name: String, result: ToolExecutionResult) -> void:
	_append_tool_log(tool_name, result.data, "")
	var signal_result: Dictionary = result.data if result.data is Dictionary else {"value": result.data}
	tool_execution_completed.emit(tool_name, signal_result)
	_log_info("Tool execution completed: " + tool_name)

func _on_shared_execution_failed(tool_name: String, result: ToolExecutionResult) -> void:
	_append_tool_log(tool_name, result.data, result.error_message)
	tool_execution_failed.emit(tool_name, result.error_message)
	_log_error("Tool execution failed: " + tool_name + " - " + result.error_message)
