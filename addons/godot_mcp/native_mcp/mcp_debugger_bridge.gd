@tool
class_name MCPDebuggerBridge
extends EditorDebuggerPlugin

var _capture_prefixes: Array[String] = [
	"mcp",
	"debug_enter",
	"debug_exit",
	"stack_dump",
	"stack_frame_vars",
	"stack_frame_var",
	"output",
	"error",
	"script_error",
	"gdscript"
]
var _captured_messages: Array[Dictionary] = []
var _max_messages: int = 500
var _connected_script_debuggers: Array[Object] = []
var _latest_stack_dump: Array = []
var _latest_stack_variables: Dictionary = {}
var _latest_evaluations: Dictionary = {}
var _state_events: Array[Dictionary] = []
var _output_events: Array[Dictionary] = []
var _max_state_events: int = 200
var _max_output_events: int = 500
var _next_variables_reference: int = 1
var _variable_references: Dictionary = {}
var _scope_variables_references: Dictionary = {}
var _evaluation_variables_references: Dictionary = {}
var _pending_stack_vars_frame: int = 0
var _message_sequence: int = 0
var _probe_ready_session_ids: Dictionary = {}

func get_message_sequence() -> int:
	return _message_sequence

func _setup_session(session_id: int) -> void:
	_probe_ready_session_ids.erase(session_id)
	call_deferred("_refresh_script_debugger_connections")

func _has_capture(capture: String) -> bool:
	return _capture_prefixes.has("*") or _capture_prefixes.has(capture)

func _capture(message: String, data: Array, session_id: int) -> bool:
	_append_captured_message(session_id, message, data)
	if message == "mcp:probe_ready":
		_probe_ready_session_ids[session_id] = true
	# Bridge "error" messages to output events (handles GDScript runtime errors from EngineDebugger)
	if data.size() > 0 and (message == "error" or message.begins_with("error:") or message.begins_with("error ")):
		var error_msg: String = str(data[0]) if data.size() > 0 else ""
		var error_file: String = str(data[1]) if data.size() > 1 else ""
		var error_line: int = int(data[2]) if data.size() > 2 else 0
		var error_func: String = str(data[3]) if data.size() > 3 else ""
		_append_output_event({
			"category": "stderr",
			"message": error_msg,
			"file": error_file,
			"line": error_line,
			"function": error_func,
			"type": 1
		})
	# Bridge "script_error" / "gdscript" messages to output events (handles GDScript runtime errors)
	elif data.size() > 0 and (message == "script_error" or message.begins_with("script_error:") or message == "gdscript" or message.begins_with("gdscript:")):
		var error_msg: String = str(data[0]) if data.size() > 0 else ""
		var error_file: String = str(data[1]) if data.size() > 1 else ""
		var error_line: int = int(data[2]) if data.size() > 2 else 0
		var error_func: String = str(data[3]) if data.size() > 3 else ""
		_append_output_event({
			"category": "stderr",
			"message": error_msg,
			"file": error_file,
			"line": error_line,
			"function": error_func,
			"type": 1
		})
	# Bridge "output" messages to output events (handles print/printerr from EngineDebugger)
	elif message == "output" and data.size() >= 2:
		var output_message: String = str(data[0])
		var output_type: int = int(data[1])
		_append_output_event({
			"category": _map_output_category(output_type),
			"message": output_message,
			"type": output_type
		})
	return true

func add_capture_prefix(prefix: String) -> void:
	if prefix.is_empty() or _capture_prefixes.has(prefix):
		return
	_capture_prefixes.append(prefix)

func is_probe_ready(session_id: int = -1) -> bool:
	if session_id >= 0:
		return _probe_ready_session_ids.has(session_id)
	return _probe_ready_session_ids.size() > 0

func wait_for_probe_ready(session_id: int = -1, timeout_ms: int = 2000) -> bool:
	if is_probe_ready(session_id):
		return true
	var deadline_ms: int = Time.get_ticks_msec() + timeout_ms
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	while Time.get_ticks_msec() < deadline_ms:
		if tree:
			await tree.process_frame
		else:
			OS.delay_msec(16)
		get_captured_messages(1, 0, "desc")
		if is_probe_ready(session_id):
			return true
	return is_probe_ready(session_id)

func reset_probe_ready(session_id: int = -1) -> void:
	if session_id >= 0:
		_probe_ready_session_ids.erase(session_id)
	else:
		_probe_ready_session_ids.clear()

func get_sessions_info() -> Array[Dictionary]:
	_refresh_script_debugger_connections()
	var result: Array[Dictionary] = []
	var sessions: Array = get_sessions()
	for index in range(sessions.size()):
		var session: EditorDebuggerSession = sessions[index]
		if not session:
			continue
		result.append({
			"session_id": index,
			"active": session.is_active(),
			"breaked": session.is_breaked(),
			"debuggable": session.is_debuggable()
		})
	return result

func set_breakpoint(path: String, line: int, enabled: bool, session_id: int = -1) -> Dictionary:
	return _for_each_session(session_id, func(session: EditorDebuggerSession) -> void:
		session.set_breakpoint(path, line, enabled)
	)

func send_debugger_message(message: String, data: Array, session_id: int = -1) -> Dictionary:
	_refresh_script_debugger_connections()
	var action: Callable = func(session: EditorDebuggerSession) -> void:
		session.send_message(message, data)
	return _for_each_session(session_id, action, true)

func request_stack_dump(session_id: int = -1) -> Dictionary:
	_refresh_script_debugger_connections()
	return send_debugger_message("get_stack_dump", [], session_id)

func request_stack_frame_vars(frame: int = 0, session_id: int = -1) -> Dictionary:
	_refresh_script_debugger_connections()
	_pending_stack_vars_frame = frame
	return send_debugger_message("get_stack_frame_vars", [frame], session_id)

func request_evaluate(expression: String, frame: int = 0, session_id: int = -1) -> Dictionary:
	_refresh_script_debugger_connections()
	return send_debugger_message("evaluate", [expression, frame], session_id)

func get_latest_stack_dump() -> Array:
	return _latest_stack_dump.duplicate(true)

func get_latest_stack_variables(frame: int = -1) -> Array:
	if frame >= 0:
		return _latest_stack_variables.get(frame, []).duplicate(true)
	var result: Array = []
	var frames: Array = _latest_stack_variables.keys()
	frames.sort()
	for frame_id in frames:
		result.append({
			"frame": frame_id,
			"variables": _latest_stack_variables[frame_id].duplicate(true)
		})
	return result

func get_latest_evaluation(expression: String = "") -> Variant:
	if not expression.is_empty():
		return _latest_evaluations.get(expression, null)
	if _latest_evaluations.is_empty():
		return null
	var keys: Array = _latest_evaluations.keys()
	keys.sort()
	return _latest_evaluations[keys[keys.size() - 1]]

func get_state_events(count: int = 100, offset: int = 0, order: String = "desc") -> Dictionary:
	var events: Array = _state_events.duplicate(true)
	if order == "desc":
		events.reverse()
	var start: int = clampi(offset, 0, events.size())
	var end: int = clampi(start + max(count, 0), start, events.size())
	return {
		"events": events.slice(start, end),
		"count": end - start,
		"total_available": events.size()
	}

func get_output_events(count: int = 100, offset: int = 0, order: String = "desc", category: String = "") -> Dictionary:
	var events: Array = []
	for entry in _output_events:
		if category.is_empty() or str(entry.get("category", "")) == category:
			events.append(entry.duplicate(true))
	if order == "desc":
		events.reverse()
	var start: int = clampi(offset, 0, events.size())
	var end: int = clampi(start + max(count, 0), start, events.size())
	return {
		"events": events.slice(start, end),
		"count": end - start,
		"total_available": events.size()
	}

func get_threads() -> Array[Dictionary]:
	var threads: Array[Dictionary] = []
	for session in get_sessions_info():
		if not session.get("active", false):
			continue
		threads.append({
			"thread_id": 1,
			"name": "Main",
			"session_id": int(session.get("session_id", -1)),
			"active": bool(session.get("active", false)),
			"breaked": bool(session.get("breaked", false)),
			"debuggable": bool(session.get("debuggable", false))
		})
	return threads

func get_scope_variables_reference(frame: int, scope: String) -> int:
	var scope_name: String = scope.strip_edges().to_lower()
	var key: String = "%d:%s" % [frame, scope_name]
	if _scope_variables_references.has(key):
		return int(_scope_variables_references[key])
	var entries: Array = []
	for variable_entry in get_latest_stack_variables(frame):
		if str(variable_entry.get("scope", "")).to_lower() != scope_name:
			continue
		entries.append(_build_variable_entry(
			str(variable_entry.get("name", "")),
			variable_entry.get("value", null),
			str(variable_entry.get("type", ""))
		))
	if entries.is_empty():
		return 0
	var reference: int = _store_variable_reference(entries)
	_scope_variables_references[key] = reference
	return reference

func get_evaluation_variables_reference(expression: String) -> int:
	var key: String = expression.strip_edges()
	if key.is_empty():
		return 0
	if _evaluation_variables_references.has(key):
		return int(_evaluation_variables_references[key])
	var evaluation: Variant = get_latest_evaluation(key)
	if not (evaluation is Dictionary):
		return 0
	var reference: int = _build_nested_variables_reference(evaluation.get("value", null))
	if reference > 0:
		_evaluation_variables_references[key] = reference
	return reference

func get_variables_by_reference(variables_reference: int, count: int = 100, offset: int = 0) -> Dictionary:
	var entries: Array = _variable_references.get(variables_reference, []).duplicate(true)
	var start: int = clampi(offset, 0, entries.size())
	var end: int = clampi(start + max(count, 0), start, entries.size())
	return {
		"variables_reference": variables_reference,
		"variables": entries.slice(start, end),
		"count": end - start,
		"total_available": entries.size()
	}

func toggle_profiler(profiler: String, enabled: bool, data: Array, session_id: int = -1) -> Dictionary:
	var action: Callable = func(session: EditorDebuggerSession) -> void:
		session.toggle_profiler(profiler, enabled, data)
	return _for_each_session(session_id, action, true)

func get_captured_messages(count: int = 100, offset: int = 0, order: String = "desc") -> Dictionary:
	_refresh_script_debugger_connections()
	var messages: Array = _captured_messages.duplicate()
	if order == "desc":
		messages.reverse()
	var start: int = clampi(offset, 0, messages.size())
	var end: int = clampi(start + max(count, 0), start, messages.size())
	return {
		"messages": messages.slice(start, end),
		"count": end - start,
		"total_available": messages.size()
	}

func get_capture_prefixes() -> Array[String]:
	return _capture_prefixes.duplicate()

func get_latest_message_payload(message: String, match_fields: Dictionary = {}) -> Variant:
	for index in range(_captured_messages.size() - 1, -1, -1):
		var entry: Dictionary = _captured_messages[index]
		if str(entry.get("message", "")) != message:
			continue
		var captured_data: Array = entry.get("data", [])
		var payload: Variant = captured_data[0] if not captured_data.is_empty() else null
		if _payload_matches(payload, match_fields):
			return payload
	return null

func get_captured_message_after_sequence(sequence: int, response_messages: Array, error_messages: Array = [], match_fields: Dictionary = {}) -> Dictionary:
	for entry in _captured_messages:
		if int(entry.get("sequence", 0)) <= sequence:
			continue
		var message: String = str(entry.get("message", ""))
		if not response_messages.has(message) and not error_messages.has(message):
			continue
		var captured_data: Array = entry.get("data", [])
		var payload: Variant = captured_data[0] if not captured_data.is_empty() else null
		if response_messages.has(message) and not _payload_matches(payload, match_fields):
			continue
		return entry
	return {}

func request_runtime_message(message: String, data: Array = [], response_messages: Array = [], error_messages: Array = ["mcp:error"], session_id: int = -1, timeout_ms: int = 1500) -> Dictionary:
	var baseline_sequence: int = _message_sequence
	var send_result: Dictionary = send_debugger_message("mcp:" + message, data, session_id)
	if send_result.has("error"):
		return send_result
	if send_result.get("sessions_updated", 0) <= 0:
		return send_result

	var wait_until: int = Time.get_ticks_msec() + maxi(timeout_ms, 1)
	while Time.get_ticks_msec() <= wait_until:
		var captured: Dictionary = _find_captured_message_after_sequence(baseline_sequence, response_messages, error_messages)
		if not captured.is_empty():
			var payload: Variant = null
			var captured_data: Array = captured.get("data", [])
			if not captured_data.is_empty():
				payload = captured_data[0]
			if error_messages.has(captured.get("message", "")):
				return {
					"error": _extract_runtime_error(payload),
					"message": captured.get("message", ""),
					"payload": payload,
					"captured": captured
				}
			return {
				"status": "success",
				"message": captured.get("message", ""),
				"payload": payload,
				"captured": captured
			}
		OS.delay_msec(10)
		if DisplayServer.has_method("process_events"):
			DisplayServer.process_events()
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree:
			await tree.process_frame

	return {
		"error": "Timed out waiting for runtime response: " + message,
		"status": "timeout",
		"response_messages": response_messages
	}

func _refresh_script_debugger_connections() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var base: Node = tree.root
	if not base:
		return
	var pending: Array[Node] = [base]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.get_class() == "ScriptEditorDebugger":
			_connect_script_debugger(node)
		for child in node.get_children():
			pending.append(child)

func _connect_script_debugger(debugger: Object) -> void:
	if _connected_script_debuggers.has(debugger):
		return
	if debugger.has_signal("stack_dump"):
		debugger.connect("stack_dump", Callable(self, "_on_stack_dump"))
	if debugger.has_signal("stack_frame_vars"):
		debugger.connect("stack_frame_vars", Callable(self, "_on_stack_frame_vars"))
	if debugger.has_signal("stack_frame_var"):
		debugger.connect("stack_frame_var", Callable(self, "_on_stack_frame_var"))
	if debugger.has_signal("debug_data"):
		debugger.connect("debug_data", Callable(self, "_on_debug_data"))
	if debugger.has_signal("breaked"):
		debugger.connect("breaked", Callable(self, "_on_breaked"))
	if debugger.has_signal("output"):
		debugger.connect("output", Callable(self, "_on_output"))
	if debugger.has_signal("stopped"):
		debugger.connect("stopped", Callable(self, "_on_stopped"))
	_connected_script_debuggers.append(debugger)

func _on_stack_dump(stack: Array) -> void:
	_latest_stack_dump = stack.duplicate(true)
	_latest_stack_variables.clear()
	_reset_variables_references()
	_append_captured_message(-1, "stack_dump", [stack])

func _on_stack_frame_vars(size: Variant) -> void:
	_latest_stack_variables[_pending_stack_vars_frame] = []
	_scope_variables_references.erase("%d:local" % _pending_stack_vars_frame)
	_scope_variables_references.erase("%d:member" % _pending_stack_vars_frame)
	_scope_variables_references.erase("%d:global" % _pending_stack_vars_frame)
	_scope_variables_references.erase("%d:constant" % _pending_stack_vars_frame)
	_append_captured_message(-1, "stack_frame_vars", [size])

func _on_stack_frame_var(data: Array) -> void:
	var variable: Dictionary = _decode_stack_variable(data)
	if not _latest_stack_variables.has(_pending_stack_vars_frame):
		_latest_stack_variables[_pending_stack_vars_frame] = []
	_latest_stack_variables[_pending_stack_vars_frame].append(variable)
	_append_captured_message(-1, "stack_frame_var", [variable])

func _on_debug_data(message: String, data: Array) -> void:
	if message == "evaluation_return":
		var variable: Dictionary = _decode_stack_variable(data)
		var expression_name: String = str(variable.get("name", ""))
		if not expression_name.is_empty():
			_latest_evaluations[expression_name] = variable.duplicate(true)
			_evaluation_variables_references.erase(expression_name)
		_append_captured_message(-1, "evaluation_return", [variable])

func _on_breaked(reallydid: bool, can_debug: bool, reason: String, has_stackdump: bool) -> void:
	_append_state_event({
		"state": "breaked" if reallydid else "running",
		"breaked": reallydid,
		"can_debug": can_debug,
		"reason": reason,
		"has_stackdump": has_stackdump
	})
	# Bridge script error break reasons to output events so get_debug_output can capture them
	if reallydid and has_stackdump:
		_append_output_event({
			"category": "stderr",
			"message": reason,
			"file": "",
			"line": 0,
			"function": "",
			"type": 1
		})
func _on_output(message: String, type: int) -> void:
	_append_output_event({
		"category": _map_output_category(type),
		"message": message,
		"type": type
	})

func _on_stopped() -> void:
	_append_state_event({
		"state": "stopped",
		"breaked": false,
		"can_debug": false,
		"reason": "stopped",
		"has_stackdump": false
	})

func _decode_stack_variable(data: Array) -> Dictionary:
	var scope_names: Array[String] = ["local", "member", "global", "constant"]
	var scope_id: int = int(data[1]) if data.size() > 1 else -1
	return {
		"name": str(data[0]) if data.size() > 0 else "",
		"scope": scope_names[scope_id] if scope_id >= 0 and scope_id < scope_names.size() else str(scope_id),
		"type": type_string(int(data[2])) if data.size() > 2 else "",
		"value": data[3] if data.size() > 3 else null,
		"raw": data
	}

func _append_captured_message(session_id: int, message: String, data: Array) -> void:
	_message_sequence += 1
	_captured_messages.append({
		"sequence": _message_sequence,
		"session_id": session_id,
		"message": message,
		"data": data,
		"timestamp": Time.get_unix_time_from_system()
	})
	if _captured_messages.size() > _max_messages:
		_captured_messages = _captured_messages.slice(_captured_messages.size() - _max_messages)

func _append_state_event(event: Dictionary) -> void:
	_message_sequence += 1
	var entry: Dictionary = event.duplicate(true)
	entry["sequence"] = _message_sequence
	entry["timestamp"] = Time.get_unix_time_from_system()
	_state_events.append(entry)
	if _state_events.size() > _max_state_events:
		_state_events = _state_events.slice(_state_events.size() - _max_state_events)

func _append_output_event(event: Dictionary) -> void:
	_message_sequence += 1
	var entry: Dictionary = event.duplicate(true)
	entry["sequence"] = _message_sequence
	entry["timestamp"] = Time.get_unix_time_from_system()
	_output_events.append(entry)
	if _output_events.size() > _max_output_events:
		_output_events = _output_events.slice(_output_events.size() - _max_output_events)

func _map_output_category(type: int) -> String:
	match type:
		0:
			return "stdout"
		1:
			return "stderr"
		2:
			return "stdout_rich"
		_:
			return "stdout"

func _reset_variables_references() -> void:
	_next_variables_reference = 1
	_variable_references.clear()
	_scope_variables_references.clear()
	_evaluation_variables_references.clear()

func _store_variable_reference(entries: Array) -> int:
	var reference: int = _next_variables_reference
	_next_variables_reference += 1
	_variable_references[reference] = entries.duplicate(true)
	return reference

func _build_variable_entry(name: String, value: Variant, value_type: String = "") -> Dictionary:
	var variables_reference: int = _build_nested_variables_reference(value)
	var resolved_type: String = value_type if not value_type.is_empty() else type_string(typeof(value))
	var counts: Dictionary = _describe_child_counts(value)
	return {
		"name": name,
		"type": resolved_type,
		"value": _serialize_debug_value(value),
		"variables_reference": variables_reference,
		"indexed_variables": int(counts.get("indexed_variables", 0)),
		"named_variables": int(counts.get("named_variables", 0)),
		"has_children": variables_reference > 0
	}

func _build_nested_variables_reference(value: Variant) -> int:
	var entries: Array = []
	match typeof(value):
		TYPE_ARRAY:
			entries.append(_build_variable_entry("size", value.size(), "int"))
			for index in range(value.size()):
				entries.append(_build_variable_entry(str(index), value[index]))
		TYPE_DICTIONARY:
			for key in value.keys():
				entries.append(_build_variable_entry(str(key), value[key]))
		TYPE_VECTOR2:
			entries.append_array([
				_build_variable_entry("x", value.x, "float"),
				_build_variable_entry("y", value.y, "float")
			])
		TYPE_VECTOR2I:
			entries.append_array([
				_build_variable_entry("x", value.x, "int"),
				_build_variable_entry("y", value.y, "int")
			])
		TYPE_VECTOR3:
			entries.append_array([
				_build_variable_entry("x", value.x, "float"),
				_build_variable_entry("y", value.y, "float"),
				_build_variable_entry("z", value.z, "float")
			])
		TYPE_VECTOR3I:
			entries.append_array([
				_build_variable_entry("x", value.x, "int"),
				_build_variable_entry("y", value.y, "int"),
				_build_variable_entry("z", value.z, "int")
			])
		TYPE_VECTOR4:
			entries.append_array([
				_build_variable_entry("x", value.x, "float"),
				_build_variable_entry("y", value.y, "float"),
				_build_variable_entry("z", value.z, "float"),
				_build_variable_entry("w", value.w, "float")
			])
		TYPE_VECTOR4I:
			entries.append_array([
				_build_variable_entry("x", value.x, "int"),
				_build_variable_entry("y", value.y, "int"),
				_build_variable_entry("z", value.z, "int"),
				_build_variable_entry("w", value.w, "int")
			])
		TYPE_PROJECTION:
			entries.append_array([
				_build_variable_entry("x", value.x, "Vector4"),
				_build_variable_entry("y", value.y, "Vector4"),
				_build_variable_entry("z", value.z, "Vector4"),
				_build_variable_entry("w", value.w, "Vector4")
			])
		TYPE_PLANE:
			entries.append_array([
				_build_variable_entry("normal", value.normal, "Vector3"),
				_build_variable_entry("d", value.d, "float")
			])
		TYPE_RECT2:
			entries.append_array([
				_build_variable_entry("position", value.position, "Vector2"),
				_build_variable_entry("size", value.size, "Vector2"),
				_build_variable_entry("end", value.end, "Vector2")
			])
		TYPE_RECT2I:
			entries.append_array([
				_build_variable_entry("position", value.position, "Vector2i"),
				_build_variable_entry("size", value.size, "Vector2i"),
				_build_variable_entry("end", value.end, "Vector2i")
			])
		TYPE_AABB:
			entries.append_array([
				_build_variable_entry("position", value.position, "Vector3"),
				_build_variable_entry("size", value.size, "Vector3"),
				_build_variable_entry("end", value.end, "Vector3")
			])
		TYPE_BASIS:
			entries.append_array([
				_build_variable_entry("x", value.x, "Vector3"),
				_build_variable_entry("y", value.y, "Vector3"),
				_build_variable_entry("z", value.z, "Vector3")
			])
		TYPE_COLOR:
			entries.append_array([
				_build_variable_entry("r", value.r, "float"),
				_build_variable_entry("g", value.g, "float"),
				_build_variable_entry("b", value.b, "float"),
				_build_variable_entry("a", value.a, "float")
			])
		TYPE_QUATERNION:
			entries.append_array([
				_build_variable_entry("x", value.x, "float"),
				_build_variable_entry("y", value.y, "float"),
				_build_variable_entry("z", value.z, "float"),
				_build_variable_entry("w", value.w, "float")
			])
		TYPE_TRANSFORM2D:
			entries.append_array([
				_build_variable_entry("x", value.x, "Vector2"),
				_build_variable_entry("y", value.y, "Vector2"),
				_build_variable_entry("origin", value.origin, "Vector2")
			])
		TYPE_TRANSFORM3D:
			entries.append_array([
				_build_variable_entry("basis", value.basis, "Basis"),
				_build_variable_entry("origin", value.origin, "Vector3")
			])
		TYPE_OBJECT:
			entries = _build_object_variable_entries(value)
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			entries.append(_build_variable_entry("size", value.size(), "int"))
			for index in range(value.size()):
				entries.append(_build_variable_entry(str(index), value[index]))
	if entries.is_empty():
		return 0
	return _store_variable_reference(entries)

func _describe_child_counts(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_ARRAY:
			return {"indexed_variables": value.size() + 1, "named_variables": 0}
		TYPE_DICTIONARY:
			return {"indexed_variables": 0, "named_variables": value.size()}
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return {"indexed_variables": 0, "named_variables": 2}
		TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_RECT2, TYPE_RECT2I, TYPE_AABB, TYPE_BASIS:
			return {"indexed_variables": 0, "named_variables": 3}
		TYPE_PLANE, TYPE_TRANSFORM3D:
			return {"indexed_variables": 0, "named_variables": 2}
		TYPE_TRANSFORM2D:
			return {"indexed_variables": 0, "named_variables": 3}
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PROJECTION, TYPE_COLOR, TYPE_QUATERNION:
			return {"indexed_variables": 0, "named_variables": 4}
		TYPE_OBJECT:
			return {"indexed_variables": 0, "named_variables": _build_object_variable_entries(value).size()}
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return {"indexed_variables": value.size() + 1, "named_variables": 0}
		_:
			return {"indexed_variables": 0, "named_variables": 0}

func _serialize_debug_value(value: Variant) -> Variant:
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
			return _serialize_debug_callable(value)
		TYPE_SIGNAL:
			return _serialize_debug_signal(value)
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
				"x": _serialize_debug_value(value.x),
				"y": _serialize_debug_value(value.y),
				"z": _serialize_debug_value(value.z),
				"w": _serialize_debug_value(value.w)
			}
		TYPE_PLANE:
			return {
				"normal": _serialize_debug_value(value.normal),
				"d": value.d
			}
		TYPE_RECT2:
			return {
				"position": _serialize_debug_value(value.position),
				"size": _serialize_debug_value(value.size),
				"end": _serialize_debug_value(value.end)
			}
		TYPE_RECT2I:
			return {
				"position": _serialize_debug_value(value.position),
				"size": _serialize_debug_value(value.size),
				"end": _serialize_debug_value(value.end)
			}
		TYPE_AABB:
			return {
				"position": _serialize_debug_value(value.position),
				"size": _serialize_debug_value(value.size),
				"end": _serialize_debug_value(value.end)
			}
		TYPE_BASIS:
			return {
				"x": _serialize_debug_value(value.x),
				"y": _serialize_debug_value(value.y),
				"z": _serialize_debug_value(value.z)
			}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_QUATERNION:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_TRANSFORM2D:
			return {
				"x": _serialize_debug_value(value.x),
				"y": _serialize_debug_value(value.y),
				"origin": _serialize_debug_value(value.origin)
			}
		TYPE_TRANSFORM3D:
			return {
				"basis": _serialize_debug_value(value.basis),
				"origin": _serialize_debug_value(value.origin)
			}
		TYPE_OBJECT:
			return _serialize_debug_object(value)
		TYPE_ARRAY:
			var serialized_array: Array = []
			for item in value:
				serialized_array.append(_serialize_debug_value(item))
			return serialized_array
		TYPE_DICTIONARY:
			var serialized_dict: Dictionary = {}
			for key in value.keys():
				serialized_dict[str(key)] = _serialize_debug_value(value[key])
			return serialized_dict
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			var packed_array: Array = []
			for item in value:
				packed_array.append(_serialize_debug_value(item))
			return packed_array
		_:
			return str(value)

func _build_object_variable_entries(value: Variant) -> Array:
	if typeof(value) != TYPE_OBJECT or value == null:
		return []
	var object_value: Object = value
	if not is_instance_valid(object_value):
		return []
	var entries: Array = []
	var seen: Dictionary = {}
	entries.append(_build_variable_entry("@class_name", object_value.get_class(), "String"))
	entries.append(_build_variable_entry("@instance_id", object_value.get_instance_id(), "int"))
	var script: Script = object_value.get_script() as Script
	entries.append(_build_variable_entry("@script_path", String(script.resource_path) if script else "", "String"))
	if object_value is Node:
		var node_value: Node = object_value as Node
		var node_path: String = str(node_value.get_path())
		if node_path.is_empty() and not String(node_value.name).is_empty():
			node_path = "/" + String(node_value.name)
		entries.append(_build_variable_entry("@node_path", node_path, "NodePath"))
	elif object_value is Resource:
		entries.append(_build_variable_entry("@resource_path", String((object_value as Resource).resource_path), "String"))
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
		entries.append(_build_variable_entry(property_name, object_value.get(property_name)))
	return entries

func _serialize_debug_object(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_OBJECT or value == null:
		return {}
	var object_value: Object = value
	if not is_instance_valid(object_value):
		return {"class_name": "<freed>"}
	var properties: Dictionary = {}
	for entry in _build_object_variable_entries(object_value):
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

func _serialize_debug_callable(value: Variant) -> Dictionary:
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

func _serialize_debug_signal(value: Variant) -> Dictionary:
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

func _find_captured_message_after_sequence(sequence: int, response_messages: Array, error_messages: Array) -> Dictionary:
	for entry in _captured_messages:
		if int(entry.get("sequence", 0)) <= sequence:
			continue
		var message: String = str(entry.get("message", ""))
		if response_messages.has(message) or error_messages.has(message):
			return entry
	return {}

func _extract_runtime_error(payload: Variant) -> String:
	if payload is Dictionary:
		return str(payload.get("message", payload))
	return str(payload)

func _payload_matches(payload: Variant, match_fields: Dictionary) -> bool:
	if match_fields.is_empty():
		return true
	if not (payload is Dictionary):
		return false
	for key in match_fields:
		if payload.get(key) != match_fields[key]:
			return false
	return true

func _for_each_session(session_id: int, action: Callable, require_active: bool = false) -> Dictionary:
	var sessions: Array = get_sessions()
	if sessions.is_empty():
		return {"status": "no_sessions", "sessions_updated": 0}
	if session_id >= 0:
		var session: EditorDebuggerSession = get_session(session_id)
		if not session:
			return {"error": "Debugger session not found: " + str(session_id)}
		if require_active and not session.is_active():
			return {"status": "no_active_sessions", "sessions_updated": 0}
		action.call(session)
		return {"status": "success", "sessions_updated": 1}
	var updated: int = 0
	for session in sessions:
		if session and (not require_active or session.is_active()):
			action.call(session)
			updated += 1
	if require_active and updated == 0:
		return {"status": "no_active_sessions", "sessions_updated": 0}
	return {"status": "success", "sessions_updated": updated}
