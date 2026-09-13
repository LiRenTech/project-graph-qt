class_name McpTransportBase
extends RefCounted

# 传输层基类 - 定义所有传输方式的统一接口
# 符合 Godot 4.x 开发规范和 MCP 协议规范

# ==============================================================================
# 信号定义（用于线程间通信，确保线程安全）
# ==============================================================================

## 收到消息时触发
## @param message: Dictionary - JSON-RPC 消息
## @param context: Variant - 传输上下文（stdio: null, HTTP: StreamPeerTCP）
signal message_received(message: Dictionary, context: Variant)

## 发生错误时触发
## @param error: String - 错误描述
signal server_error(error: String)

## 服务器成功启动时触发
signal server_started()

## 服务器停止时触发
signal server_stopped()


# ==============================================================================
# 虚方法（子类必须实现）
# ==============================================================================

## 启动传输层
## @returns: bool - 启动成功返回 true，失败返回 false
func start() -> bool:
	push_error("McpTransportBase.start() must be overridden")
	return false

## 停止传输层
func stop() -> void:
	push_error("McpTransportBase.stop() must be overridden")

## 检查传输层是否正在运行
## @returns: bool - 运行中返回 true，否则返回 false
func is_running() -> bool:
	push_error("McpTransportBase.is_running() must be overridden")
	return false


# ==============================================================================
# 可选方法（子类可以重写）
# ==============================================================================

## 设置端口（HTTP 模式使用）
## @param port: int - 监听端口
func set_port(port: int) -> void:
	push_error("McpTransportBase.set_port() is not implemented")

## 设置认证管理器（HTTP 模式使用）
## @param manager: RefCounted - 认证管理器实例
func set_auth_manager(manager: RefCounted) -> void:
	push_error("McpTransportBase.set_auth_manager() is not implemented")

## 发送响应（某些传输方式需要）
## @param response: Dictionary - JSON-RPC 响应
## @param context: Variant - 传输上下文
func send_response(response: Dictionary, context: Variant) -> void:
	push_error("McpTransportBase.send_response() is not implemented")

## 发送原始 JSON-RPC 消息（用于服务端推送通知）
## @param message: Dictionary - 完整的 JSON-RPC 消息（包含 jsonrpc/method/params）
func send_raw_message(message: Dictionary) -> void:
	push_error("McpTransportBase.send_raw_message() is not implemented")
