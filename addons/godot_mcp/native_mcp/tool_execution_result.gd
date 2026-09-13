class_name ToolExecutionResult
extends RefCounted

var ok: bool = false
var data: Variant = null
var error_code: String = ""
var error_message: String = ""
var retryable: bool = false
var warnings: Array[String] = []
var artifacts: Array[Dictionary] = []
var truncated: bool = false
var next_cursor: String = ""
var duration_ms: int = 0

static func success(value: Variant = null) -> ToolExecutionResult:
	var result := ToolExecutionResult.new()
	result.ok = true
	result.data = value
	return result

static func failure(code: String, message: String, can_retry: bool = false) -> ToolExecutionResult:
	var result := ToolExecutionResult.new()
	result.ok = false
	result.error_code = code
	result.error_message = message
	result.retryable = can_retry
	return result

static func from_legacy(value: Variant) -> ToolExecutionResult:
	if value is Dictionary and value.has("error"):
		return failure("TOOL_EXECUTION_FAILED", str(value.get("error", "Tool execution failed")))
	return success(value)

func to_cli_dict() -> Dictionary:
	var payload: Dictionary = {
		"ok": ok,
		"data": data if ok else null,
		"warnings": warnings,
		"artifacts": artifacts,
		"meta": {
			"duration_ms": duration_ms,
			"truncated": truncated,
			"next_cursor": next_cursor if not next_cursor.is_empty() else null,
		},
	}
	if not ok:
		payload["error"] = {
			"code": error_code,
			"message": error_message,
			"retryable": retryable,
		}
	return payload
