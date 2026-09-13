class_name CliApiHandler
extends RefCounted

const API_VERSION: int = 1
const SCHEMA_VERSION: int = 1
const API_HEADER: String = "x-gdmcp-api-version"

var _server_core: RefCounted = null
var _plugin: Object = null
var _registry := ToolRegistry.new()
var _executor := ToolExecutor.new(_registry)
var _limiter := CliResultLimiter.new()
var _auth_required: bool = false

func configure(server_core: RefCounted, plugin: Object = null, auth_required: bool = false) -> void:
	_server_core = server_core
	_plugin = plugin
	_auth_required = auth_required
	if _server_core != null and _server_core.has_method("get_tool_registry"):
		_registry = _server_core.get_tool_registry()
	if _server_core != null and _server_core.has_method("get_tool_executor"):
		_executor = _server_core.get_tool_executor()
	else:
		_executor = ToolExecutor.new(_registry)
	refresh_registry()

func refresh_registry() -> void:
	if _server_core != null and _server_core.has_method("get_tool_registry"):
		_registry = _server_core.get_tool_registry()
		return
	_registry.clear()
	if _server_core == null or not _server_core.has_method("get_all_tools"):
		return
	var tools: Dictionary = _server_core.get_all_tools()
	for tool_name in tools:
		_registry.register_tool(ToolDefinition.from_legacy(tools[tool_name]))

func handle_request(method: String, raw_path: String, headers: Dictionary, body: String) -> Dictionary:
	var requested_version: String = str(headers.get(API_HEADER, str(API_VERSION)))
	if requested_version != str(API_VERSION):
		return _error_response(409, "API_VERSION_MISMATCH", "Supported API version is 1")
	refresh_registry()
	var parsed_path: Dictionary = _parse_path(raw_path)
	var path: String = parsed_path["path"]
	var query: Dictionary = parsed_path["query"]
	if method == "GET" and path == "/cli/v1/doctor":
		return _json_response(200, _doctor())
	if method == "GET" and path == "/cli/v1/catalog":
		return _json_response(200, {
			"api_version": API_VERSION,
			"schema_version": SCHEMA_VERSION,
			"catalog_hash": _registry.get_catalog_hash(),
			"tools": _registry.to_cli_catalog(),
		})
	if method == "GET" and path == "/cli/v1/tools/search":
		var search_query: String = str(query.get("q", ""))
		var raw_limit: String = str(query.get("limit", "5"))
		var limit: int = int(raw_limit)
		if limit <= 0 or str(limit) != raw_limit:
			return _error_response(400, "INVALID_ARGUMENT", "limit must be a positive integer")
		limit = mini(limit, 20)
		return _json_response(200, _envelope("tools.search", {
			"query": search_query,
			"tools": _registry.search_tools(search_query, limit),
		}))
	if path.begins_with("/cli/v1/tools/"):
		var suffix: String = path.trim_prefix("/cli/v1/tools/")
		if method == "POST" and suffix.ends_with("/execute"):
			return await _execute(suffix.trim_suffix("/execute"), body)
		if method == "GET" and not suffix.contains("/"):
			var definition: ToolDefinition = _registry.get_tool(suffix)
			if definition == null:
				return _error_response(404, "TOOL_NOT_FOUND", "Tool not found: " + suffix)
			return _json_response(200, _envelope("tools.schema", definition.to_cli_schema()))
	return _error_response(404, "NOT_FOUND", "CLI API route not found")

func _execute(tool_name: String, body: String) -> Dictionary:
	var parsed_body: Dictionary = {}
	if not body.is_empty():
		var json := JSON.new()
		if json.parse(body) != OK:
			return _error_response(400, "INVALID_JSON", "Request body must be a JSON object")
		var json_data: Variant = json.get_data()
		if not (json_data is Dictionary):
			return _error_response(400, "INVALID_JSON", "Request body must be a JSON object")
		parsed_body = json_data
	var context := ToolExecutionContext.new()
	context.caller = "cli"
	context.request_id = str(parsed_body.get("request_id", ""))
	context.dry_run = bool(parsed_body.get("dry_run", false))
	context.apply_confirmed = bool(parsed_body.get("apply_confirmed", false))
	context.allow_open_world = bool(parsed_body.get("allow_open_world", false))
	context.max_bytes = int(parsed_body.get("max_bytes", CliResultLimiter.DEFAULT_MAX_BYTES))
	var limit: int = CliResultLimiter.DEFAULT_LIST_LIMIT
	if parsed_body.has("limit"):
		limit = int(parsed_body["limit"])
		if limit <= 0:
			return _error_response(400, "INVALID_ARGUMENT", "limit must be greater than zero")
	var raw_arguments: Variant = parsed_body.get("arguments", {})
	if not (raw_arguments is Dictionary):
		return _error_response(400, "INVALID_ARGUMENTS", "arguments must be a JSON object")
	var result: ToolExecutionResult = await _executor.execute(tool_name, raw_arguments, context)
	if result.ok:
		var limited: Dictionary = _limiter.apply(result.data, {
			"fields": parsed_body.get("fields", PackedStringArray()),
			"limit": limit,
			"cursor": parsed_body.get("cursor", "0"),
			"depth": parsed_body.get("depth", -1),
			"max_bytes": context.max_bytes,
		})
		if limited.has("error"):
			return _error_response(413, limited["error"]["code"], limited["error"]["message"], limited["error"])
		result.data = limited["data"]
		result.truncated = bool(limited["truncated"])
		result.next_cursor = str(limited["next_cursor"])
	var status: int = 200 if result.ok else _status_for_error(result.error_code)
	var payload: Dictionary = result.to_cli_dict()
	payload["schema_version"] = SCHEMA_VERSION
	payload["api_version"] = API_VERSION
	payload["command"] = "tool-call." + tool_name
	return _json_response(status, payload)

func _doctor() -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	var runtime_running: bool = false
	if _plugin != null and _plugin.has_method("is_runtime_running"):
		runtime_running = bool(_plugin.call("is_runtime_running"))
	return {
		"api_version": API_VERSION,
		"schema_version": SCHEMA_VERSION,
		"plugin_version": "1.0.7",
		"godot_version": str(version.get("string", version)),
		"project_path": ProjectSettings.globalize_path("res://"),
		"editor_connected": _plugin != null,
		"runtime_running": runtime_running,
		"catalog_hash": _registry.get_catalog_hash(),
		"auth": {"required": _auth_required, "source": "bearer" if _auth_required else "localhost"},
	}

func _parse_path(raw_path: String) -> Dictionary:
	var question: int = raw_path.find("?")
	var path: String = raw_path if question < 0 else raw_path.left(question)
	var query: Dictionary = {}
	if question >= 0:
		for pair in raw_path.substr(question + 1).split("&", false):
			var separator: int = pair.find("=")
			if separator < 0:
				query[pair.uri_decode()] = ""
			else:
				query[pair.left(separator).uri_decode()] = pair.substr(separator + 1).uri_decode()
	return {"path": path, "query": query}

func _envelope(command: String, data: Variant) -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "api_version": API_VERSION, "ok": true, "command": command, "data": data, "meta": {"truncated": false, "next_cursor": null}}

func _json_response(status: int, payload: Dictionary) -> Dictionary:
	return {"status": status, "content_type": "application/json; charset=utf-8", "body": payload}

func _error_response(status: int, code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var error: Dictionary = {"code": code, "message": message, "retryable": status >= 500}
	if not details.is_empty():
		error["details"] = details
	return _json_response(status, {"schema_version": SCHEMA_VERSION, "api_version": API_VERSION, "ok": false, "data": null, "error": error, "meta": {"truncated": false, "next_cursor": null}})

func _status_for_error(code: String) -> int:
	match code:
		"TOOL_NOT_FOUND": return 404
		"APPLY_REQUIRED", "OPEN_WORLD_PERMISSION_REQUIRED", "CLI_NOT_ALLOWED": return 403
		"TOOL_UNAVAILABLE": return 409
		_: return 422
