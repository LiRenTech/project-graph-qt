class_name ToolExecutor
extends RefCounted

signal execution_started(tool_name: String, arguments: Dictionary)
signal execution_completed(tool_name: String, result: ToolExecutionResult)
signal execution_failed(tool_name: String, result: ToolExecutionResult)

var _registry: ToolRegistry = null

func _init(registry: ToolRegistry = null) -> void:
	_registry = registry

func set_registry(registry: ToolRegistry) -> void:
	_registry = registry

func execute(tool_name: String, arguments: Dictionary, context: ToolExecutionContext) -> ToolExecutionResult:
	var started_at: int = Time.get_ticks_msec()
	if _registry == null:
		return _finish_failure(tool_name, started_at, "EXECUTOR_NOT_CONFIGURED", "Tool executor is not configured")
	var definition: ToolDefinition = _registry.get_tool(tool_name)
	if definition == null:
		return _finish_failure(tool_name, started_at, "TOOL_NOT_FOUND", "Tool not found: " + tool_name)
	if not definition.policy.available:
		return _finish_failure(tool_name, started_at, "TOOL_UNAVAILABLE", "Tool is unavailable: " + tool_name)
	if context.caller == "cli" and not definition.policy.cli_allowed:
		return _finish_failure(tool_name, started_at, "CLI_NOT_ALLOWED", "Tool is not allowed through the CLI: " + tool_name)
	if context.caller == "mcp" and not definition.policy.mcp_visible:
		return _finish_failure(tool_name, started_at, "MCP_NOT_VISIBLE", "Tool is not exposed through MCP: " + tool_name)
	if context.dry_run and definition.policy.risk_level != "read":
		var preview := ToolExecutionResult.success({
			"preview": true,
			"tool": tool_name,
			"arguments": arguments,
			"risk": definition.policy.risk_level,
		})
		preview.duration_ms = Time.get_ticks_msec() - started_at
		return preview
	if definition.policy.requires_apply and not context.apply_confirmed:
		return _finish_failure(tool_name, started_at, "APPLY_REQUIRED", "This operation requires explicit apply confirmation")
	if definition.policy.requires_open_world_permission and not context.allow_open_world:
		return _finish_failure(tool_name, started_at, "OPEN_WORLD_PERMISSION_REQUIRED", "This operation requires open-world permission")
	if not definition.callable.is_valid():
		return _finish_failure(tool_name, started_at, "INVALID_CALLABLE", "Tool callable is invalid: " + tool_name)
	execution_started.emit(tool_name, arguments)
	var legacy_result: Variant = await definition.callable.call(arguments)
	var result: ToolExecutionResult = ToolExecutionResult.from_legacy(legacy_result)
	result.duration_ms = Time.get_ticks_msec() - started_at
	if result.ok:
		execution_completed.emit(tool_name, result)
	else:
		execution_failed.emit(tool_name, result)
	return result

func _finish_failure(tool_name: String, started_at: int, code: String, message: String) -> ToolExecutionResult:
	var result := ToolExecutionResult.failure(code, message)
	result.duration_ms = Time.get_ticks_msec() - started_at
	execution_failed.emit(tool_name, result)
	return result
