extends Node

const CAPTURE_PREFIX: StringName = &"mcp"
var _capture_registered: bool = false
var _probe_ready_sent: bool = false

func _ready() -> void:
	_ensure_debugger_capture_registered()
	set_process(not _capture_registered)

func _process(_delta: float) -> void:
	if _capture_registered:
		set_process(false)
		return
	_ensure_debugger_capture_registered()
	if _capture_registered:
		set_process(false)

func _exit_tree() -> void:
	if EngineDebugger.is_active() and EngineDebugger.has_capture(CAPTURE_PREFIX):
		EngineDebugger.unregister_message_capture(CAPTURE_PREFIX)
	_capture_registered = false

func _ensure_debugger_capture_registered() -> void:
	if _capture_registered:
		if EngineDebugger.is_active() and not _probe_ready_sent:
			EngineDebugger.send_message("mcp:probe_ready", [_get_runtime_info()])
			_probe_ready_sent = true
		return
	if not EngineDebugger.is_active():
		return
	if EngineDebugger.has_capture(CAPTURE_PREFIX):
		EngineDebugger.unregister_message_capture(CAPTURE_PREFIX)
	EngineDebugger.register_message_capture(CAPTURE_PREFIX, Callable(self, "_capture_mcp_message"))
	_capture_registered = true
	if not _probe_ready_sent:
		EngineDebugger.send_message("mcp:probe_ready", [_get_runtime_info()])
		_probe_ready_sent = true

func _capture_mcp_message(message: String, data: Array) -> bool:
	match message:
		"ping":
			EngineDebugger.send_message("mcp:pong", [_get_runtime_info()])
			return true
		"get_runtime_info":
			EngineDebugger.send_message("mcp:runtime_info", [_get_runtime_info()])
			return true
		"get_performance_snapshot":
			EngineDebugger.send_message("mcp:performance_snapshot", [_get_performance_snapshot()])
			return true
		"get_memory_trend":
			return _handle_get_memory_trend(data)
		"get_scene_tree":
			var max_depth: int = 6
			if not data.is_empty() and data[0] is int:
				max_depth = data[0]
			var root: Node = get_tree().current_scene
			if not root:
				root = get_tree().root
			EngineDebugger.send_message("mcp:scene_tree", [_serialize_node(root, 0, max_depth)])
			return true
		"inspect_node":
			if data.is_empty():
				EngineDebugger.send_message("mcp:error", [{"message": "inspect_node requires a NodePath string"}])
				return true
			var node: Node = _resolve_target_node(str(data[0]))
			if not node:
				EngineDebugger.send_message("mcp:error", [{"message": "Node not found: " + str(data[0])}])
				return true
			EngineDebugger.send_message("mcp:node", [_serialize_node(node, 0, 1, true)])
			return true
		"create_node":
			return _handle_create_node(data)
		"delete_node":
			return _handle_delete_node(data)
		"set_node_property":
			return _handle_set_node_property(data)
		"call_node_method":
			return _handle_call_node_method(data)
		"evaluate_expression":
			return _handle_evaluate_expression(data)
		"simulate_input_event":
			return _handle_simulate_input_event(data)
		"simulate_input_action":
			return _handle_simulate_input_action(data)
		"list_input_actions":
			return _handle_list_input_actions(data)
		"upsert_input_action":
			return _handle_upsert_input_action(data)
		"remove_input_action":
			return _handle_remove_input_action(data)
		"list_animations":
			return _handle_list_animations(data)
		"play_animation":
			return _handle_play_animation(data)
		"stop_animation":
			return _handle_stop_animation(data)
		"get_animation_state":
			return _handle_get_animation_state(data)
		"get_animation_tree_state":
			return _handle_get_animation_tree_state(data)
		"set_animation_tree_active":
			return _handle_set_animation_tree_active(data)
		"travel_animation_tree":
			return _handle_travel_animation_tree(data)
		"get_material_state":
			return _handle_get_material_state(data)
		"get_theme_item":
			return _handle_get_theme_item(data)
		"set_theme_override":
			return _handle_set_theme_override(data)
		"clear_theme_override":
			return _handle_clear_theme_override(data)
		"get_shader_parameters":
			return _handle_get_shader_parameters(data)
		"set_shader_parameter":
			return _handle_set_shader_parameter(data)
		"list_tilemap_layers":
			return _handle_list_tilemap_layers(data)
		"get_tilemap_cell":
			return _handle_get_tilemap_cell(data)
		"set_tilemap_cell":
			return _handle_set_tilemap_cell(data)
		"list_audio_buses":
			return _handle_list_audio_buses(data)
		"get_audio_bus":
			return _handle_get_audio_bus(data)
		"update_audio_bus":
			return _handle_update_audio_bus(data)
		"get_runtime_screenshot":
			return _handle_get_runtime_screenshot(data)
		"debug_break":
			EngineDebugger.debug(true, false)
			return true
		_:
			return false

func _get_runtime_info() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"physics_frames": Engine.get_physics_frames(),
		"process_frames": Engine.get_process_frames(),
		"debugger_active": EngineDebugger.is_active(),
		"current_scene": str(get_tree().current_scene.get_path()) if get_tree().current_scene else "",
		"node_count": _count_nodes(get_tree().root)
	}

func _get_performance_snapshot() -> Dictionary:
	var memory_static: float = float(Performance.get_monitor(Performance.MEMORY_STATIC))
	return {
		"fps": float(Performance.get_monitor(Performance.TIME_FPS)),
		"frame_time_sec": float(Performance.get_monitor(Performance.TIME_PROCESS)),
		"physics_frame_time_sec": float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"rendered_objects_in_frame": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"memory_static_bytes": int(memory_static),
		"memory_static_mb": memory_static / 1024.0 / 1024.0,
		"current_scene": str(get_tree().current_scene.get_path()) if get_tree().current_scene else "",
		"node_count": _count_nodes(get_tree().root)
	}

func _get_memory_sample(sample_index: int) -> Dictionary:
	var memory_static: float = float(Performance.get_monitor(Performance.MEMORY_STATIC))
	return {
		"sample_index": sample_index,
		"timestamp_ms": Time.get_ticks_msec(),
		"memory_static_bytes": int(memory_static),
		"memory_static_mb": memory_static / 1024.0 / 1024.0,
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	}

func _handle_get_memory_trend(data: Array) -> bool:
	var sample_count: int = 5
	var sample_interval_ms: int = 100
	if data.size() > 0:
		sample_count = max(int(data[0]), 1)
	if data.size() > 1:
		sample_interval_ms = max(int(data[1]), 0)
	var samples: Array = []
	for sample_index in range(sample_count):
		samples.append(_get_memory_sample(sample_index))
		if sample_index < sample_count - 1 and sample_interval_ms > 0:
			OS.delay_msec(sample_interval_ms)

	var first_sample: Dictionary = samples[0] if not samples.is_empty() else {}
	var last_sample: Dictionary = samples[samples.size() - 1] if not samples.is_empty() else {}
	var first_bytes: int = int(first_sample.get("memory_static_bytes", 0))
	var last_bytes: int = int(last_sample.get("memory_static_bytes", 0))
	var first_objects: int = int(first_sample.get("object_count", 0))
	var last_objects: int = int(last_sample.get("object_count", 0))
	var first_resources: int = int(first_sample.get("resource_count", 0))
	var last_resources: int = int(last_sample.get("resource_count", 0))

	EngineDebugger.send_message("mcp:memory_trend", [{
		"sample_count": sample_count,
		"sample_interval_ms": sample_interval_ms,
		"memory_static_delta_bytes": last_bytes - first_bytes,
		"object_count_delta": last_objects - first_objects,
		"resource_count_delta": last_resources - first_resources,
		"current_scene": str(get_tree().current_scene.get_path()) if get_tree().current_scene else "",
		"samples": samples
	}])
	return true

func _serialize_node(node: Node, depth: int, max_depth: int, include_properties: bool = false) -> Dictionary:
	var result: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"child_count": node.get_child_count()
	}
	if include_properties:
		result["properties"] = _serialize_properties(node)
	if max_depth >= 0 and depth >= max_depth:
		return result
	var children: Array[Dictionary] = []
	for child in node.get_children():
		children.append(_serialize_node(child, depth + 1, max_depth))
	result["children"] = children
	return result

func _serialize_properties(node: Node) -> Dictionary:
	var properties: Dictionary = {}
	for property in node.get_property_list():
		var name: String = property.get("name", "")
		var usage: int = property.get("usage", 0)
		if name.begins_with("_") \
				or (usage & PROPERTY_USAGE_CATEGORY) != 0 \
				or (usage & PROPERTY_USAGE_GROUP) != 0 \
				or (usage & PROPERTY_USAGE_SUBGROUP) != 0:
			continue
		var value: Variant = node.get(name)
		match typeof(value):
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
				properties[name] = value
			TYPE_VECTOR2:
				properties[name] = {"x": value.x, "y": value.y}
			TYPE_VECTOR3:
				properties[name] = {"x": value.x, "y": value.y, "z": value.z}
			TYPE_COLOR:
				properties[name] = {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
			_:
				properties[name] = _serialize_value(value)
	return properties

func _handle_set_node_property(data: Array) -> bool:
	if data.size() < 3:
		EngineDebugger.send_message("mcp:error", [{"message": "set_node_property requires node_path, property_name, property_value"}])
		return true
	var node: Node = _resolve_target_node(str(data[0]))
	if not node:
		EngineDebugger.send_message("mcp:error", [{"message": "Node not found: " + str(data[0])}])
		return true
	var property_name: String = str(data[1])
	if not property_name in node:
		EngineDebugger.send_message("mcp:error", [{"message": "Property not found on node: " + property_name}])
		return true
	var old_value: Variant = node.get(property_name)
	var converted_value: Variant = _convert_value_for_property(node, property_name, data[2])
	node.set(property_name, converted_value)
	EngineDebugger.send_message("mcp:node_property_updated", [{
		"node_path": str(node.get_path()),
		"property_name": property_name,
		"old_value": _serialize_value(old_value),
		"new_value": _serialize_value(node.get(property_name))
	}])
	return true

func _handle_create_node(data: Array) -> bool:
	if data.size() < 3:
		EngineDebugger.send_message("mcp:error", [{"message": "create_node requires parent_path, node_type, node_name"}])
		return true
	var parent_path: String = str(data[0])
	var node_type: String = str(data[1])
	var node_name: String = str(data[2])
	var parent: Node = _resolve_target_node(parent_path)
	if not parent:
		EngineDebugger.send_message("mcp:error", [{"message": "Parent node not found: " + parent_path}])
		return true
	if node_type.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "node_type cannot be empty"}])
		return true
	if node_name.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "node_name cannot be empty"}])
		return true
	if not ClassDB.class_exists(node_type):
		EngineDebugger.send_message("mcp:error", [{"message": "Invalid node type: " + node_type}])
		return true
	if not ClassDB.is_parent_class(node_type, "Node"):
		EngineDebugger.send_message("mcp:error", [{"message": "Class is not a Node type: " + node_type}])
		return true
	var node_instance: Variant = ClassDB.instantiate(node_type)
	if not (node_instance is Node):
		EngineDebugger.send_message("mcp:error", [{"message": "Failed to instantiate node type: " + node_type}])
		return true
	var node: Node = node_instance
	node.name = node_name
	parent.add_child(node)
	EngineDebugger.send_message("mcp:runtime_node_created", [{
		"parent_path": str(parent.get_path()),
		"node_path": str(node.get_path()),
		"node_type": node.get_class(),
		"node_name": String(node.name)
	}])
	return true

func _handle_delete_node(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "delete_node requires node_path"}])
		return true
	var node_path: String = str(data[0])
	var node: Node = _resolve_target_node(node_path)
	if not node:
		EngineDebugger.send_message("mcp:error", [{"message": "Node not found: " + node_path}])
		return true
	if node == get_tree().root:
		EngineDebugger.send_message("mcp:error", [{"message": "Cannot delete the SceneTree root"}])
		return true
	if node == get_tree().current_scene:
		EngineDebugger.send_message("mcp:error", [{"message": "Cannot delete the active runtime scene root"}])
		return true
	if _is_protected_runtime_node(node):
		EngineDebugger.send_message("mcp:error", [{"message": "Cannot delete the MCPRuntimeProbe node while the runtime session is active"}])
		return true
	var deleted_path: String = str(node.get_path())
	var deleted_type: String = node.get_class()
	var parent: Node = node.get_parent()
	if parent:
		parent.remove_child(node)
	node.queue_free()
	EngineDebugger.send_message("mcp:runtime_node_deleted", [{
		"node_path": deleted_path,
		"node_type": deleted_type
	}])
	return true

func _is_protected_runtime_node(node: Node) -> bool:
	return node == self

func _handle_call_node_method(data: Array) -> bool:
	if data.size() < 2:
		EngineDebugger.send_message("mcp:error", [{"message": "call_node_method requires node_path and method_name"}])
		return true
	var node: Node = _resolve_target_node(str(data[0]))
	if not node:
		EngineDebugger.send_message("mcp:error", [{"message": "Node not found: " + str(data[0])}])
		return true
	var method_name: String = str(data[1])
	if not node.has_method(method_name):
		EngineDebugger.send_message("mcp:error", [{"message": "Method not found on node: " + method_name}])
		return true
	var arguments: Array = []
	if data.size() >= 3 and data[2] is Array:
		arguments = data[2]
	var result: Variant = node.callv(method_name, arguments)
	EngineDebugger.send_message("mcp:node_method_result", [{
		"node_path": str(node.get_path()),
		"method_name": method_name,
		"arguments": _serialize_value(arguments),
		"result": _serialize_value(result)
	}])
	return true

func _handle_evaluate_expression(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "evaluate_expression requires an expression string"}])
		return true
	var expression_text: String = str(data[0])
	var node_path: String = ""
	if data.size() >= 2:
		node_path = str(data[1])
	var base_instance: Object = _resolve_target_node(node_path)
	if not base_instance:
		base_instance = get_tree().current_scene if get_tree().current_scene else self
	var expression: Expression = Expression.new()
	var parse_error: int = expression.parse(expression_text, [])
	if parse_error != OK:
		EngineDebugger.send_message("mcp:error", [{
			"message": "Expression parse failed",
			"code": parse_error,
			"expression": expression_text
		}])
		return true
	var result: Variant = expression.execute([], base_instance, false)
	if expression.has_execute_failed():
		EngineDebugger.send_message("mcp:error", [{
			"message": "Expression execution failed",
			"expression": expression_text
		}])
		return true
	EngineDebugger.send_message("mcp:expression_result", [{
		"expression": expression_text,
		"node_path": str(base_instance.get_path()) if base_instance is Node else "",
		"value": _serialize_value(result)
	}])
	return true

func _handle_get_runtime_screenshot(data: Array) -> bool:
	var save_path: String = "user://mcp_runtime_capture.png"
	if not data.is_empty() and data[0] is String and not String(data[0]).is_empty():
		save_path = String(data[0])
	var format: String = "png"
	if data.size() >= 2 and data[1] is String and not String(data[1]).is_empty():
		format = String(data[1]).to_lower()
	var viewport_path: String = ""
	if data.size() >= 3 and data[2] is String and not String(data[2]).is_empty():
		viewport_path = String(data[2])
	var result: Dictionary = capture_runtime_screenshot(save_path, format, viewport_path)
	if result.has("error"):
		EngineDebugger.send_message("mcp:error", [result])
		return true
	EngineDebugger.send_message("mcp:runtime_screenshot", [result])
	return true

func _handle_simulate_input_action(data: Array) -> bool:
	if data.is_empty() or not data[0] is String or String(data[0]).is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "simulate_input_action requires a non-empty action name"}])
		return true
	var action_name: String = String(data[0])
	var pressed: bool = bool(data[1]) if data.size() >= 2 else true
	var strength: float = float(data[2]) if data.size() >= 3 else (1.0 if pressed else 0.0)
	var action: StringName = StringName(action_name)
	var action_exists: bool = InputMap.has_action(action)

	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = strength
	Input.parse_input_event(event)

	EngineDebugger.send_message("mcp:input_action_simulated", [{
		"action_name": action_name,
		"action_exists": action_exists,
		"pressed": pressed,
		"strength": strength,
		"runtime_pressed": Input.is_action_pressed(action)
	}])
	return true

func _handle_simulate_input_event(data: Array) -> bool:
	if data.is_empty() or not data[0] is Dictionary:
		EngineDebugger.send_message("mcp:error", [{"message": "simulate_input_event requires an event dictionary"}])
		return true
	var payload: Dictionary = data[0]
	var event: InputEvent = _build_input_event(payload)
	if not event:
		EngineDebugger.send_message("mcp:error", [{"message": "Unsupported or invalid input event payload", "payload": payload}])
		return true
	Input.parse_input_event(event)
	EngineDebugger.send_message("mcp:input_event_simulated", [_serialize_input_event(event)])
	return true

func _handle_list_input_actions(data: Array) -> bool:
	var action_filter: String = ""
	if not data.is_empty():
		action_filter = str(data[0])
	var actions: PackedStringArray = InputMap.get_actions()
	var results: Array = []
	for action_name in actions:
		var action_text: String = str(action_name)
		if not action_filter.is_empty() and action_text != action_filter:
			continue
		var events: Array = []
		for event in InputMap.action_get_events(action_name):
			events.append(_serialize_input_event(event))
		results.append({
			"action_name": action_text,
			"deadzone": InputMap.action_get_deadzone(action_name),
			"event_count": events.size(),
			"events": events
		})
	results.sort_custom(Callable(self, "_sort_input_action_entries"))
	EngineDebugger.send_message("mcp:input_actions", [{
		"actions": results,
		"count": results.size(),
		"filter": action_filter
	}])
	return true

func _handle_upsert_input_action(data: Array) -> bool:
	if data.is_empty() or not data[0] is String or String(data[0]).is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "upsert_input_action requires a non-empty action name"}])
		return true
	var action_name_text: String = String(data[0])
	var action_name: StringName = StringName(action_name_text)
	var deadzone: float = float(data[1]) if data.size() >= 2 else 0.5
	var erase_existing: bool = bool(data[2]) if data.size() >= 3 else false
	var event_payloads: Array = data[3] if data.size() >= 4 and data[3] is Array else []
	var existed_before: bool = InputMap.has_action(action_name)

	if not existed_before:
		InputMap.add_action(action_name, deadzone)
	else:
		InputMap.action_set_deadzone(action_name, deadzone)
		if erase_existing:
			for existing_event in InputMap.action_get_events(action_name):
				InputMap.action_erase_event(action_name, existing_event)

	var added_events: Array = []
	for payload in event_payloads:
		if not (payload is Dictionary):
			EngineDebugger.send_message("mcp:error", [{"message": "Input action events must be dictionaries", "action_name": action_name_text}])
			return true
		var event: InputEvent = _build_input_event(payload)
		if not event:
			EngineDebugger.send_message("mcp:error", [{"message": "Unsupported input action event payload", "action_name": action_name_text, "payload": payload}])
			return true
		InputMap.action_add_event(action_name, event)
		added_events.append(_serialize_input_event(event))

	var all_events: Array = []
	for stored_event in InputMap.action_get_events(action_name):
		all_events.append(_serialize_input_event(stored_event))
	EngineDebugger.send_message("mcp:input_action_updated", [{
		"action_name": action_name_text,
		"existed_before": existed_before,
		"deadzone": InputMap.action_get_deadzone(action_name),
		"event_count": all_events.size(),
		"events": all_events,
		"added_events": added_events
	}])
	return true

func _handle_remove_input_action(data: Array) -> bool:
	if data.is_empty() or not data[0] is String or String(data[0]).is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "remove_input_action requires a non-empty action name"}])
		return true
	var action_name_text: String = String(data[0])
	var action_name: StringName = StringName(action_name_text)
	if not InputMap.has_action(action_name):
		EngineDebugger.send_message("mcp:error", [{"message": "Input action not found: " + action_name_text}])
		return true
	var event_count: int = InputMap.action_get_events(action_name).size()
	InputMap.erase_action(action_name)
	EngineDebugger.send_message("mcp:input_action_removed", [{
		"action_name": action_name_text,
		"removed": true,
		"event_count": event_count
	}])
	return true

func _handle_list_animations(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "list_animations requires node_path"}])
		return true
	var player: AnimationPlayer = _resolve_animation_player(str(data[0]))
	if not player:
		return true
	var animations: PackedStringArray = player.get_animation_list()
	var entries: Array = []
	for animation_name in animations:
		var animation: Animation = player.get_animation(animation_name)
		entries.append({
			"name": str(animation_name),
			"length": animation.length if animation else 0.0,
			"track_count": animation.get_track_count() if animation else 0
		})
	entries.sort_custom(Callable(self, "_sort_animation_entries"))
	EngineDebugger.send_message("mcp:animation_list", [{
		"node_path": str(player.get_path()),
		"animations": entries,
		"count": entries.size()
	}])
	return true

func _handle_play_animation(data: Array) -> bool:
	if data.size() < 2:
		EngineDebugger.send_message("mcp:error", [{"message": "play_animation requires node_path and animation_name"}])
		return true
	var player: AnimationPlayer = _resolve_animation_player(str(data[0]))
	if not player:
		return true
	var animation_name: String = str(data[1])
	if animation_name.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "animation_name cannot be empty"}])
		return true
	if not player.has_animation(animation_name):
		EngineDebugger.send_message("mcp:error", [{"message": "Animation not found: " + animation_name, "node_path": str(player.get_path())}])
		return true
	var custom_blend: float = float(data[2]) if data.size() >= 3 else -1.0
	var custom_speed: float = float(data[3]) if data.size() >= 4 else 1.0
	var from_end: bool = bool(data[4]) if data.size() >= 5 else false
	player.play(StringName(animation_name), custom_blend, custom_speed, from_end)
	EngineDebugger.send_message("mcp:animation_started", [_serialize_animation_state(player)])
	return true

func _handle_stop_animation(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "stop_animation requires node_path"}])
		return true
	var player: AnimationPlayer = _resolve_animation_player(str(data[0]))
	if not player:
		return true
	var keep_state: bool = bool(data[1]) if data.size() >= 2 else false
	player.stop(keep_state)
	EngineDebugger.send_message("mcp:animation_stopped", [_serialize_animation_state(player)])
	return true

func _handle_get_animation_state(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "get_animation_state requires node_path"}])
		return true
	var player: AnimationPlayer = _resolve_animation_player(str(data[0]))
	if not player:
		return true
	EngineDebugger.send_message("mcp:animation_state", [_serialize_animation_state(player)])
	return true

func _handle_get_animation_tree_state(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "get_animation_tree_state requires node_path"}])
		return true
	var animation_tree: AnimationTree = _resolve_animation_tree(str(data[0]))
	if not animation_tree:
		return true
	EngineDebugger.send_message("mcp:animation_tree_state", [_serialize_animation_tree_state(animation_tree)])
	return true

func _handle_set_animation_tree_active(data: Array) -> bool:
	if data.size() < 2:
		EngineDebugger.send_message("mcp:error", [{"message": "set_animation_tree_active requires node_path and active"}])
		return true
	var animation_tree: AnimationTree = _resolve_animation_tree(str(data[0]))
	if not animation_tree:
		return true
	animation_tree.active = bool(data[1])
	EngineDebugger.send_message("mcp:animation_tree_active_updated", [_serialize_animation_tree_state(animation_tree)])
	return true

func _handle_travel_animation_tree(data: Array) -> bool:
	if data.size() < 2:
		EngineDebugger.send_message("mcp:error", [{"message": "travel_animation_tree requires node_path and state_name"}])
		return true
	var animation_tree: AnimationTree = _resolve_animation_tree(str(data[0]))
	if not animation_tree:
		return true
	var state_name: String = str(data[1])
	if state_name.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "state_name cannot be empty"}])
		return true
	var playback: Variant = animation_tree.get("parameters/playback")
	if playback == null or not playback.has_method("travel"):
		EngineDebugger.send_message("mcp:error", [{
			"message": "AnimationTree does not expose a state machine playback object",
			"node_path": str(animation_tree.get_path()),
			"tree_root_type": animation_tree.tree_root.get_class() if animation_tree.tree_root else ""
		}])
		return true
	playback.travel(state_name)
	EngineDebugger.send_message("mcp:animation_tree_travelled", [_serialize_animation_tree_state(animation_tree)])
	return true

func _handle_get_material_state(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "get_material_state requires node_path"}])
		return true
	var resolution: Dictionary = _resolve_material_binding(str(data[0]), str(data[1]) if data.size() >= 2 else "auto", int(data[2]) if data.size() >= 3 else 0)
	if resolution.has("error"):
		EngineDebugger.send_message("mcp:error", [resolution])
		return true
	EngineDebugger.send_message("mcp:material_state", [_serialize_material_state(resolution)])
	return true

func _handle_get_theme_item(data: Array) -> bool:
	if data.size() < 3:
		EngineDebugger.send_message("mcp:error", [{"message": "get_theme_item requires node_path, item_type, and item_name"}])
		return true
	var control: Control = _resolve_control_node(str(data[0]))
	if not control:
		return true
	var item_type: String = str(data[1]).strip_edges().to_lower()
	var item_name: String = str(data[2]).strip_edges()
	var theme_type: String = str(data[3]) if data.size() >= 4 else ""
	var result: Dictionary = _resolve_theme_item(control, item_type, item_name, theme_type)
	if result.has("error"):
		EngineDebugger.send_message("mcp:error", [result])
		return true
	EngineDebugger.send_message("mcp:theme_item", [result])
	return true

func _handle_set_theme_override(data: Array) -> bool:
	if data.size() < 4:
		EngineDebugger.send_message("mcp:error", [{"message": "set_theme_override requires node_path, item_type, item_name, and value"}])
		return true
	var control: Control = _resolve_control_node(str(data[0]))
	if not control:
		return true
	var item_type: String = str(data[1]).strip_edges().to_lower()
	var item_name: String = str(data[2]).strip_edges()
	var override_value: Variant = _convert_theme_override_value(item_type, data[3])
	if override_value == null and item_type in ["font", "stylebox", "icon"]:
		EngineDebugger.send_message("mcp:error", [{"message": "Failed to resolve resource override value", "item_type": item_type, "item_name": item_name}])
		return true
	var apply_error: String = _apply_theme_override(control, item_type, item_name, override_value)
	if not apply_error.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": apply_error, "item_type": item_type, "item_name": item_name}])
		return true
	var theme_type: String = str(data[4]) if data.size() >= 5 else ""
	var result: Dictionary = _resolve_theme_item(control, item_type, item_name, theme_type)
	if result.has("error"):
		EngineDebugger.send_message("mcp:error", [result])
		return true
	EngineDebugger.send_message("mcp:theme_override_updated", [result])
	return true

func _handle_clear_theme_override(data: Array) -> bool:
	if data.size() < 3:
		EngineDebugger.send_message("mcp:error", [{"message": "clear_theme_override requires node_path, item_type, and item_name"}])
		return true
	var control: Control = _resolve_control_node(str(data[0]))
	if not control:
		return true
	var item_type: String = str(data[1]).strip_edges().to_lower()
	var item_name: String = str(data[2]).strip_edges()
	var clear_error: String = _remove_theme_override(control, item_type, item_name)
	if not clear_error.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": clear_error, "item_type": item_type, "item_name": item_name}])
		return true
	var theme_type: String = str(data[3]) if data.size() >= 4 else ""
	var result: Dictionary = _resolve_theme_item(control, item_type, item_name, theme_type)
	if result.has("error"):
		EngineDebugger.send_message("mcp:error", [result])
		return true
	EngineDebugger.send_message("mcp:theme_override_cleared", [result])
	return true

func _handle_get_shader_parameters(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "get_shader_parameters requires node_path"}])
		return true
	var resolution: Dictionary = _resolve_material_binding(str(data[0]), str(data[1]) if data.size() >= 2 else "auto", int(data[2]) if data.size() >= 3 else 0)
	if resolution.has("error"):
		EngineDebugger.send_message("mcp:error", [resolution])
		return true
	var material: Material = resolution.get("material")
	if not (material is ShaderMaterial):
		EngineDebugger.send_message("mcp:error", [{
			"message": "Resolved material is not a ShaderMaterial",
			"node_path": str(resolution.get("node_path", "")),
			"material_class": material.get_class() if material else ""
		}])
		return true
	EngineDebugger.send_message("mcp:shader_parameters", [_serialize_shader_parameters(resolution, material)])
	return true

func _handle_set_shader_parameter(data: Array) -> bool:
	if data.size() < 3:
		EngineDebugger.send_message("mcp:error", [{"message": "set_shader_parameter requires node_path, parameter_name, value, and optional material_target/surface_index"}])
		return true
	var resolution: Dictionary = _resolve_material_binding(str(data[0]), str(data[3]) if data.size() >= 4 else "auto", int(data[4]) if data.size() >= 5 else 0)
	if resolution.has("error"):
		EngineDebugger.send_message("mcp:error", [resolution])
		return true
	var material: Material = resolution.get("material")
	if not (material is ShaderMaterial):
		EngineDebugger.send_message("mcp:error", [{
			"message": "Resolved material is not a ShaderMaterial",
			"node_path": str(resolution.get("node_path", "")),
			"material_class": material.get_class() if material else ""
		}])
		return true
	var parameter_name: String = str(data[1])
	if parameter_name.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "parameter_name cannot be empty"}])
		return true
	var shader_material: ShaderMaterial = material
	var old_value: Variant = shader_material.get_shader_parameter(parameter_name)
	shader_material.set_shader_parameter(parameter_name, data[2])
	EngineDebugger.send_message("mcp:shader_parameter_updated", [_serialize_shader_parameter_update(resolution, shader_material, parameter_name, old_value)])
	return true

func _handle_list_tilemap_layers(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "list_tilemap_layers requires node_path"}])
		return true
	var tilemap: TileMap = _resolve_tilemap(str(data[0]))
	if not tilemap:
		return true
	var layers: Array = []
	for layer_index in range(tilemap.get_layers_count()):
		layers.append(_serialize_tilemap_layer(tilemap, layer_index))
	EngineDebugger.send_message("mcp:tilemap_layers", [{
		"node_path": str(tilemap.get_path()),
		"layers": layers,
		"count": layers.size()
	}])
	return true

func _handle_get_tilemap_cell(data: Array) -> bool:
	if data.size() < 3:
		EngineDebugger.send_message("mcp:error", [{"message": "get_tilemap_cell requires node_path, layer, coords"}])
		return true
	var tilemap: TileMap = _resolve_tilemap(str(data[0]))
	if not tilemap:
		return true
	var layer: int = int(data[1])
	if not _is_valid_tilemap_layer(tilemap, layer):
		return true
	var coords: Vector2i = _variant_to_vector2i(data[2])
	var use_proxies: bool = false
	if data.size() >= 4:
		use_proxies = bool(data[3])
	EngineDebugger.send_message("mcp:tilemap_cell", [_serialize_tilemap_cell(tilemap, layer, coords, use_proxies)])
	return true

func _handle_set_tilemap_cell(data: Array) -> bool:
	if data.size() < 3:
		EngineDebugger.send_message("mcp:error", [{"message": "set_tilemap_cell requires node_path, layer, coords"}])
		return true
	var tilemap: TileMap = _resolve_tilemap(str(data[0]))
	if not tilemap:
		return true
	var layer: int = int(data[1])
	if not _is_valid_tilemap_layer(tilemap, layer):
		return true
	var coords: Vector2i = _variant_to_vector2i(data[2])
	var updates: Dictionary = {}
	if data.size() >= 4 and data[3] is Dictionary:
		updates = data[3]
	var erase: bool = bool(updates.get("erase", false))
	if erase:
		tilemap.erase_cell(layer, coords)
	else:
		var source_id: int = int(updates.get("source_id", -1))
		var atlas_coords: Vector2i = _variant_to_vector2i(updates.get("atlas_coords", {"x": -1, "y": -1}))
		var alternative_tile: int = int(updates.get("alternative_tile", 0))
		tilemap.set_cell(layer, coords, source_id, atlas_coords, alternative_tile)
	EngineDebugger.send_message("mcp:tilemap_cell_updated", [_serialize_tilemap_cell(tilemap, layer, coords, false)])
	return true

func _handle_list_audio_buses(data: Array) -> bool:
	var buses: Array = []
	for index in range(AudioServer.get_bus_count()):
		buses.append(_serialize_audio_bus(index))
	EngineDebugger.send_message("mcp:audio_buses", [{
		"buses": buses,
		"count": buses.size()
	}])
	return true

func _handle_get_audio_bus(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "get_audio_bus requires bus_name"}])
		return true
	var bus_index: int = _resolve_audio_bus_index(str(data[0]))
	if bus_index < 0:
		return true
	EngineDebugger.send_message("mcp:audio_bus", [_serialize_audio_bus(bus_index)])
	return true

func _handle_update_audio_bus(data: Array) -> bool:
	if data.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "update_audio_bus requires bus_name"}])
		return true
	var bus_index: int = _resolve_audio_bus_index(str(data[0]))
	if bus_index < 0:
		return true
	if data.size() >= 2 and data[1] is Dictionary:
		var updates: Dictionary = data[1]
		if updates.has("volume_db"):
			AudioServer.set_bus_volume_db(bus_index, float(updates.get("volume_db")))
		if updates.has("mute"):
			AudioServer.set_bus_mute(bus_index, bool(updates.get("mute")))
	EngineDebugger.send_message("mcp:audio_bus_updated", [_serialize_audio_bus(bus_index)])
	return true

func _resolve_audio_bus_index(bus_name: String) -> int:
	if bus_name.is_empty():
		EngineDebugger.send_message("mcp:error", [{"message": "bus_name cannot be empty"}])
		return -1
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		EngineDebugger.send_message("mcp:error", [{"message": "Audio bus not found: " + bus_name, "bus_name": bus_name}])
		return -1
	return bus_index

func _serialize_audio_bus(bus_index: int) -> Dictionary:
	return {
		"index": bus_index,
		"name": str(AudioServer.get_bus_name(bus_index)),
		"volume_db": AudioServer.get_bus_volume_db(bus_index),
		"mute": AudioServer.is_bus_mute(bus_index),
		"solo": AudioServer.is_bus_solo(bus_index),
		"bypass_effects": AudioServer.is_bus_bypassing_effects(bus_index),
		"send": str(AudioServer.get_bus_send(bus_index)),
		"effect_count": AudioServer.get_bus_effect_count(bus_index)
	}

func _resolve_animation_player(node_path: String) -> AnimationPlayer:
	var node: Node = _resolve_target_node(node_path)
	if not node:
		EngineDebugger.send_message("mcp:error", [{"message": "Node not found: " + node_path}])
		return null
	if not (node is AnimationPlayer):
		EngineDebugger.send_message("mcp:error", [{"message": "Node is not an AnimationPlayer: " + node_path, "node_type": node.get_class()}])
		return null
	return node

func _resolve_animation_tree(node_path: String) -> AnimationTree:
	var node: Node = _resolve_target_node(node_path)
	if not node:
		EngineDebugger.send_message("mcp:error", [{"message": "Node not found: " + node_path}])
		return null
	if not (node is AnimationTree):
		EngineDebugger.send_message("mcp:error", [{"message": "Node is not an AnimationTree: " + node_path, "node_type": node.get_class()}])
		return null
	return node

func _resolve_material_binding(node_path: String, material_target: String = "auto", surface_index: int = 0) -> Dictionary:
	var node: Node = _resolve_target_node(node_path)
	if not node:
		return {"error": "Node not found: " + node_path, "node_path": node_path}
	var target: String = material_target.strip_edges().to_lower()
	if target.is_empty():
		target = "auto"
	var material: Material = null
	var resolved_target: String = target
	match target:
		"auto":
			if node is CanvasItem and node.material:
				material = node.material
				resolved_target = "material"
			elif node.has_method("get_material_override") and node.call("get_material_override"):
				material = node.call("get_material_override")
				resolved_target = "material_override"
			elif node is MeshInstance3D:
				material = node.get_active_material(surface_index)
				resolved_target = "surface_override"
		"material":
			if node is CanvasItem:
				material = node.material
			elif node.has_method("get_material"):
				material = node.call("get_material")
		"material_override":
			if node.has_method("get_material_override"):
				material = node.call("get_material_override")
		"surface_override":
			if node is MeshInstance3D:
				material = node.get_active_material(surface_index)
			else:
				return {"error": "surface_override target requires MeshInstance3D", "node_path": node_path, "node_type": node.get_class()}
		_:
			return {"error": "Unsupported material_target: " + material_target, "node_path": node_path}
	if material == null:
		return {
			"error": "No material resolved for target",
			"node_path": node_path,
			"node_type": node.get_class(),
			"material_target": resolved_target,
			"surface_index": surface_index
		}
	return {
		"node": node,
		"node_path": str(node.get_path()),
		"node_type": node.get_class(),
		"material": material,
		"material_target": resolved_target,
		"surface_index": surface_index
	}

func _resolve_control_node(node_path: String) -> Control:
	var node: Node = _resolve_target_node(node_path)
	if not node:
		EngineDebugger.send_message("mcp:error", [{"message": "Node not found: " + node_path}])
		return null
	if not (node is Control):
		EngineDebugger.send_message("mcp:error", [{"message": "Node is not a Control: " + node_path, "node_type": node.get_class()}])
		return null
	return node

func _resolve_tilemap(node_path: String) -> TileMap:
	var node: Node = _resolve_target_node(node_path)
	if not node:
		EngineDebugger.send_message("mcp:error", [{"message": "Node not found: " + node_path}])
		return null
	if not (node is TileMap):
		EngineDebugger.send_message("mcp:error", [{"message": "Node is not a TileMap: " + node_path, "node_type": node.get_class()}])
		return null
	return node

func _is_valid_tilemap_layer(tilemap: TileMap, layer: int) -> bool:
	if layer < 0 or layer >= tilemap.get_layers_count():
		EngineDebugger.send_message("mcp:error", [{
			"message": "TileMap layer is out of range",
			"node_path": str(tilemap.get_path()),
			"layer": layer,
			"layer_count": tilemap.get_layers_count()
		}])
		return false
	return true

func _serialize_tilemap_layer(tilemap: TileMap, layer: int) -> Dictionary:
	return {
		"node_path": str(tilemap.get_path()),
		"layer": layer,
		"name": tilemap.get_layer_name(layer),
		"enabled": tilemap.is_layer_enabled(layer),
		"y_sort_enabled": tilemap.is_layer_y_sort_enabled(layer),
		"y_sort_origin": tilemap.get_layer_y_sort_origin(layer),
		"z_index": tilemap.get_layer_z_index(layer),
		"used_cell_count": tilemap.get_used_cells(layer).size()
	}

func _serialize_tilemap_cell(tilemap: TileMap, layer: int, coords: Vector2i, use_proxies: bool) -> Dictionary:
	var source_id: int = tilemap.get_cell_source_id(layer, coords, use_proxies)
	return {
		"node_path": str(tilemap.get_path()),
		"layer": layer,
		"coords": _serialize_value(coords),
		"use_proxies": use_proxies,
		"source_id": source_id,
		"atlas_coords": _serialize_value(tilemap.get_cell_atlas_coords(layer, coords, use_proxies)),
		"alternative_tile": tilemap.get_cell_alternative_tile(layer, coords, use_proxies),
		"is_empty": source_id == -1
	}

func _serialize_animation_state(player: AnimationPlayer) -> Dictionary:
	return {
		"node_path": str(player.get_path()),
		"current_animation": player.current_animation,
		"is_playing": player.is_playing(),
		"current_position": player.current_animation_position,
		"current_length": player.current_animation_length,
		"speed_scale": player.speed_scale,
		"playing_speed": player.get_playing_speed()
	}

func _serialize_animation_tree_state(animation_tree: AnimationTree) -> Dictionary:
	var playback: Variant = animation_tree.get("parameters/playback")
	var tree_root: AnimationRootNode = animation_tree.tree_root
	var result: Dictionary = {
		"node_path": str(animation_tree.get_path()),
		"active": animation_tree.active,
		"anim_player": str(animation_tree.get("anim_player")),
		"tree_root_type": tree_root.get_class() if tree_root else "",
		"has_playback": playback != null,
		"current_length": animation_tree.get("parameters/current_length") as float,
		"current_position": animation_tree.get("parameters/current_position") as float,
		"current_delta": animation_tree.get("parameters/current_delta") as float
	}
	if playback != null:
		result["playback_class"] = playback.get_class() if playback.has_method("get_class") else ""
		if playback.has_method("is_playing"):
			result["playback_is_playing"] = playback.is_playing()
		if playback.has_method("get_current_node"):
			result["current_node"] = str(playback.get_current_node())
		if playback.has_method("get_current_length"):
			result["playback_current_length"] = playback.get_current_length() as float
		if playback.has_method("get_current_play_position"):
			result["playback_current_position"] = playback.get_current_play_position() as float
		if playback.has_method("get_travel_path"):
			result["travel_path"] = PackedStringArray(playback.get_travel_path())
	return result

func _serialize_material_state(resolution: Dictionary) -> Dictionary:
	var material: Material = resolution.get("material")
	var shader_material: ShaderMaterial = material as ShaderMaterial
	var result: Dictionary = {
		"node_path": str(resolution.get("node_path", "")),
		"node_type": str(resolution.get("node_type", "")),
		"material_target": str(resolution.get("material_target", "")),
		"surface_index": int(resolution.get("surface_index", 0)),
		"material_class": material.get_class() if material else "",
		"resource_path": material.resource_path if material else "",
		"is_shader_material": shader_material != null
	}
	if shader_material:
		result["shader_resource_path"] = shader_material.shader.resource_path if shader_material.shader else ""
		result["shader_uniform_count"] = shader_material.shader.get_shader_uniform_list().size() if shader_material.shader else 0
	return result

func _resolve_theme_item(control: Control, item_type: String, item_name: String, theme_type: String = "") -> Dictionary:
	if item_name.is_empty():
		return {"error": "item_name cannot be empty", "node_path": str(control.get_path())}
	var result: Dictionary = {
		"node_path": str(control.get_path()),
		"node_type": control.get_class(),
		"item_type": item_type,
		"item_name": item_name,
		"theme_type": theme_type,
		"theme_type_variation": str(control.theme_type_variation),
		"has_override": false,
		"has_item": false,
		"value": null
	}
	match item_type:
		"color":
			result["has_override"] = control.has_theme_color_override(item_name)
			result["has_item"] = control.has_theme_color(item_name, theme_type)
			if result["has_item"]:
				result["value"] = _serialize_value(control.get_theme_color(item_name, theme_type))
		"constant":
			result["has_override"] = control.has_theme_constant_override(item_name)
			result["has_item"] = control.has_theme_constant(item_name, theme_type)
			if result["has_item"]:
				result["value"] = control.get_theme_constant(item_name, theme_type)
		"font":
			result["has_override"] = control.has_theme_font_override(item_name)
			result["has_item"] = control.has_theme_font(item_name, theme_type)
			if result["has_item"]:
				result["value"] = _serialize_theme_resource(control.get_theme_font(item_name, theme_type))
		"font_size":
			result["has_override"] = control.has_theme_font_size_override(item_name)
			result["has_item"] = control.has_theme_font_size(item_name, theme_type)
			if result["has_item"]:
				result["value"] = control.get_theme_font_size(item_name, theme_type)
		"stylebox":
			result["has_override"] = control.has_theme_stylebox_override(item_name)
			result["has_item"] = control.has_theme_stylebox(item_name, theme_type)
			if result["has_item"]:
				result["value"] = _serialize_theme_resource(control.get_theme_stylebox(item_name, theme_type))
		"icon":
			result["has_override"] = control.has_theme_icon_override(item_name)
			result["has_item"] = control.has_theme_icon(item_name, theme_type)
			if result["has_item"]:
				result["value"] = _serialize_theme_resource(control.get_theme_icon(item_name, theme_type))
		_:
			return {"error": "Unsupported theme item type: " + item_type, "node_path": str(control.get_path())}
	return result

func _serialize_theme_resource(resource: Resource) -> Dictionary:
	if not resource:
		return {}
	return {
		"resource_class": resource.get_class(),
		"resource_path": resource.resource_path
	}

func _convert_theme_override_value(item_type: String, value: Variant) -> Variant:
	match item_type:
		"color":
			if value is Dictionary:
				return Color(float(value.get("r", 0.0)), float(value.get("g", 0.0)), float(value.get("b", 0.0)), float(value.get("a", 1.0)))
			return value
		"constant", "font_size":
			return int(value)
		"font", "stylebox", "icon":
			if value is String and not String(value).is_empty():
				return load(String(value))
			if value is Resource:
				return value
	return value

func _apply_theme_override(control: Control, item_type: String, item_name: String, override_value: Variant) -> String:
	if item_name.is_empty():
		return "item_name cannot be empty"
	match item_type:
		"color":
			control.add_theme_color_override(item_name, override_value)
		"constant":
			control.add_theme_constant_override(item_name, int(override_value))
		"font":
			if not (override_value is Font):
				return "font override requires a Font resource path"
			control.add_theme_font_override(item_name, override_value)
		"font_size":
			control.add_theme_font_size_override(item_name, int(override_value))
		"stylebox":
			if not (override_value is StyleBox):
				return "stylebox override requires a StyleBox resource path"
			control.add_theme_stylebox_override(item_name, override_value)
		"icon":
			if not (override_value is Texture2D):
				return "icon override requires a Texture2D resource path"
			control.add_theme_icon_override(item_name, override_value)
		_:
			return "Unsupported theme item type: " + item_type
	return ""

func _remove_theme_override(control: Control, item_type: String, item_name: String) -> String:
	if item_name.is_empty():
		return "item_name cannot be empty"
	match item_type:
		"color":
			control.remove_theme_color_override(item_name)
		"constant":
			control.remove_theme_constant_override(item_name)
		"font":
			control.remove_theme_font_override(item_name)
		"font_size":
			control.remove_theme_font_size_override(item_name)
		"stylebox":
			control.remove_theme_stylebox_override(item_name)
		"icon":
			control.remove_theme_icon_override(item_name)
		_:
			return "Unsupported theme item type: " + item_type
	return ""

func _serialize_shader_parameters(resolution: Dictionary, material: ShaderMaterial) -> Dictionary:
	var uniforms: Array = material.shader.get_shader_uniform_list() if material.shader else []
	var parameters: Array = []
	for uniform_info in uniforms:
		var uniform_name: String = str(uniform_info.get("name", ""))
		parameters.append({
			"name": uniform_name,
			"type": int(uniform_info.get("type", -1)),
			"hint": int(uniform_info.get("hint", 0)),
			"hint_string": str(uniform_info.get("hint_string", "")),
			"value": _serialize_value(material.get_shader_parameter(uniform_name))
		})
	parameters.sort_custom(Callable(self, "_sort_shader_parameter_entries"))
	var result: Dictionary = _serialize_material_state(resolution)
	result["parameters"] = parameters
	result["count"] = parameters.size()
	return result

func _serialize_shader_parameter_update(resolution: Dictionary, material: ShaderMaterial, parameter_name: String, old_value: Variant) -> Dictionary:
	var result: Dictionary = _serialize_material_state(resolution)
	result["parameter_name"] = parameter_name
	result["old_value"] = _serialize_value(old_value)
	result["new_value"] = _serialize_value(material.get_shader_parameter(parameter_name))
	return result

func _build_input_event(payload: Dictionary) -> InputEvent:
	var event_type: String = str(payload.get("type", "")).to_lower()
	match event_type:
		"action":
			var action_name: String = str(payload.get("action_name", ""))
			if action_name.is_empty():
				return null
			var action_event := InputEventAction.new()
			action_event.action = StringName(action_name)
			action_event.pressed = bool(payload.get("pressed", true))
			action_event.strength = float(payload.get("strength", 1.0 if action_event.pressed else 0.0))
			return action_event
		"key":
			var keycode: int = int(payload.get("keycode", 0))
			if keycode == 0:
				return null
			var key_event := InputEventKey.new()
			key_event.keycode = keycode
			key_event.physical_keycode = int(payload.get("physical_keycode", 0))
			key_event.unicode = int(payload.get("unicode", 0))
			key_event.pressed = bool(payload.get("pressed", true))
			key_event.echo = bool(payload.get("echo", false))
			_apply_input_modifiers(key_event, payload)
			return key_event
		"mouse_button":
			var button_index: int = int(payload.get("button_index", 0))
			if button_index == 0:
				return null
			var mouse_button_event := InputEventMouseButton.new()
			mouse_button_event.button_index = button_index
			mouse_button_event.pressed = bool(payload.get("pressed", true))
			mouse_button_event.double_click = bool(payload.get("double_click", false))
			mouse_button_event.factor = float(payload.get("factor", 1.0))
			mouse_button_event.button_mask = int(payload.get("button_mask", 0))
			mouse_button_event.position = _dict_to_vector2(payload.get("position", {}))
			mouse_button_event.global_position = _dict_to_vector2(payload.get("global_position", payload.get("position", {})))
			_apply_input_modifiers(mouse_button_event, payload)
			return mouse_button_event
		"mouse_motion":
			var mouse_motion_event := InputEventMouseMotion.new()
			mouse_motion_event.position = _dict_to_vector2(payload.get("position", {}))
			mouse_motion_event.global_position = _dict_to_vector2(payload.get("global_position", payload.get("position", {})))
			mouse_motion_event.relative = _dict_to_vector2(payload.get("relative", {}))
			mouse_motion_event.velocity = _dict_to_vector2(payload.get("velocity", {}))
			mouse_motion_event.button_mask = int(payload.get("button_mask", 0))
			mouse_motion_event.pressure = float(payload.get("pressure", 0.0))
			mouse_motion_event.pen_inverted = bool(payload.get("pen_inverted", false))
			_apply_input_modifiers(mouse_motion_event, payload)
			return mouse_motion_event
		"screen_touch":
			var screen_touch_event := InputEventScreenTouch.new()
			screen_touch_event.index = int(payload.get("index", 0))
			screen_touch_event.pressed = bool(payload.get("pressed", true))
			screen_touch_event.position = _dict_to_vector2(payload.get("position", {}))
			screen_touch_event.double_tap = bool(payload.get("double_tap", false))
			screen_touch_event.canceled = bool(payload.get("canceled", false))
			return screen_touch_event
		"screen_drag":
			var screen_drag_event := InputEventScreenDrag.new()
			screen_drag_event.index = int(payload.get("index", 0))
			screen_drag_event.position = _dict_to_vector2(payload.get("position", {}))
			screen_drag_event.relative = _dict_to_vector2(payload.get("relative", {}))
			screen_drag_event.velocity = _dict_to_vector2(payload.get("velocity", {}))
			screen_drag_event.pressure = float(payload.get("pressure", 0.0))
			screen_drag_event.pen_inverted = bool(payload.get("pen_inverted", false))
			return screen_drag_event
		"joypad_button":
			var joypad_button_event := InputEventJoypadButton.new()
			joypad_button_event.device = int(payload.get("device", 0))
			joypad_button_event.button_index = int(payload.get("button_index", 0))
			joypad_button_event.pressed = bool(payload.get("pressed", true))
			joypad_button_event.pressure = float(payload.get("pressure", 0.0))
			return joypad_button_event
		"joypad_motion":
			var joypad_motion_event := InputEventJoypadMotion.new()
			joypad_motion_event.device = int(payload.get("device", 0))
			joypad_motion_event.axis = int(payload.get("axis", 0))
			joypad_motion_event.axis_value = float(payload.get("axis_value", 0.0))
			return joypad_motion_event
		_:
			return null

func _apply_input_modifiers(event: InputEventWithModifiers, payload: Dictionary) -> void:
	event.alt_pressed = bool(payload.get("alt_pressed", false))
	event.shift_pressed = bool(payload.get("shift_pressed", false))
	event.ctrl_pressed = bool(payload.get("ctrl_pressed", false))
	event.meta_pressed = bool(payload.get("meta_pressed", false))
	event.command_or_control_autoremap = bool(payload.get("command_or_control_autoremap", false))

func _dict_to_vector2(value: Variant) -> Vector2:
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO

func _serialize_input_event(event: InputEvent) -> Dictionary:
	if event is InputEventAction:
		return {
			"type": "action",
			"action_name": String(event.action),
			"pressed": event.pressed,
			"strength": event.strength,
			"runtime_pressed": Input.is_action_pressed(event.action)
		}
	if event is InputEventKey:
		return {
			"type": "key",
			"keycode": event.keycode,
			"physical_keycode": event.physical_keycode,
			"unicode": event.unicode,
			"pressed": event.pressed,
			"echo": event.echo
		}
	if event is InputEventMouseButton:
		return {
			"type": "mouse_button",
			"button_index": event.button_index,
			"pressed": event.pressed,
			"double_click": event.double_click,
			"position": {"x": event.position.x, "y": event.position.y}
		}
	if event is InputEventMouseMotion:
		return {
			"type": "mouse_motion",
			"position": {"x": event.position.x, "y": event.position.y},
			"relative": {"x": event.relative.x, "y": event.relative.y},
			"velocity": {"x": event.velocity.x, "y": event.velocity.y}
		}
	if event is InputEventScreenTouch:
		return {
			"type": "screen_touch",
			"index": event.index,
			"pressed": event.pressed,
			"position": {"x": event.position.x, "y": event.position.y},
			"double_tap": event.double_tap,
			"canceled": event.canceled
		}
	if event is InputEventScreenDrag:
		return {
			"type": "screen_drag",
			"index": event.index,
			"position": {"x": event.position.x, "y": event.position.y},
			"relative": {"x": event.relative.x, "y": event.relative.y},
			"velocity": {"x": event.velocity.x, "y": event.velocity.y},
			"pressure": event.pressure,
			"pen_inverted": event.pen_inverted
		}
	if event is InputEventJoypadButton:
		return {
			"type": "joypad_button",
			"device": event.device,
			"button_index": event.button_index,
			"pressed": event.pressed,
			"pressure": event.pressure
		}
	if event is InputEventJoypadMotion:
		return {
			"type": "joypad_motion",
			"device": event.device,
			"axis": event.axis,
			"axis_value": event.axis_value
		}
	return {"type": "unknown", "class": event.get_class()}

func _sort_input_action_entries(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("action_name", "")) < str(b.get("action_name", ""))

func _sort_animation_entries(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("name", "")) < str(b.get("name", ""))

func _sort_shader_parameter_entries(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("name", "")) < str(b.get("name", ""))

func capture_runtime_screenshot(save_path: String = "user://mcp_runtime_capture.png", format: String = "png", viewport_path: String = "") -> Dictionary:
	if not ["png", "jpg"].has(format):
		return {"error": "Unsupported screenshot format: " + format}

	var viewport: Viewport = get_viewport()
	if not viewport_path.is_empty():
		var viewport_node: Node = _resolve_target_node(viewport_path)
		if not viewport_node:
			return {"error": "Viewport node not found: " + viewport_path}
		if not (viewport_node is Viewport):
			return {"error": "Node is not a Viewport: " + viewport_path, "node_type": viewport_node.get_class()}
		viewport = viewport_node
	if not viewport:
		return {"error": "Runtime viewport is not available"}
	var texture: Texture2D = viewport.get_texture()
	if not texture:
		return {"error": "Failed to get runtime viewport texture"}
	var image: Image = texture.get_image()
	if not image or image.is_empty():
		return {"error": "Failed to capture runtime viewport image"}

	var absolute_path: String = ProjectSettings.globalize_path(save_path)
	var save_dir: String = absolute_path.get_base_dir()
	if not save_dir.is_empty() and not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var err: Error = OK
	if format == "jpg":
		err = image.save_jpg(absolute_path, 0.9)
	else:
		err = image.save_png(absolute_path)
	if err != OK:
		return {"error": "Failed to save runtime screenshot: error " + str(err)}

	return {
		"save_path": save_path,
		"format": format,
		"viewport_path": str(viewport.get_path()),
		"width": image.get_width(),
		"height": image.get_height(),
		"size": str(image.get_width()) + "x" + str(image.get_height()),
		"current_scene": str(get_tree().current_scene.get_path()) if get_tree().current_scene else ""
	}

func _resolve_target_node(node_path: String) -> Node:
	if node_path.is_empty() or node_path == ".":
		return get_tree().current_scene if get_tree().current_scene else get_tree().root
	if node_path == "/root":
		return get_tree().root
	return get_node_or_null(NodePath(node_path))

func _convert_value_for_property(node: Node, property_name: String, value: Variant) -> Variant:
	if value is String:
		var parsed: Variant = JSON.parse_string(value)
		if parsed != null:
			value = parsed

	var property_type: int = TYPE_NIL
	for property_info in node.get_property_list():
		if property_info.get("name", "") == property_name:
			property_type = int(property_info.get("type", TYPE_NIL))
			break

	match property_type:
		TYPE_VECTOR2:
			if value is Dictionary:
				return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
		TYPE_VECTOR3:
			if value is Dictionary:
				return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
		TYPE_COLOR:
			if value is Dictionary:
				return Color(float(value.get("r", 0.0)), float(value.get("g", 0.0)), float(value.get("b", 0.0)), float(value.get("a", 1.0)))
		TYPE_BOOL:
			if value is String:
				return value.to_lower() == "true"
		TYPE_INT:
			if value is String:
				return int(value)
		TYPE_FLOAT:
			if value is String:
				return float(value)

	return value

func _serialize_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(_serialize_value(item))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in value:
				result[str(key)] = _serialize_value(value[key])
			return result
		_:
			return str(value)

func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count

func _variant_to_vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO
