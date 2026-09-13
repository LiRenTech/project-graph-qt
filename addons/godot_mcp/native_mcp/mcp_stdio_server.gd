class_name McpStdioServer
extends McpTransportBase

# stdio 传输实现 - 从 mcp_server_core.gd 中提取
# 负责处理 stdin/stdout 的 JSON-RPC 消息传输
# 继承自 McpTransportBase，实现传输层统一接口

# ==============================================================================
# 状态变量（带类型提示 - 根据 godot-dev-guide）
# ==============================================================================

## 是否正在运行
var _active: bool = false

## stdin 监听线程
var _thread: Thread = null

## 互斥锁（用于线程安全访问消息队列）
var _mutex: Mutex = Mutex.new()

## 消息队列（存储待处理的消息）
var _message_queue: Array[Dictionary] = []

## 响应队列（存储待发送的响应）
var _response_queue: Array[Dictionary] = []

## 日志回调
var _log_callback: Callable = Callable()

## 设置日志回调函数
func set_log_callback(callback: Callable) -> void:
	_log_callback = callback


# ==============================================================================
# McpTransportBase 接口实现
# ==============================================================================

## 启动 stdio 传输层
## @returns: bool - 启动成功返回 true，失败返回 false
func start() -> bool:
	_active = true
	
	# 确保 stdout 及时刷新
	ProjectSettings.set_setting("application/run/flush_stdout_on_print", true)
	
	_thread = Thread.new()
	_thread.start(_stdin_listen_loop)
	
	server_started.emit()
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Server started")
	
	return true

## 停止 stdio 传输层
func stop() -> void:
	if not _active:
		return
	
	_active = false
	
	# 等待线程结束
	if _thread and _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
	
	# 清空队列
	_mutex.lock()
	_message_queue.clear()
	_response_queue.clear()
	_mutex.unlock()
	
	server_stopped.emit()
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Server stopped")

## 检查传输层是否正在运行
## @returns: bool - 运行中返回 true，否则返回 false
func is_running() -> bool:
	return _active


# ==============================================================================
# stdio 传输核心逻辑（从 mcp_server_core.gd 提取并优化）
# ==============================================================================

## stdin 监听循环（在独立线程中运行）
func _stdin_listen_loop() -> void:
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Listen loop started")
	
	while _active:
		# 从 stdin 读取数据
		var input: String = OS.read_string_from_stdin()
		
		if not input.is_empty():
			# 解析消息
			_parse_and_queue_message(input)
		
		# 避免 CPU 占用过高
		OS.delay_msec(10)
	
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Listen loop stopped")

## 解析并队列消息
## @param raw_input: String - 从 stdin 读取的原始字符串
func _parse_and_queue_message(raw_input: String) -> void:
	var lines: PackedStringArray = raw_input.split("\n")
	
	for line in lines:
		if line.is_empty():
			continue
		
		var json: JSON = JSON.new()
		var parse_result: Error = json.parse(line)
		
		if parse_result != OK:
			if _log_callback.is_valid():
				_log_callback.call("ERROR", "JSON parse error: " + json.get_error_message())
			call_deferred("_emit_error", null, MCPTypes.ERROR_PARSE_ERROR, "Failed to parse JSON input", line)
			continue
		
		var message: Dictionary = json.get_data()
		
		# 线程安全：使用互斥锁保护消息队列
		_mutex.lock()
		_message_queue.append(message)
		_mutex.unlock()
		
		# 在主线程中处理消息（确保线程安全）
		call_deferred("_process_next_message")
	
	# 处理响应队列
	call_deferred("_process_response_queue")

## 处理下一个消息
func _process_next_message() -> void:
	_mutex.lock()
	
	if _message_queue.is_empty():
		_mutex.unlock()
		return
	
	var message: Dictionary = _message_queue.pop_front()
	
	_mutex.unlock()
	
	# 发送信号到核心层处理
	message_received.emit(message, null)  # context 为 null（stdio 不需要）

## 处理响应队列（stdio 模式：直接输出到 stdout）
func _process_response_queue() -> void:
	_mutex.lock()
	
	if _response_queue.is_empty():
		_mutex.unlock()
		return
	
	var response: Dictionary = _response_queue.pop_front()
	
	_mutex.unlock()
	
	# 发送到 stdout
	_send_response(response)

## 发送响应（stdio 模式：输出到 stdout）
## @param response: Dictionary - JSON-RPC 响应
func _send_response(response: Dictionary) -> void:
	var json_string: String = JSON.stringify(response)
	
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Sending response: " + json_string)
	
	# 输出到 stdout
	print(json_string)

## 发送错误响应
## @param id: Variant - 请求 ID
## @param code: int - 错误代码
## @param message: String - 错误消息
## @param data: Variant - 附加数据（可选）
func _send_error(id: Variant, code: int, message: String, data: Variant = null) -> void:
	var error_response: Dictionary = MCPTypes.create_error_response(id, code, message, data)
	_send_response(error_response)

## 发送原始 JSON-RPC 消息（直接输出到 stdout）
## @param message: Dictionary - 完整的 JSON-RPC 消息
func send_raw_message(message: Dictionary) -> void:
	var json_string: String = JSON.stringify(message)
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Sending raw message: " + json_string)
	print(json_string)

## 队列响应（供外部调用）
## @param response: Dictionary - JSON-RPC 响应
func queue_response(response: Dictionary) -> void:
	_mutex.lock()
	_response_queue.append(response)
	_mutex.unlock()
	
	call_deferred("_process_response_queue")

## 在主线程中发送错误信号（线程安全）
func _emit_error(id: Variant, code: int, message: String, data: Variant = null) -> void:
	server_error.emit("JSON parse error: " + message)
