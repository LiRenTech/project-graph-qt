# mcp_types.gd - MCP类型定义和常量
# 根据mcp-builder添加outputSchema和annotations支持
# 根据godot-dev-guide添加完整的类型提示

class_name MCPTypes
extends RefCounted

# ============================================================================
# 常量定义
# ============================================================================

# JSON-RPC版本
const JSONRPC_VERSION: String = "2.0"

# MCP协议版本
const PROTOCOL_VERSION: String = "2025-11-25"

# 标准MCP方法
const METHOD_INITIALIZE: String = "initialize"
const METHOD_NOTIFICATIONS_INITIALIZED: String = "notifications/initialized"
const METHOD_TOOLS_LIST: String = "tools/list"
const METHOD_TOOLS_CALL: String = "tools/call"
const METHOD_RESOURCES_LIST: String = "resources/list"
const METHOD_RESOURCES_READ: String = "resources/read"
const METHOD_RESOURCES_SUBSCRIBE: String = "resources/subscribe"
const METHOD_PROMPTS_LIST: String = "prompts/list"
const METHOD_PROMPTS_GET: String = "prompts/get"

# JSON-RPC错误码
const ERROR_PARSE_ERROR: int = -32700
const ERROR_INVALID_REQUEST: int = -32600
const ERROR_METHOD_NOT_FOUND: int = -32601
const ERROR_INVALID_PARAMS: int = -32602
const ERROR_INTERNAL_ERROR: int = -32603

# MCP自定义错误码
const ERROR_TOOL_NOT_FOUND: int = -32001
const ERROR_RESOURCE_NOT_FOUND: int = -32002
const ERROR_EXECUTION_FAILED: int = -32003

# 安全级别
enum SecurityLevel {
	PERMISSIVE,  # 宽松模式
	STRICT       # 严格模式
}

# 日志级别
enum LogLevel {
	ERROR,  # 只记录错误
	WARN,   # 记录警告和错误
	INFO,   # 记录信息、警告和错误
	DEBUG   # 记录所有信息
}

# ============================================================================
# MCPTool类 - 工具元数据（根据mcp-builder优化）
# ============================================================================

class MCPTool:
	var name: String = ""
	var description: String = ""
	var input_schema: Dictionary = {}
	var output_schema: Dictionary = {}
	var annotations: Dictionary = {}
	var callable: Callable = Callable()
	var enabled: bool = true
	var category: String = "core"
	var group: String = ""
	
	# 转换为Dictionary（用于JSON序列化）
	func to_dict() -> Dictionary:
		var result: Dictionary = {
			"name": name,
			"description": description,
			"inputSchema": input_schema,
			"x_category": category,
			"x_group": group
		}
		
		if not output_schema.is_empty():
			result["outputSchema"] = output_schema
		
		if not annotations.is_empty():
			result["annotations"] = annotations
		
		return result
	
	# 验证工具定义是否有效
	func is_valid() -> bool:
		if name.is_empty():
			return false
		if description.is_empty():
			return false
		if not callable.is_valid():
			return false
		return true
	
	# 创建annotations的帮助方法（根据mcp-builder）
	static func create_annotations(read_only: bool = false, 
								   destructive: bool = false,
								   idempotent: bool = false,
								   open_world: bool = false) -> Dictionary:
		return {
			"readOnlyHint": read_only,
			"destructiveHint": destructive,
			"idempotentHint": idempotent,
			"openWorldHint": open_world
		}

# ============================================================================
# MCPResource类 - 资源元数据（根据mcp-builder添加description）
# ============================================================================

class MCPResource:
	var uri: String = ""
	var name: String = ""
	var description: String = ""  # 新增（根据mcp-builder）
	var mime_type: String = "application/octet-stream"
	var load_callable: Callable = Callable()
	
	# 转换为Dictionary
	func to_dict() -> Dictionary:
		var result: Dictionary = {
			"uri": uri,
			"name": name,
			"mimeType": mime_type
		}
		
		# 添加description（根据mcp-builder）
		if not description.is_empty():
			result["description"] = description
		
		return result
	
	# 验证资源定义是否有效
	func is_valid() -> bool:
		if uri.is_empty():
			return false
		if name.is_empty():
			return false
		if not load_callable.is_valid():
			return false
		return true

# ============================================================================
# MCPPrompt类 - 提示模板元数据
# ============================================================================

class MCPPrompt:
	var name: String = ""
	var description: String = ""
	var arguments: Array[Dictionary] = []  # [{name, description, required}]
	
	func to_dict() -> Dictionary:
		return {
			"name": name,
			"description": description,
			"arguments": arguments
		}
	
	func is_valid() -> bool:
		return not name.is_empty()

# ============================================================================
# 工具函数
# ============================================================================

# 规范化 JSON-RPC id。
# Godot 的 JSON 解析会把整数 id 读成 float，例如 0 -> 0.0。
# JSON-RPC id 不应包含小数部分，部分 MCP 客户端会拒绝反序列化 0.0。
static func normalize_jsonrpc_id(id: Variant) -> Variant:
	if typeof(id) == TYPE_FLOAT:
		var integer_id: int = int(id)
		if is_equal_approx(id, float(integer_id)):
			return integer_id
	
	return id

# 创建标准JSON-RPC响应
static func create_response(id: Variant, result: Variant) -> Dictionary:
	return {
		"jsonrpc": JSONRPC_VERSION,
		"id": normalize_jsonrpc_id(id),
		"result": result
	}

# 创建标准JSON-RPC错误响应
static func create_error_response(id: Variant, code: int, message: String, data: Variant = null) -> Dictionary:
	var error: Dictionary = {
		"code": code,
		"message": message
	}
	
	if data != null:
		error["data"] = data
	
	return {
		"jsonrpc": JSONRPC_VERSION,
		"id": normalize_jsonrpc_id(id),
		"error": error
	}

# 创建标准MCP capabilities响应（根据mcp-builder优化）
static func create_capabilities(tools_changed: bool = true,
								resources_subscribe: bool = true,
								resources_changed: bool = true,
								prompts_changed: bool = true) -> Dictionary:
	var capabilities: Dictionary = {}
	
	if tools_changed:
		capabilities["tools"] = {"listChanged": true}
	
	if resources_subscribe or resources_changed:
		var resources_cap: Dictionary = {}
		if resources_subscribe:
			resources_cap["subscribe"] = true
		if resources_changed:
			resources_cap["listChanged"] = true
		capabilities["resources"] = resources_cap
	
	if prompts_changed:
		capabilities["prompts"] = {"listChanged": true}
	
	return capabilities

# 验证路径是否安全（根据mcp-builder安全最佳实践）
static func is_path_safe(path: String) -> bool:
	# 检查白名单
	var allowed_prefixes: Array[String] = ["res://", "user://"]
	var is_allowed: bool = false
	
	for prefix in allowed_prefixes:
		if path.begins_with(prefix):
			is_allowed = true
			break
	
	if not is_allowed:
		return false
	
	# 检查黑名单模式
	var blocked_patterns: Array[String] = ["..", "~", "$", "|", ";", "`", "&&", "||"]
	for pattern in blocked_patterns:
		if path.contains(pattern):
			return false
	
	# 检查路径长度
	if path.length() > 4096:
		return false
	
	return true

# 清理路径（根据mcp-builder安全最佳实践）
static func sanitize_path(path: String) -> String:
	var sanitized: String = path.replace("..", "").replace("~", "")
	
	if not sanitized.begins_with("res://") and not sanitized.begins_with("user://"):
		sanitized = "res://" + sanitized.lstrip("/")
	
	return sanitized

# 生成唯一ID
static func generate_id() -> String:
	return "mcp_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())

# ============================================================================
# 日志工具类
# ============================================================================

class MCPLogger:
	var level: int = LogLevel.INFO
	var prefix: String = "[MCP]"
	var _log_callback: Callable = Callable()
	
	func set_log_callback(callback: Callable) -> void:
		_log_callback = callback
	
	func error(message: String) -> void:
		if level >= LogLevel.ERROR:
			if _log_callback.is_valid():
				_log_callback.call("ERROR", prefix + "[ERROR] " + message)
	
	func warn(message: String) -> void:
		if level >= LogLevel.WARN:
			if _log_callback.is_valid():
				_log_callback.call("WARN", prefix + "[WARN] " + message)
	
	func info(message: String) -> void:
		if level >= LogLevel.INFO:
			if _log_callback.is_valid():
				_log_callback.call("INFO", prefix + "[INFO] " + message)
	
	func debug(message: String) -> void:
		if level >= LogLevel.DEBUG:
			if _log_callback.is_valid():
				_log_callback.call("DEBUG", prefix + "[DEBUG] " + message)
