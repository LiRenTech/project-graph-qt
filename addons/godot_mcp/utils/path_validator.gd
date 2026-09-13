# path_validator.gd
# 路径验证工具 - 防止路径遍历攻击和非法访问
# 版本: 1.0
# 作者: AI Assistant
# 日期: 2026-05-01

@tool
class_name PathValidator
extends RefCounted

# 信号
signal path_rejected(path: String, reason: String)
signal path_approved(path: String)

# 常量 - 允许的路径前缀
const ALLOWED_PATHS := ["res://", "user://"]

# 常量 - 危险路径模式
const DANGEROUS_PATTERNS := [
	"~",            # 用户目录
	"\\\\",         # Windows网络路径
	"C:\\",         # Windows绝对路径
	"/etc/",        # Linux系统目录
	"/var/",        # Linux变量目录
	"/tmp/",        # 临时目录
	"/Users/",      # macOS用户目录
	"/Library/",    # macOS系统库目录
	"/Applications/", # macOS应用目录
	"D:\\",        # 其他Windows盘符
	"E:\\",
	"F:\\"
]

# 配置
var _strict_mode: bool = true  # true=严格模式，false=宽松模式
var _allowed_extensions: Array[String] = []  # 允许的文件扩展名（空=不限制）

# 日志回调
var _log_callback: Callable = Callable()

## 设置日志回调函数
func set_log_callback(callback: Callable) -> void:
	_log_callback = callback

# ===========================================
# 路径验证主函数
# ===========================================

## 验证路径是否安全
## 返回: {valid: bool, error: String, sanitized: String}
static func validate_path(path: String, strict: bool = true) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"error": "",
		"sanitized": ""
	}
	
	if path.is_empty():
		result["error"] = "Path is empty"
		return result
	
	var sanitized: String = _sanitize_path(path)
	result["sanitized"] = sanitized
	
	var is_allowed: bool = false
	for allowed in ALLOWED_PATHS:
		if sanitized.begins_with(allowed):
			is_allowed = true
			break
	
	if not is_allowed:
		result["error"] = "Path must start with res:// or user://"
		return result
	
	if strict:
		for pattern in DANGEROUS_PATTERNS:
			if sanitized.contains(pattern):
				result["error"] = "Path contains dangerous pattern: " + pattern
				return result
		var path_part: String = sanitized
		for prefix in ALLOWED_PATHS:
			if path_part.begins_with(prefix):
				path_part = path_part.substr(prefix.length())
				break
		if path_part.contains(".."):
			result["error"] = "Path contains directory traversal: .."
			return result
	
	result["valid"] = true
	result["sanitized"] = sanitized
	return result

## 验证文件路径（检查扩展名）
## 返回: {valid: bool, error: String, sanitized: String}
static func validate_file_path(path: String, allowed_extensions: Array = []) -> Dictionary:
	var result: Dictionary = validate_path(path)
	if not result["valid"]:
		return result
	
	if not allowed_extensions.is_empty():
		var has_valid_ext: bool = false
		var path_lower: String = result["sanitized"].to_lower()
		
		for ext in allowed_extensions:
			if path_lower.ends_with(ext.to_lower()):
				has_valid_ext = true
				break
		
		if not has_valid_ext:
			result["valid"] = false
			result["error"] = "File extension not allowed. Allowed: " + str(allowed_extensions)
			return result
	
	return result

## 验证目录路径
## 返回: {valid: bool, error: String, sanitized: String}
static func validate_directory_path(path: String) -> Dictionary:
	var result: Dictionary = validate_path(path)
	if not result["valid"]:
		return result
	
	var sanitized: String = result["sanitized"]
	var path_without_prefix: String = sanitized
	for allowed in ALLOWED_PATHS:
		if path_without_prefix.begins_with(allowed):
			path_without_prefix = path_without_prefix.substr(allowed.length())
			break
	
	if not path_without_prefix.is_empty() and not path_without_prefix.ends_with("/"):
		sanitized += "/"
		result["sanitized"] = sanitized
	
	return result

# ===========================================
# 路径清理
# ===========================================

## 清理路径（移除危险字符）
static func _sanitize_path(path: String) -> String:
	var sanitized: String = path
	
	var prefix: String = ""
	for allowed in ALLOWED_PATHS:
		if sanitized.begins_with(allowed):
			prefix = allowed
			sanitized = sanitized.substr(allowed.length())
			break
	
	sanitized = sanitized.replace("..", "")
	
	while sanitized.contains("//"):
		sanitized = sanitized.replace("//", "/")
	
	if sanitized.begins_with("/"):
		sanitized = sanitized.lstrip("/")
	
	if prefix.is_empty():
		if path.begins_with("/"):
			prefix = "res://"
		else:
			prefix = "res://"
	
	return prefix + sanitized

# ===========================================
# 批量验证
# ===========================================

## 批量验证多个路径
## 返回: {valid: Array, invalid: Array[Dictionary]}
static func validate_paths(paths: Array[String], strict: bool = true) -> Dictionary:
	var result: Dictionary = {
		"valid": [],
		"invalid": []
	}
	
	for path in paths:
		var validation: Dictionary = validate_path(path, strict)
		if validation["valid"]:
			result["valid"].append(validation["sanitized"])
		else:
			result["invalid"].append({
				"path": path,
				"error": validation["error"]
			})
	
	return result

# ===========================================
# 实例方法（支持信号）
# ===========================================

## 实例方法：验证路径（会发射信号）
## 返回: bool
func validate_path_with_signal(path: String) -> bool:
	var result: Dictionary = validate_path(path, _strict_mode)
	
	if result["valid"]:
		path_approved.emit(result["sanitized"])
		return true
	else:
		path_rejected.emit(path, result["error"])
		return false

## 设置严格模式
func set_strict_mode(strict: bool) -> void:
	_strict_mode = strict
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Strict mode: " + str(strict))

## 添加允许的扩展名
func add_allowed_extension(extension: String) -> void:
	if not _allowed_extensions.has(extension):
		_allowed_extensions.append(extension)
		if _log_callback.is_valid():
			_log_callback.call("INFO", "Added allowed extension: " + extension)

## 清除允许的扩展名（不限制）
func clear_allowed_extensions() -> void:
	_allowed_extensions.clear()
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Cleared allowed extensions (no restriction)")

# ===========================================
# 调试功能
# ===========================================

## 测试路径验证（调试用）
## 返回: Array[String] 验证结果文本
static func test_validation() -> Array[String]:
	var output: Array[String] = []
	output.append("Testing path validation...")
	
	var test_paths: Array[String] = [
		"res://test.tscn",
		"user://save.dat",
		"../../../etc/passwd",
		"C:\\Windows\\System32",
		"res://../escape.tscn",
		"res://normal/path/script.gd"
	]
	
	for path in test_paths:
		var result: Dictionary = validate_path(path)
		output.append("  Path: " + path)
		output.append("    Valid: " + str(result["valid"]))
		if not result["valid"]:
			output.append("    Error: " + result["error"])
		else:
			output.append("    Sanitized: " + result["sanitized"])
		output.append("")
	
	return output
