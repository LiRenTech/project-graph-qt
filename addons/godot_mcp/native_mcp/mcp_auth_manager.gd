class_name McpAuthManager
extends RefCounted

# HTTP 模式认证管理器 - token-based auth
# 符合 MCP 安全最佳实践和 RFC 6750 (Bearer Token)

# ==============================================================================
# 配置变量
# ==============================================================================

## 认证 token（必须 ≥ 16 字符）
var _token: String = ""

## 是否启用认证
var _enabled: bool = true


# ==============================================================================
# 常量
# ==============================================================================

## HTTP 认证头名称
const HEADER_NAME: String = "authorization"

## Bearer 认证方案
const SCHEME: String = "Bearer"


# ==============================================================================
# 公共方法
# ==============================================================================

## 设置认证 token
## @param token: String - 认证令牌（必须 ≥ 16 字符）
func set_token(token: String) -> void:
	if token.length() < 16:
		push_error("Auth token must be at least 16 characters long")
		return
	_token = token

## 启用/禁用认证
## @param enabled: bool - true 启用，false 禁用
func set_enabled(enabled: bool) -> void:
	_enabled = enabled

## 验证 HTTP 请求的认证头
## @param headers: Dictionary - HTTP 请求头字典
## @returns: bool - 验证通过返回 true，否则返回 false
func validate_request(headers: Dictionary) -> bool:
	# 如果认证未启用，直接通过
	if not _enabled:
		return true
	
	# 检查是否存在 Authorization 头
	if not headers.has(HEADER_NAME):
		return false  # 缺少认证头
	
	var auth_header: String = headers[HEADER_NAME]
	
	# 检查格式：Bearer <token>
	if not auth_header.begins_with(SCHEME + " "):
		return false  # 格式错误
	
	# 提取 token
	var token: String = auth_header.substr(SCHEME.length() + 1)
	
	var result: bool = true
	var max_len: int = maxi(token.length(), _token.length())
	
	for i in range(max_len):
		var token_char: String = token[i] if i < token.length() else ""
		var stored_char: String = _token[i] if i < _token.length() else ""
		if token_char != stored_char:
			result = false
	
	if token.length() != _token.length():
		result = false
	
	return result

## 返回 WWW-Authenticate 头（用于 401 响应）
## @returns: String - WWW-Authenticate 头值
func get_www_authenticate_header() -> String:
	return SCHEME + ' realm="Godot MCP Native", error="invalid_token"'

## 生成随机 token
## @param length: int - token 长度（默认 32）
## @returns: String - 随机生成的 token
static func generate_token(length: int = 32) -> String:
	var chars: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
	var token: String = ""
	
	for i in range(length):
		var idx: int = randi() % chars.length()
		token += chars[idx]
	
	return token
