class_name MCPToolClassifier
extends RefCounted

const CORE_MAX_COUNT: int = 30

var _tool_classifications: Dictionary = {}

func _init() -> void:
	_build_classifications()

func _build_classifications() -> void:
	var classifications: Array[Dictionary] = [
		{"name": "create_node", "category": "core", "group": "Node-Write"},
		{"name": "delete_node", "category": "core", "group": "Node-Write"},
		{"name": "update_node_property", "category": "core", "group": "Node-Write"},
		{"name": "get_node_properties", "category": "core", "group": "Node-Read"},
		{"name": "list_nodes", "category": "core", "group": "Node-Read"},
		{"name": "get_scene_tree", "category": "core", "group": "Node-Read"},
		{"name": "duplicate_node", "category": "core", "group": "Node-Write"},
		{"name": "move_node", "category": "core", "group": "Node-Write"},
		{"name": "rename_node", "category": "core", "group": "Node-Write"},
		{"name": "add_resource", "category": "supplementary", "group": "Node-Write-Advanced"},
		{"name": "set_anchor_preset", "category": "supplementary", "group": "Node-Write-Advanced"},
		{"name": "connect_signal", "category": "supplementary", "group": "Node-Write-Advanced"},
		{"name": "disconnect_signal", "category": "supplementary", "group": "Node-Write-Advanced"},
		{"name": "get_node_groups", "category": "supplementary", "group": "Node-Advanced"},
		{"name": "set_node_groups", "category": "supplementary", "group": "Node-Write-Advanced"},
		{"name": "find_nodes_in_group", "category": "supplementary", "group": "Node-Advanced"},
		{"name": "list_project_scripts", "category": "core", "group": "Script"},
		{"name": "read_script", "category": "core", "group": "Script"},
		{"name": "create_script", "category": "core", "group": "Script"},
		{"name": "modify_script", "category": "core", "group": "Script"},
		{"name": "analyze_script", "category": "supplementary", "group": "Script-Advanced"},
		{"name": "get_current_script", "category": "core", "group": "Script"},
		{"name": "attach_script", "category": "core", "group": "Script"},
		{"name": "validate_script", "category": "supplementary", "group": "Script-Advanced"},
		{"name": "search_in_files", "category": "supplementary", "group": "Script-Advanced"},
		{"name": "create_scene", "category": "core", "group": "Scene"},
		{"name": "save_scene", "category": "core", "group": "Scene"},
		{"name": "open_scene", "category": "core", "group": "Scene"},
		{"name": "get_current_scene", "category": "core", "group": "Scene"},
		{"name": "get_scene_structure", "category": "supplementary", "group": "Scene-Advanced"},
		{"name": "list_project_scenes", "category": "supplementary", "group": "Scene-Advanced"},
		{"name": "get_editor_state", "category": "core", "group": "Editor"},
		{"name": "run_project", "category": "core", "group": "Editor"},
		{"name": "stop_project", "category": "core", "group": "Editor"},
		{"name": "get_selected_nodes", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "set_editor_setting", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "get_editor_screenshot", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "get_signals", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "reload_project", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "get_editor_logs", "category": "core", "group": "Debug"},
		{"name": "execute_script", "category": "core", "group": "Script"},
		{"name": "get_performance_metrics", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_print", "category": "core", "group": "Debug"},
		{"name": "execute_editor_script", "category": "core", "group": "Editor"},
		{"name": "clear_output", "category": "core", "group": "Debug"},
		{"name": "get_debugger_sessions", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "set_debugger_breakpoint", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "send_debugger_message", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "toggle_debugger_profiler", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_debugger_messages", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "add_debugger_capture_prefix", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_debug_stack_frames", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_debug_stack_variables", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "install_runtime_probe", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "remove_runtime_probe", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "request_debug_break", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "send_debug_command", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_info", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "await_scene_ready", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_scene_tree", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "inspect_runtime_node", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "update_runtime_node_property", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "call_runtime_node_method", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "evaluate_runtime_expression", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "await_runtime_condition", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "assert_runtime_condition", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_project_info", "category": "core", "group": "Project"},
		{"name": "get_project_settings", "category": "core", "group": "Project"},
		{"name": "list_project_resources", "category": "core", "group": "Project"},
		{"name": "create_resource", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "get_project_structure", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "select_node", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "select_file", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "get_inspector_properties", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "list_export_presets", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "inspect_export_templates", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "validate_export_preset", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "run_export", "category": "supplementary", "group": "Editor-Advanced"},
		{"name": "batch_update_node_properties", "category": "supplementary", "group": "Node-Advanced"},
		{"name": "batch_scene_node_edits", "category": "supplementary", "group": "Node-Advanced"},
		{"name": "audit_scene_node_persistence", "category": "supplementary", "group": "Node-Advanced"},
		{"name": "audit_scene_inheritance", "category": "supplementary", "group": "Node-Advanced"},
		{"name": "list_open_scenes", "category": "supplementary", "group": "Scene-Advanced"},
		{"name": "close_scene_tab", "category": "supplementary", "group": "Scene-Advanced"},
		{"name": "list_project_script_symbols", "category": "supplementary", "group": "Script-Advanced"},
		{"name": "find_script_symbol_definition", "category": "supplementary", "group": "Script-Advanced"},
		{"name": "find_script_symbol_references", "category": "supplementary", "group": "Script-Advanced"},
		{"name": "rename_script_symbol", "category": "supplementary", "group": "Script-Advanced"},
		{"name": "open_script_at_line", "category": "supplementary", "group": "Script-Advanced"},
		{"name": "get_debug_threads", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_debug_state_events", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_debug_output", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_debug_scopes", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_debug_variables", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "expand_debug_variable", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "evaluate_debug_expression", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_step_into", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_step_over", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_step_out", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_continue", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_step_into_and_wait", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_step_over_and_wait", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_step_out_and_wait", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "debug_continue_and_wait", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "await_debugger_state", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_performance_snapshot", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_memory_trend", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "create_runtime_node", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "delete_runtime_node", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "simulate_runtime_input_event", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "simulate_runtime_input_action", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "list_runtime_input_actions", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "upsert_runtime_input_action", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "remove_runtime_input_action", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "list_runtime_animations", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "play_runtime_animation", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "stop_runtime_animation", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_animation_state", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_animation_tree_state", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "set_runtime_animation_tree_active", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "travel_runtime_animation_tree", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_material_state", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_theme_item", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "set_runtime_theme_override", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "clear_runtime_theme_override", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_shader_parameters", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "set_runtime_shader_parameter", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "list_runtime_tilemap_layers", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_tilemap_cell", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "set_runtime_tilemap_cell", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "list_runtime_audio_buses", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_audio_bus", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "update_runtime_audio_bus", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "get_runtime_screenshot", "category": "supplementary", "group": "Debug-Advanced"},
		{"name": "list_project_tests", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "run_project_test", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "run_project_tests", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "list_project_input_actions", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "upsert_project_input_action", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "remove_project_input_action", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "list_project_autoloads", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "list_project_global_classes", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "get_class_api_metadata", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "inspect_csharp_project_support", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "compare_render_screenshots", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "inspect_tileset_resource", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "reimport_resources", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "get_import_metadata", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "get_resource_uid_info", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "fix_resource_uid", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "get_resource_dependencies", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "scan_missing_resource_dependencies", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "scan_cyclic_resource_dependencies", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "detect_broken_scripts", "category": "supplementary", "group": "Project-Advanced"},
		{"name": "audit_project_health", "category": "supplementary", "group": "Project-Advanced"},
	]

	for item in classifications:
		_tool_classifications[item["name"]] = {
			"category": item["category"],
			"group": item["group"]
		}

func get_tool_category(tool_name: String) -> String:
	if _tool_classifications.has(tool_name):
		return _tool_classifications[tool_name]["category"]
	return "core"

func get_tool_group(tool_name: String) -> String:
	if _tool_classifications.has(tool_name):
		return _tool_classifications[tool_name]["group"]
	return ""

func get_all_groups() -> Array[String]:
	var groups: Array[String] = []
	for tool_name in _tool_classifications:
		var group: String = _tool_classifications[tool_name]["group"]
		if not group in groups and not group.is_empty():
			groups.append(group)
	return groups

func get_group_tools(group_name: String) -> Array[String]:
	var tools: Array[String] = []
	for tool_name in _tool_classifications:
		if _tool_classifications[tool_name]["group"] == group_name:
			tools.append(tool_name)
	return tools

func get_core_tools() -> Array[String]:
	var tools: Array[String] = []
	for tool_name in _tool_classifications:
		if _tool_classifications[tool_name]["category"] == "core":
			tools.append(tool_name)
	return tools

func get_supplementary_tools() -> Array[String]:
	var tools: Array[String] = []
	for tool_name in _tool_classifications:
		if _tool_classifications[tool_name]["category"] == "supplementary":
			tools.append(tool_name)
	return tools

func get_core_max_count() -> int:
	return CORE_MAX_COUNT

func is_core_tool(tool_name: String) -> bool:
	return get_tool_category(tool_name) == "core"

func is_supplementary_tool(tool_name: String) -> bool:
	return get_tool_category(tool_name) == "supplementary"

func get_all_tools() -> Array:
	return _tool_classifications.keys()

func get_all_categories() -> Array[String]:
	var categories: Array[String] = []
	for tool_name in _tool_classifications:
		var cat: String = _tool_classifications[tool_name]["category"]
		if not cat in categories:
			categories.append(cat)
	return categories
