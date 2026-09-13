# project_tools_native.gd - Project Tools原生实现

@tool
class_name ProjectToolsNative
extends RefCounted

var _editor_interface: EditorInterface = null

func initialize(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface

func _get_editor_interface() -> EditorInterface:
	if _editor_interface:
		return _editor_interface
	if Engine.has_meta("GodotMCPPlugin"):
		var plugin = Engine.get_meta("GodotMCPPlugin")
		if plugin and plugin.has_method("get_editor_interface"):
			return plugin.get_editor_interface()
	return null

# ============================================================================
# 工具注册
# ============================================================================

func register_tools(server_core: RefCounted) -> void:
	_register_get_project_info(server_core)
	_register_get_project_settings(server_core)
	_register_list_project_tests(server_core)
	_register_run_project_test(server_core)
	_register_run_project_tests(server_core)
	_register_list_project_input_actions(server_core)
	_register_upsert_project_input_action(server_core)
	_register_remove_project_input_action(server_core)
	_register_list_project_autoloads(server_core)
	_register_list_project_global_classes(server_core)
	_register_get_class_api_metadata(server_core)
	_register_inspect_csharp_project_support(server_core)
	_register_compare_render_screenshots(server_core)
	_register_inspect_tileset_resource(server_core)
	_register_list_project_resources(server_core)
	_register_create_resource(server_core)
	_register_get_project_structure(server_core)
	_register_reimport_resources(server_core)
	_register_get_import_metadata(server_core)
	_register_get_resource_uid_info(server_core)
	_register_fix_resource_uid(server_core)
	_register_get_resource_dependencies(server_core)
	_register_scan_missing_resource_dependencies(server_core)
	_register_scan_cyclic_resource_dependencies(server_core)
	_register_detect_broken_scripts(server_core)
	_register_audit_project_health(server_core)

# ============================================================================
# get_project_info - 获取项目信息
# ============================================================================

func _register_get_project_info(server_core: RefCounted) -> void:
	var tool_name: String = "get_project_info"
	var description: String = "Get general information about the Godot project, including name, version, and description."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"project_name": {"type": "string"},
			"project_version": {"type": "string"},
			"project_description": {"type": "string"},
			"main_scene": {"type": "string"},
			"project_path": {"type": "string"},
			"godot_version": {"type": "string"}
		}
	}
	
	# annotations - readOnlyHint = true
	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_project_info"),
						  output_schema, annotations,
						  "core", "Project")

func _tool_get_project_info(params: Dictionary) -> Dictionary:
	var project_name: String = ProjectSettings.get_setting("application/config/name", "")
	var project_version: String = ProjectSettings.get_setting("application/config/version", "")
	var project_description: String = ProjectSettings.get_setting("application/config/description", "")
	var main_scene_uid: String = ProjectSettings.get_setting("application/run/main_scene", "")
	
	var main_scene: String = main_scene_uid
	if main_scene_uid.begins_with("uid://"):
		if ClassDB.class_exists("ResourceUID"):
			main_scene = ResourceUID.uid_to_path(main_scene_uid)
	
	var project_path: String = ProjectSettings.globalize_path("res://")
	var godot_version: Dictionary = Engine.get_version_info()
	var version_str: String = "%d.%d.%s" % [godot_version.get("major", 0), godot_version.get("minor", 0), godot_version.get("status", "")]
	
	return {
		"project_name": project_name,
		"project_version": project_version,
		"project_description": project_description,
		"main_scene": main_scene,
		"project_path": project_path,
		"godot_version": version_str
	}

# ============================================================================
# get_project_settings - 获取项目设置
# ============================================================================

func _register_get_project_settings(server_core: RefCounted) -> void:
	var tool_name: String = "get_project_settings"
	var description: String = "Get project settings. Optionally filter by a prefix."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"filter": {
				"type": "string",
				"description": "Optional prefix to filter settings (e.g. 'display/', 'input/'). Returns all if not provided."
			}
		}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"settings": {"type": "object"},
			"count": {"type": "integer"}
		}
	}
	
	# annotations - readOnlyHint = true
	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_project_settings"),
						  output_schema, annotations,
						  "core", "Project")

func _tool_get_project_settings(params: Dictionary) -> Dictionary:
	var filter: String = params.get("filter", "")
	
	var settings: Dictionary = {}
	var setting_count: int = 0
	
	var all_properties: Array = ProjectSettings.get_property_list()
	
	for property_info in all_properties:
		var setting_name: String = property_info.get("name", "")
		
		if not filter.is_empty() and not setting_name.begins_with(filter):
			continue
		
		var value: Variant = ProjectSettings.get_setting(setting_name)
		settings[setting_name] = str(value)
		setting_count += 1
	
	return {
		"settings": settings,
		"count": setting_count
	}

# ============================================================================
# project input actions - 项目级 InputMap
# ============================================================================

func _register_list_project_input_actions(server_core: RefCounted) -> void:
	var tool_name: String = "list_project_input_actions"
	var description: String = "List project InputMap actions stored in ProjectSettings, including serialized input events."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"action_name": {
				"type": "string",
				"description": "Optional exact action name filter."
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"actions": {"type": "array"},
			"count": {"type": "integer"},
			"filter": {"type": "string"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_list_project_input_actions"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_list_project_input_actions(params: Dictionary) -> Dictionary:
	var action_name: String = str(params.get("action_name", "")).strip_edges()
	var actions: Array = _collect_project_input_actions(action_name)
	return {
		"actions": actions,
		"count": actions.size(),
		"filter": action_name
	}

func _register_upsert_project_input_action(server_core: RefCounted) -> void:
	var tool_name: String = "upsert_project_input_action"
	var description: String = "Create or update a project InputMap action in ProjectSettings and save project.godot."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"action_name": {"type": "string"},
			"deadzone": {"type": "number", "default": 0.5},
			"erase_existing": {"type": "boolean", "default": false},
			"events": {"type": "array", "items": {"type": "object"}, "description": "Optional structured input event payloads to store on the action."}
		},
		"required": ["action_name"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"action_name": {"type": "string"},
			"existed_before": {"type": "boolean"},
			"deadzone": {"type": "number"},
			"event_count": {"type": "integer"},
			"events": {"type": "array", "items": {"type": "object"}},
			"added_events": {"type": "array", "items": {"type": "object"}}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": false,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_upsert_project_input_action"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_upsert_project_input_action(params: Dictionary) -> Dictionary:
	var action_name: String = str(params.get("action_name", "")).strip_edges()
	if action_name.is_empty():
		return {"error": "Missing required parameter: action_name"}

	var deadzone: float = float(params.get("deadzone", 0.5))
	var erase_existing: bool = bool(params.get("erase_existing", false))
	var raw_events: Array = params.get("events", [])
	var setting_name: String = "input/" + action_name
	var existed_before: bool = ProjectSettings.has_setting(setting_name)

	var stored_events: Array = []
	var added_events: Array = []
	if existed_before and not erase_existing:
		var existing_value: Variant = ProjectSettings.get_setting(setting_name, {})
		if existing_value is Dictionary:
			stored_events = (existing_value.get("events", []) as Array).duplicate()
	for raw_event in raw_events:
		if not (raw_event is Dictionary):
			return {"error": "Each event entry must be an object"}
		var built_event: InputEvent = _build_project_input_event(raw_event)
		if built_event == null:
			return {"error": "Unsupported input event payload: " + JSON.stringify(raw_event)}
		stored_events.append(built_event)
		added_events.append(_serialize_project_input_event(built_event))

	ProjectSettings.set_setting(setting_name, {
		"deadzone": deadzone,
		"events": stored_events
	})
	var save_error: Error = ProjectSettings.save()
	if save_error != OK:
		return {"error": "Failed to save project settings: " + str(save_error)}
	InputMap.load_from_project_settings()

	var listed_actions: Array = _collect_project_input_actions(action_name)
	var action_entry: Dictionary = listed_actions[0] if not listed_actions.is_empty() else {}
	action_entry["added_events"] = added_events
	action_entry["existed_before"] = existed_before
	return action_entry

func _register_remove_project_input_action(server_core: RefCounted) -> void:
	var tool_name: String = "remove_project_input_action"
	var description: String = "Remove a project InputMap action from ProjectSettings and save project.godot."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"action_name": {"type": "string"}
		},
		"required": ["action_name"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"action_name": {"type": "string"},
			"removed": {"type": "boolean"},
			"event_count": {"type": "integer"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": true,
		"idempotentHint": false,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_remove_project_input_action"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_remove_project_input_action(params: Dictionary) -> Dictionary:
	var action_name: String = str(params.get("action_name", "")).strip_edges()
	if action_name.is_empty():
		return {"error": "Missing required parameter: action_name"}

	var setting_name: String = "input/" + action_name
	if not ProjectSettings.has_setting(setting_name):
		return {
			"action_name": action_name,
			"removed": false,
			"event_count": 0
		}

	var existing_value: Variant = ProjectSettings.get_setting(setting_name, {})
	var event_count: int = 0
	if existing_value is Dictionary:
		event_count = (existing_value.get("events", []) as Array).size()

	ProjectSettings.clear(setting_name)
	var save_error: Error = ProjectSettings.save()
	if save_error != OK:
		return {"error": "Failed to save project settings: " + str(save_error)}
	InputMap.load_from_project_settings()

	return {
		"action_name": action_name,
		"removed": true,
		"event_count": event_count
	}

# ============================================================================
# list_project_autoloads - 列出项目 Autoload
# ============================================================================

func _register_list_project_autoloads(server_core: RefCounted) -> void:
	var tool_name: String = "list_project_autoloads"
	var description: String = "List project autoload entries with resolved path, singleton flag, and project setting order."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"filter": {
				"type": "string",
				"description": "Optional case-insensitive filter that matches autoload name or path."
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"autoloads": {"type": "array", "items": {"type": "object"}},
			"count": {"type": "integer"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_list_project_autoloads"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_list_project_autoloads(params: Dictionary) -> Dictionary:
	var filter: String = str(params.get("filter", "")).strip_edges().to_lower()
	var values_by_name: Dictionary = {}
	var orders_by_name: Dictionary = {}
	for property_info in ProjectSettings.get_property_list():
		var property_name: String = str(property_info.get("name", ""))
		if not property_name.begins_with("autoload/"):
			continue
		values_by_name[property_name] = ProjectSettings.get_setting(property_name)
		orders_by_name[property_name] = ProjectSettings.get_order(property_name)

	var autoloads: Array = _collect_project_autoloads_from_properties(ProjectSettings.get_property_list(), values_by_name, orders_by_name)
	if not filter.is_empty():
		var filtered_autoloads: Array = []
		for entry in autoloads:
			var entry_name: String = str(entry.get("name", "")).to_lower()
			var entry_path: String = str(entry.get("path", "")).to_lower()
			if entry_name.contains(filter) or entry_path.contains(filter):
				filtered_autoloads.append(entry)
		autoloads = filtered_autoloads

	return {
		"autoloads": autoloads,
		"count": autoloads.size()
	}

# ============================================================================
# list_project_global_classes - 列出项目全局脚本类
# ============================================================================

func _register_list_project_global_classes(server_core: RefCounted) -> void:
	var tool_name: String = "list_project_global_classes"
	var description: String = "List project global script classes registered through class_name metadata."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"filter": {
				"type": "string",
				"description": "Optional case-insensitive filter that matches class name, base type, or script path."
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"classes": {"type": "array", "items": {"type": "object"}},
			"count": {"type": "integer"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_list_project_global_classes"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_list_project_global_classes(params: Dictionary) -> Dictionary:
	var filter: String = str(params.get("filter", "")).strip_edges().to_lower()
	var class_entries: Array = []
	if ProjectSettings.has_method("get_global_class_list"):
		class_entries = _normalize_global_class_entries(ProjectSettings.get_global_class_list())
	if not filter.is_empty():
		var filtered_entries: Array = []
		for entry in class_entries:
			var entry_name: String = str(entry.get("name", "")).to_lower()
			var base_name: String = str(entry.get("base", "")).to_lower()
			var path: String = str(entry.get("path", "")).to_lower()
			if entry_name.contains(filter) or base_name.contains(filter) or path.contains(filter):
				filtered_entries.append(entry)
		class_entries = filtered_entries
	return {
		"classes": class_entries,
		"count": class_entries.size()
	}

# ============================================================================
# get_class_api_metadata - 获取类型化 API 元数据
# ============================================================================

func _register_get_class_api_metadata(server_core: RefCounted) -> void:
	var tool_name: String = "get_class_api_metadata"
	var description: String = "Get typed API metadata for an engine ClassDB class or a project global script class."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"class_name": {
				"type": "string",
				"description": "Class name to inspect, such as 'Node' or a project global class_name."
			},
			"filter": {
				"type": "string",
				"description": "Optional case-insensitive filter applied to method/property/signal/constant names."
			},
			"include_base_api": {
				"type": "boolean",
				"description": "For project global classes, whether to include base ClassDB metadata. Default is true.",
				"default": true
			}
		},
		"required": ["class_name"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"class_name": {"type": "string"},
			"source": {"type": "string"},
			"base_class": {"type": "string"},
			"methods": {"type": "array"},
			"properties": {"type": "array"},
			"signals": {"type": "array"},
			"constants": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_class_api_metadata"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_get_class_api_metadata(params: Dictionary) -> Dictionary:
	var target_class_name: String = str(params.get("class_name", "")).strip_edges()
	if target_class_name.is_empty():
		return {"error": "Missing required parameter: class_name"}
	var filter: String = str(params.get("filter", "")).strip_edges().to_lower()
	var include_base_api: bool = params.get("include_base_api", true)

	if ClassDB.class_exists(target_class_name):
		return _build_classdb_api_metadata(target_class_name, filter)

	var global_class: Dictionary = _find_project_global_class_entry(target_class_name)
	if global_class.is_empty():
		return {"error": "Class not found: " + target_class_name}

	var script_path: String = str(global_class.get("path", ""))
	var script: Script = load(script_path)
	if not script:
		return {"error": "Failed to load global class script: " + script_path}

	var result: Dictionary = {
		"class_name": target_class_name,
		"source": "global_class",
		"base_class": str(global_class.get("base", "")),
		"script_path": script_path,
		"language": str(global_class.get("language", "")),
		"is_tool": bool(global_class.get("is_tool", false)),
		"is_abstract": bool(global_class.get("is_abstract", false)),
		"methods": _normalize_method_entries(script.get_script_method_list(), filter),
		"properties": _normalize_property_entries(script.get_script_property_list(), filter),
		"signals": _normalize_signal_entries(script.get_script_signal_list(), filter),
		"constants": []
	}

	if include_base_api:
		var base_class: String = str(global_class.get("base", ""))
		if not base_class.is_empty() and ClassDB.class_exists(base_class):
			result["base_api"] = _build_classdb_api_metadata(base_class, filter)

	return result

# ============================================================================
# list_project_tests - 发现项目测试
# ============================================================================

func _register_list_project_tests(server_core: RefCounted) -> void:
	server_core.register_tool(
		"list_project_tests",
		"Discover runnable project tests under the Godot project's test directories. Reports Python integration tests and GUT unit tests, including whether each test is currently runnable.",
		{
			"type": "object",
			"properties": {
				"search_path": {"type": "string", "description": "Optional res:// path to limit discovery."},
				"framework": {"type": "string", "description": "Optional framework filter: python or gut."}
			}
		},
		Callable(self, "_tool_list_project_tests"),
		{
			"type": "object",
			"properties": {
				"count": {"type": "integer"},
				"search_path": {"type": "string"},
				"tests": {"type": "array"}
			}
		},
		{"readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false},
		"supplementary", "Project-Advanced"
	)

func _tool_list_project_tests(params: Dictionary) -> Dictionary:
	var search_path: String = str(params.get("search_path", "res://test")).strip_edges()
	if search_path.is_empty():
		search_path = "res://test"
	var framework_filter: String = str(params.get("framework", "")).strip_edges().to_lower()

	var validation: Dictionary = _validate_test_path(search_path, true)
	if validation.has("error"):
		return validation
	search_path = String(validation["sanitized"])

	var absolute_root: String = ProjectSettings.globalize_path(search_path)
	var dir: DirAccess = DirAccess.open(absolute_root)
	if dir == null:
		return {"error": "Test directory not found: " + search_path}

	var gut_available: bool = FileAccess.file_exists("res://addons/gut/gut_cmdln.gd")
	var tests: Array = []
	_collect_project_tests_recursive(search_path, absolute_root, framework_filter, gut_available, tests)
	tests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("test_path", "")) < String(b.get("test_path", ""))
	)

	return {
		"count": tests.size(),
		"search_path": search_path,
		"tests": tests
	}

# ============================================================================
# run_project_test - 运行项目测试
# ============================================================================

func _register_run_project_test(server_core: RefCounted) -> void:
	server_core.register_tool(
		"run_project_test",
		"Run a single project test script. Python integration tests are executed with python. GUT unit tests are executed through Godot headless when addons/gut is available.",
		{
			"type": "object",
			"properties": {
				"test_path": {"type": "string", "description": "res:// path to a project test file under test/."},
				"timeout_ms": {"type": "integer", "description": "Reserved timeout hint for the caller. The process itself runs synchronously."}
			},
			"required": ["test_path"]
		},
		Callable(self, "_tool_run_project_test"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"framework": {"type": "string"},
				"test_path": {"type": "string"},
				"exit_code": {"type": "integer"},
				"command": {"type": "array"},
				"output": {"type": "array"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"supplementary", "Project-Advanced"
	)

func _tool_run_project_test(params: Dictionary) -> Dictionary:
	var test_path: String = str(params.get("test_path", "")).strip_edges()
	if test_path.is_empty():
		return {"error": "Missing required parameter: test_path"}

	var validation: Dictionary = _validate_test_path(test_path, false)
	if validation.has("error"):
		return validation
	test_path = String(validation["sanitized"])

	var extension: String = test_path.get_extension().to_lower()
	var absolute_test_path: String = ProjectSettings.globalize_path(test_path)
	if not FileAccess.file_exists(test_path):
		return {"error": "Test file not found: " + test_path}

	match extension:
		"py":
			return _run_python_project_test(test_path, absolute_test_path)
		"gd":
			return _run_gut_project_test(test_path)
		_:
			return {"error": "Unsupported project test type: " + extension}

func _register_run_project_tests(server_core: RefCounted) -> void:
	server_core.register_tool(
		"run_project_tests",
		"Discover and run multiple project tests from a directory. Reuses the same framework filters as list_project_tests and aggregates pass/fail counts.",
		{
			"type": "object",
			"properties": {
				"search_path": {"type": "string", "description": "Optional res:// path to limit discovery. Default is res://test."},
				"framework": {"type": "string", "description": "Optional framework filter: python or gut."},
				"only_runnable": {"type": "boolean", "description": "Whether to skip discovered tests that are not currently runnable. Default is true."}
			}
		},
		Callable(self, "_tool_run_project_tests"),
		{
			"type": "object",
			"properties": {
				"status": {"type": "string"},
				"search_path": {"type": "string"},
				"framework": {"type": "string"},
				"total_count": {"type": "integer"},
				"passed_count": {"type": "integer"},
				"failed_count": {"type": "integer"},
				"skipped_count": {"type": "integer"},
				"results": {"type": "array"}
			}
		},
		{"readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false},
		"supplementary", "Project-Advanced"
	)

func _tool_run_project_tests(params: Dictionary) -> Dictionary:
	var list_result: Dictionary = _tool_list_project_tests({
		"search_path": params.get("search_path", "res://test"),
		"framework": params.get("framework", "")
	})
	if list_result.has("error"):
		return list_result

	var only_runnable: bool = bool(params.get("only_runnable", true))
	var discovered_tests: Array = list_result.get("tests", [])
	var results: Array = []
	var passed_count: int = 0
	var failed_count: int = 0
	var skipped_count: int = 0

	for entry in discovered_tests:
		if not (entry is Dictionary):
			continue
		var test_entry: Dictionary = entry
		if only_runnable and not bool(test_entry.get("runnable", false)):
			skipped_count += 1
			results.append({
				"status": "skipped",
				"test_path": String(test_entry.get("test_path", "")),
				"framework": String(test_entry.get("framework", "")),
				"reason": "No available runner"
			})
			continue
		var test_result: Dictionary = _tool_run_project_test({"test_path": String(test_entry.get("test_path", ""))})
		results.append(test_result)
		if test_result.get("status", "") == "passed":
			passed_count += 1
		else:
			failed_count += 1

	var aggregate_status: String = "passed"
	if failed_count > 0:
		aggregate_status = "failed"
	elif passed_count == 0 and skipped_count > 0:
		aggregate_status = "skipped"

	return {
		"status": aggregate_status,
		"search_path": list_result.get("search_path", ""),
		"framework": str(params.get("framework", "")).strip_edges().to_lower(),
		"total_count": results.size(),
		"passed_count": passed_count,
		"failed_count": failed_count,
		"skipped_count": skipped_count,
		"results": results
	}

func _validate_test_path(path: String, expect_directory: bool) -> Dictionary:
	if path.is_empty():
		return {"error": "Test path cannot be empty"}
	if not path.begins_with("res://"):
		return {"error": "Test path must start with res://"}
	if not (path.begins_with("res://test/") or path.begins_with("res://.tmp_") or path.contains("/.tmp_")):
		return {"error": "Test path must stay under res://test/ or a temporary test directory"}
	var validation: Dictionary = PathValidator.validate_directory_path(path) if expect_directory else PathValidator.validate_path(path)
	if not validation.get("valid", false):
		return {"error": "Invalid path: " + str(validation.get("error", "unknown"))}
	return {"sanitized": String(validation.get("sanitized", path))}

func _collect_project_tests_recursive(search_path: String, absolute_root: String, framework_filter: String, gut_available: bool, tests: Array) -> void:
	var dir: DirAccess = DirAccess.open(absolute_root)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry_name: String = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue
		var child_res_path: String = search_path.path_join(entry_name)
		var child_abs_path: String = absolute_root.path_join(entry_name)
		if dir.current_is_dir():
			_collect_project_tests_recursive(child_res_path, child_abs_path, framework_filter, gut_available, tests)
			continue
		var extension: String = entry_name.get_extension().to_lower()
		var framework: String = ""
		var kind: String = ""
		var runnable: bool = false
		match extension:
			"py":
				framework = "python"
				kind = "integration"
				runnable = true
			"gd":
				framework = "gut"
				kind = "unit"
				runnable = gut_available
			_:
				continue
		if not framework_filter.is_empty() and framework != framework_filter:
			continue
		tests.append({
			"test_path": child_res_path,
			"framework": framework,
			"kind": kind,
			"runnable": runnable,
			"available_runner": runnable,
			"name": entry_name
		})
	dir.list_dir_end()

func _run_python_project_test(test_path: String, absolute_test_path: String) -> Dictionary:
	var logs: Array = []
	var started_at_ms: int = Time.get_ticks_msec()
	var python_cmd: String = _find_python_executable()
	var exit_code: int = OS.execute(python_cmd, [absolute_test_path], logs, true)
	var duration_ms: int = Time.get_ticks_msec() - started_at_ms
	var output: Array = []
	for line in logs:
		output.append(_sanitize_cli_output(str(line)))
	return {
		"status": "passed" if exit_code == OK else "failed",
		"framework": "python",
		"kind": "integration",
		"test_path": test_path,
		"exit_code": exit_code,
		"duration_ms": duration_ms,
		"command": [python_cmd, absolute_test_path],
		"output": output
	}

# Sanitize CLI output: remove control characters and ANSI escape sequences (ESC[...m etc.)
# that would break JSON.stringify() in Godot 4.x (which does not escape ESC/U+001B).
# Defense-in-depth: even if the subprocess doesn't use colors, this protects
# against any other control character in stdout.
func _sanitize_cli_output(text: String) -> String:
	var sanitized: String = ""
	var in_escape: bool = false
	var i: int = 0
	while i < text.length():
		var codepoint: int = text.unicode_at(i)
		
		# --- Handle ANSI escape sequences ---
		# ESC (27) starts an ANSI sequence: ESC[X... or ESC[X...letter
		if codepoint == 27:
			in_escape = true
			i += 1
			continue
		
		# Inside an escape sequence: skip everything until a letter (A-Z/a-z) ends it
		if in_escape:
			var is_letter: bool = (codepoint >= 65 and codepoint <= 90) or (codepoint >= 97 and codepoint <= 122)
			if is_letter:
				in_escape = false
			# For BEL (7) or ESC (27) inside an OSC sequence, also terminate
			if codepoint == 7 or codepoint == 27:
				in_escape = false
				if codepoint == 27:
					continue  # Re-process this potential start
			i += 1
			continue
		
		# --- Filter control characters ---
		var keep_char: bool = codepoint >= 32 and codepoint != 127
		if codepoint == 9 or codepoint == 10 or codepoint == 13:
			keep_char = true
		# Unicode Private Use Area (some terminals map glyphs here)
		if codepoint >= 0xE000 and codepoint <= 0xF8FF:
			keep_char = false
		# Unicode Replacement Character U+FFFD (65533) — keep, not a control char
		if keep_char:
			sanitized += String.chr(codepoint)
		i += 1
	
	# Second pass: clean up any residual CSI fragments like "[31m" or "[0m"
	# that remain if an ESC was consumed by another layer before reaching us.
	# CSI pattern: '[' followed by one or more params (digits/semicolons), then a letter.
	# Uses lookahead to avoid false positives (e.g. "Array[0]" or "[Passed]").
	var cleaned: String = ""
	var j: int = 0
	while j < sanitized.length():
		var c: int = sanitized.unicode_at(j)
		if c == 91:  # '['
			# Look ahead to validate full CSI sequence before consuming
			var scan_pos: int = j + 1
			var has_param: bool = false
			while scan_pos < sanitized.length():
				var sc: int = sanitized.unicode_at(scan_pos)
				var is_sc_param: bool = (sc >= 48 and sc <= 59)  # 0-9 or ;
				var is_sc_letter: bool = (sc >= 65 and sc <= 90) or (sc >= 97 and sc <= 122)  # A-Z a-z
				if is_sc_param:
					has_param = true
					scan_pos += 1
				elif is_sc_letter and has_param:
					# Valid CSI: '[' + params + letter — skip it all
					j = scan_pos + 1
					break
				else:
					# Not a CSI sequence — keep the '['
					cleaned += String.chr(91)
					j += 1
					break
			if scan_pos >= sanitized.length():
				# Reached end without completing a CSI sequence
				cleaned += String.chr(91)
				j += 1
			continue
		cleaned += String.chr(c)
		j += 1
	
	return cleaned

func _find_python_executable() -> String:
	var test_output: Array = []
	if OS.execute("python3", ["--version"], test_output, true) == OK:
		return "python3"
	test_output.clear()
	if OS.execute("python", ["--version"], test_output, true) == OK:
		return "python"
	return "python3"

func _run_gut_project_test(test_path: String) -> Dictionary:
	var gut_cmdln_path: String = "res://addons/gut/gut_cmdln.gd"
	if not FileAccess.file_exists(gut_cmdln_path):
		return {"error": "GUT is not installed at res://addons/gut/gut_cmdln.gd"}
	var executable_path: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	var args: Array[String] = [
		"--headless",
		"--path", project_path,
		"-s", gut_cmdln_path,
		"-gtest=" + test_path,
		"-gexit",
		"-gdisable_colors"
	]
	var logs: Array = []
	var started_at_ms: int = Time.get_ticks_msec()
	var exit_code: int = OS.execute(executable_path, args, logs, true)
	var duration_ms: int = Time.get_ticks_msec() - started_at_ms
	var output: Array = []
	for line in logs:
		output.append(_sanitize_cli_output(str(line)))
	return {
		"status": "passed" if exit_code == OK else "failed",
		"framework": "gut",
		"kind": "unit",
		"test_path": test_path,
		"exit_code": exit_code,
		"duration_ms": duration_ms,
		"command": [executable_path] + args,
		"output": output
	}

# ============================================================================
# inspect_csharp_project_support - 检查 C# / Mono 项目支持元数据
# ============================================================================

func _register_inspect_csharp_project_support(server_core: RefCounted) -> void:
	var tool_name: String = "inspect_csharp_project_support"
	var description: String = "Inspect C# / Mono project support files such as .csproj and .sln, including target frameworks, assembly metadata, and references."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {
				"type": "string",
				"description": "Directory to scan. Default is res://.",
				"default": "res://"
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {"type": "string"},
			"project_count": {"type": "integer"},
			"solution_count": {"type": "integer"},
			"projects": {"type": "array"},
			"solutions": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_inspect_csharp_project_support"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_inspect_csharp_project_support(params: Dictionary) -> Dictionary:
	var search_path: String = str(params.get("search_path", "res://")).strip_edges()
	var validation: Dictionary = PathValidator.validate_directory_path(search_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	search_path = validation["sanitized"]

	var project_paths: Array[String] = []
	var solution_paths: Array[String] = []
	_collect_resources(search_path, [".csproj"], project_paths)
	_collect_resources(search_path, [".sln"], solution_paths)
	project_paths.sort()
	solution_paths.sort()

	var projects: Array = []
	for project_path in project_paths:
		projects.append(_inspect_csproj_file(project_path))

	var solutions: Array = []
	for solution_path in solution_paths:
		solutions.append(_inspect_solution_file(solution_path))

	return {
		"search_path": search_path,
		"project_count": projects.size(),
		"solution_count": solutions.size(),
		"projects": projects,
		"solutions": solutions
	}

# ============================================================================
# compare_render_screenshots - 比较渲染截图
# ============================================================================

func _register_compare_render_screenshots(server_core: RefCounted) -> void:
	var tool_name: String = "compare_render_screenshots"
	var description: String = "Compare two screenshot images and report pixel differences, RMSE, and threshold-based match status."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"baseline_path": {
				"type": "string",
				"description": "Baseline screenshot image path."
			},
			"candidate_path": {
				"type": "string",
				"description": "Candidate screenshot image path."
			},
			"max_diff_pixels": {
				"type": "integer",
				"description": "Maximum differing pixels allowed for a passing match. Default is 0.",
				"default": 0
			}
		},
		"required": ["baseline_path", "candidate_path"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"baseline_path": {"type": "string"},
			"candidate_path": {"type": "string"},
			"width": {"type": "integer"},
			"height": {"type": "integer"},
			"diff_pixel_count": {"type": "integer"},
			"diff_ratio": {"type": "number"},
			"rmse": {"type": "number"},
			"max_channel_delta": {"type": "number"},
			"matches": {"type": "boolean"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_compare_render_screenshots"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_compare_render_screenshots(params: Dictionary) -> Dictionary:
	var baseline_path: String = str(params.get("baseline_path", "")).strip_edges()
	var candidate_path: String = str(params.get("candidate_path", "")).strip_edges()
	if baseline_path.is_empty():
		return {"error": "Missing required parameter: baseline_path"}
	if candidate_path.is_empty():
		return {"error": "Missing required parameter: candidate_path"}

	var baseline_validation: Dictionary = PathValidator.validate_file_path(baseline_path, [".png", ".jpg", ".jpeg", ".webp", ".bmp"])
	if not baseline_validation.get("valid", false):
		return {"error": baseline_validation.get("error", "Invalid baseline_path")}
	baseline_path = str(baseline_validation.get("sanitized", baseline_path))

	var candidate_validation: Dictionary = PathValidator.validate_file_path(candidate_path, [".png", ".jpg", ".jpeg", ".webp", ".bmp"])
	if not candidate_validation.get("valid", false):
		return {"error": candidate_validation.get("error", "Invalid candidate_path")}
	candidate_path = str(candidate_validation.get("sanitized", candidate_path))

	var baseline_image: Image = Image.load_from_file(ProjectSettings.globalize_path(baseline_path))
	var candidate_image: Image = Image.load_from_file(ProjectSettings.globalize_path(candidate_path))
	if baseline_image == null or baseline_image.is_empty():
		return {"error": "Failed to load baseline image: " + baseline_path}
	if candidate_image == null or candidate_image.is_empty():
		return {"error": "Failed to load candidate image: " + candidate_path}

	if baseline_image.get_width() != candidate_image.get_width() or baseline_image.get_height() != candidate_image.get_height():
		return {
			"baseline_path": baseline_path,
			"candidate_path": candidate_path,
			"width": baseline_image.get_width(),
			"height": baseline_image.get_height(),
			"candidate_width": candidate_image.get_width(),
			"candidate_height": candidate_image.get_height(),
			"matches": false,
			"error": "Image dimensions do not match"
		}

	var width: int = baseline_image.get_width()
	var height: int = baseline_image.get_height()
	var diff_pixel_count: int = 0
	var max_channel_delta: float = 0.0
	var squared_error_sum: float = 0.0

	for y in range(height):
		for x in range(width):
			var baseline_color: Color = baseline_image.get_pixel(x, y)
			var candidate_color: Color = candidate_image.get_pixel(x, y)
			var dr: float = absf(baseline_color.r - candidate_color.r)
			var dg: float = absf(baseline_color.g - candidate_color.g)
			var db: float = absf(baseline_color.b - candidate_color.b)
			var da: float = absf(baseline_color.a - candidate_color.a)
			var pixel_delta: float = maxf(maxf(dr, dg), maxf(db, da))
			if pixel_delta > 0.00001:
				diff_pixel_count += 1
			max_channel_delta = maxf(max_channel_delta, pixel_delta)
			squared_error_sum += dr * dr + dg * dg + db * db + da * da

	var total_pixels: int = width * height
	var total_channels: int = total_pixels * 4
	var rmse: float = sqrt(squared_error_sum / float(total_channels)) if total_channels > 0 else 0.0
	var diff_ratio: float = float(diff_pixel_count) / float(total_pixels) if total_pixels > 0 else 0.0
	var max_diff_pixels: int = max(0, int(params.get("max_diff_pixels", 0)))

	return {
		"baseline_path": baseline_path,
		"candidate_path": candidate_path,
		"width": width,
		"height": height,
		"diff_pixel_count": diff_pixel_count,
		"diff_ratio": diff_ratio,
		"rmse": rmse,
		"max_channel_delta": max_channel_delta,
		"matches": diff_pixel_count <= max_diff_pixels
	}

# ============================================================================
# inspect_tileset_resource - 检查 TileSet 资源
# ============================================================================

func _register_inspect_tileset_resource(server_core: RefCounted) -> void:
	var tool_name: String = "inspect_tileset_resource"
	var description: String = "Inspect a TileSet resource and summarize its sources, atlas tiles, and scene tiles."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {
				"type": "string",
				"description": "Path to a TileSet resource, such as 'res://tiles/terrain.tres'."
			},
			"include_tiles": {
				"type": "boolean",
				"description": "Whether to include per-tile entries for atlas and scene sources. Default is true."
			}
		},
		"required": ["resource_path"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {"type": "string"},
			"source_count": {"type": "integer"},
			"tile_size": {"type": "object"},
			"sources": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_inspect_tileset_resource"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_inspect_tileset_resource(params: Dictionary) -> Dictionary:
	var resource_path: String = str(params.get("resource_path", "")).strip_edges()
	if resource_path.is_empty():
		return {"error": "Missing required parameter: resource_path"}

	var validation: Dictionary = PathValidator.validate_file_path(resource_path, [".tres", ".res"])
	if not validation.get("valid", false):
		return {"error": validation.get("error", "Invalid resource path")}
	resource_path = str(validation.get("sanitized", resource_path))

	if not FileAccess.file_exists(resource_path):
		return {"error": "File not found: " + resource_path}

	var resource: Resource = ResourceLoader.load(resource_path)
	if resource == null:
		return {"error": "Failed to load resource: " + resource_path}
	if not (resource is TileSet):
		return {"error": "Resource is not a TileSet: " + resource_path}

	var tile_set: TileSet = resource as TileSet
	var include_tiles: bool = bool(params.get("include_tiles", true))
	var sources: Array = []
	for index in range(tile_set.get_source_count()):
		var source_id: int = tile_set.get_source_id(index)
		var source: TileSetSource = tile_set.get_source(source_id)
		sources.append(_serialize_tileset_source(source_id, source, include_tiles))

	return {
		"resource_path": resource_path,
		"source_count": tile_set.get_source_count(),
		"tile_size": _serialize_vector2i(tile_set.tile_size),
		"sources": sources
	}

# ============================================================================
# list_project_resources - 列出项目资源
# ============================================================================

func _register_list_project_resources(server_core: RefCounted) -> void:
	var tool_name: String = "list_project_resources"
	var description: String = "List all resource files in the project (.tres, .res, .png, .ogg, etc.)."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {
				"type": "string",
				"description": "Optional subpath to search. Default is 'res://'.",
				"default": "res://"
			},
			"resource_types": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Optional list of file extensions to filter (e.g. ['.tres', '.png']). Returns all if not provided."
			}
		}
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resources": {
				"type": "array",
				"items": {"type": "string"}
			},
			"count": {"type": "integer"}
		}
	}
	
	# annotations - readOnlyHint = true
	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_list_project_resources"),
						  output_schema, annotations,
						  "core", "Project")

func _tool_list_project_resources(params: Dictionary) -> Dictionary:
	# 参数提取
	var search_path: String = params.get("search_path", "res://")
	var resource_types: Array = params.get("resource_types", [])
	
	# 使用PathValidator验证路径安全性
	var validation: Dictionary = PathValidator.validate_directory_path(search_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	
	# 使用清理后的路径
	search_path = validation["sanitized"]
	
	# 常见资源扩展名
	var default_extensions: Array[String] = [
		".tres", ".res", ".otr", ".font", ".theme",
		".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".hdr",
		".ogg", ".wav", ".mp3", ".oggstr",
		".obj", ".glb", ".gltf", ".mesh", ".fbx",
		".material", ".shader", ".gdshader",
		".tscn", ".gd", ".cfg", ".json",
		".ttf", ".otf", ".woff", ".woff2"
	]
	
	# 如果提供了resource_types，使用它；否则使用默认扩展名
	var extensions: Array[String] = []
	if resource_types.size() > 0:
		for ext in resource_types:
			var ext_str: String = str(ext)
			if not ext_str.begins_with("."):
				ext_str = "." + ext_str
			extensions.append(ext_str)
	else:
		extensions = default_extensions
	
	# 使用DirAccess递归查找资源文件
	var resources: Array[String] = []
	_collect_resources(search_path, extensions, resources)
	
	# 排序
	resources.sort()
	
	return {
		"resources": resources,
		"count": resources.size()
	}

# 辅助函数：递归收集资源文件
func _collect_resources(directory_path: String, extensions: Array[String], result: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(directory_path)
	
	if not dir:
		return
	
	# 列出所有文件和目录
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	
	while not file_name.is_empty():
		# 跳过特殊目录
		if file_name != "." and file_name != "..":
			var full_path: String = directory_path
			if not full_path.ends_with("/"):
				full_path += "/"
			full_path += file_name
			
			if dir.current_is_dir():
				# 递归处理子目录
				_collect_resources(full_path, extensions, result)
			else:
				# 检查文件扩展名
				for ext in extensions:
					if file_name.ends_with(ext):
						result.append(full_path)
						break
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

# ============================================================================
# create_resource - 创建资源
# ============================================================================

func _register_create_resource(server_core: RefCounted) -> void:
	var tool_name: String = "create_resource"
	var description: String = "Create a new Godot resource file (.tres). Supports common resource types."
	
	# inputSchema
	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {
				"type": "string",
				"description": "Path where the resource will be saved (e.g. 'res://resources/my_curve.tres')"
			},
			"resource_type": {
				"type": "string",
				"description": "Type of resource to create (e.g. 'Curve', 'Gradient', 'StyleBoxFlat', 'Animation')"
			},
			"properties": {
				"type": "object",
				"description": "Optional dictionary of property values to set on the resource"
			}
		},
		"required": ["resource_path", "resource_type"]
	}
	
	# outputSchema
	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"resource_path": {"type": "string"},
			"resource_type": {"type": "string"}
		}
	}
	
	# annotations
	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": false,
		"openWorldHint": false
	}
	
	# 注册工具
	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_create_resource"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_create_resource(params: Dictionary) -> Dictionary:
	# 参数提取
	var resource_path: String = params.get("resource_path", "")
	var resource_type: String = params.get("resource_type", "")
	var properties: Dictionary = params.get("properties", {})
	
	# 参数验证
	if resource_path.is_empty():
		return {"error": "Missing required parameter: resource_path"}
	if resource_type.is_empty():
		return {"error": "Missing required parameter: resource_type"}
	
	# 使用PathValidator验证路径安全性
	var validation: Dictionary = PathValidator.validate_file_path(resource_path, [".tres", ".res"])
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	
	# 使用清理后的路径
	resource_path = validation["sanitized"]
	
	# 验证资源类型
	if not ClassDB.class_exists(resource_type):
		return {"error": "Invalid resource type: " + resource_type}
	
	if not ClassDB.is_parent_class(resource_type, "Resource"):
		return {"error": "Type '%s' is not a Resource type" % resource_type}
	
	# 创建资源实例
	var resource: RefCounted = ClassDB.instantiate(resource_type)
	
	if not resource:
		return {"error": "Failed to create resource of type: " + resource_type}
	
	# 设置属性（如果有）
	for prop_name in properties:
		if prop_name in resource:
			var converted_val: Variant = _convert_value_for_resource(resource, prop_name, properties[prop_name])
			resource.set(prop_name, converted_val)
	
	# 保存资源
	var error: Error = ResourceSaver.save(resource, resource_path)
	
	if error != OK:
		return {"error": "Failed to save resource: " + error_string(error)}
	
	return {
		"status": "success",
		"resource_path": resource_path,
		"resource_type": resource_type
	}

func _convert_value_for_resource(resource: Resource, property_name: String, value: Variant) -> Variant:
	if value == null:
		return value
	var property_type: int = TYPE_NIL
	for prop in resource.get_property_list():
		if prop["name"] == property_name:
			property_type = prop["type"]
			break
	if property_type == TYPE_NIL:
		return value
	match property_type:
		TYPE_VECTOR2:
			if value is Dictionary:
				return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
			if value is String:
				var parsed: Dictionary = _parse_key_value_string(value)
				if not parsed.is_empty():
					return Vector2(float(parsed.get("x", 0.0)), float(parsed.get("y", 0.0)))
				var parts: PackedStringArray = value.replace("Vector2", "").replace("(", "").replace(")", "").replace(" ", "").split(",")
				if parts.size() >= 2:
					return Vector2(float(parts[0]), float(parts[1]))
		TYPE_VECTOR3:
			if value is Dictionary:
				return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
			if value is String:
				var parsed: Dictionary = _parse_key_value_string(value)
				if not parsed.is_empty():
					return Vector3(float(parsed.get("x", 0.0)), float(parsed.get("y", 0.0)), float(parsed.get("z", 0.0)))
				var parts: PackedStringArray = value.replace("Vector3", "").replace("(", "").replace(")", "").replace(" ", "").split(",")
				if parts.size() >= 3:
					return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		TYPE_COLOR:
			if value is Dictionary:
				return Color(float(value.get("r", 0.0)), float(value.get("g", 0.0)), float(value.get("b", 0.0)), float(value.get("a", 1.0)))
			if value is String:
				if value.begins_with("#") or value.begins_with("Color"):
					return Color(value)
		TYPE_BOOL:
			if value is String:
				return value.to_lower() == "true"
			if value is int or value is float:
				return value != 0
		TYPE_INT:
			if value is String:
				return int(value)
			if value is float:
				return int(value)
		TYPE_FLOAT:
			if value is String:
				return float(value)
			if value is int:
				return float(value)
		TYPE_OBJECT:
			if value is String:
				if value.begins_with("res://"):
					var loaded_res: Resource = load(value)
					if loaded_res:
						return loaded_res
				if ClassDB.class_exists(value) and ClassDB.is_parent_class(value, "Resource"):
					return ClassDB.instantiate(value)
		TYPE_ARRAY:
			if value is Array:
				var result: Array = []
				for item in value:
					result.append(_convert_value_for_resource(resource, property_name, item))
				return result
		TYPE_DICTIONARY:
			if value is Dictionary:
				var result: Dictionary = {}
				for key in value:
					result[key] = _convert_value_for_resource(resource, property_name, value[key])
				return result
	return value

func _parse_key_value_string(value: String) -> Dictionary:
	if not (value.begins_with("{") and value.ends_with("}")):
		return {}
	var inner: String = value.substr(1, value.length() - 2).replace(" ", "")
	var result: Dictionary = {}
	var entries: PackedStringArray = inner.split(",")
	for entry in entries:
		var kv: PackedStringArray = entry.split(":")
		if kv.size() == 2:
			result[kv[0]] = kv[1]
	return result

# ============================================================================
# get_project_structure - 获取项目目录结构
# ============================================================================

func _register_get_project_structure(server_core: RefCounted) -> void:
	var tool_name: String = "get_project_structure"
	var description: String = "Get the project directory structure with file counts by extension. Returns directories and file type statistics."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"max_depth": {
				"type": "integer",
				"description": "Maximum directory depth to traverse. Default is 3.",
				"default": 3
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"directories": {"type": "array", "items": {"type": "string"}},
			"file_counts": {"type": "object"},
			"total_files": {"type": "integer"},
			"total_directories": {"type": "integer"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_project_structure"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_get_project_structure(params: Dictionary) -> Dictionary:
	var max_depth: int = params.get("max_depth", 3)
	var directories: Array = []
	var file_counts: Dictionary = {}

	_scan_directory("res://", directories, file_counts, 0, max_depth)

	var total_files: int = 0
	for ext in file_counts:
		total_files += file_counts[ext]

	return {
		"directories": directories,
		"file_counts": file_counts,
		"total_files": total_files,
		"total_directories": directories.size()
	}

func _scan_directory(path: String, directories: Array, file_counts: Dictionary, current_depth: int, max_depth: int) -> void:
	if current_depth > max_depth:
		return

	var dir: DirAccess = DirAccess.open(path)
	if not dir:
		return

	directories.append(path)

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full_path: String = path + file_name
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_directory(full_path + "/", directories, file_counts, current_depth + 1, max_depth)
		else:
			var ext: String = file_name.get_extension().to_lower()
			if not ext.is_empty() and ext != "import" and ext != "uid":
				if not file_counts.has(ext):
					file_counts[ext] = 0
				file_counts[ext] += 1
		file_name = dir.get_next()
	dir.list_dir_end()

# ============================================================================
# reimport_resources - 重新导入指定资源
# ============================================================================

func _register_reimport_resources(server_core: RefCounted) -> void:
	var tool_name: String = "reimport_resources"
	var description: String = "Reimport existing project resources using Godot's EditorFileSystem import pipeline."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_paths": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Resource source file paths to reimport, e.g. ['res://icon.png']"
			},
			"refresh_metadata": {
				"type": "boolean",
				"description": "Whether to refresh EditorFileSystem metadata with update_file() before reimport. Default is true.",
				"default": true
			}
		},
		"required": ["resource_paths"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"requested_count": {"type": "integer"},
			"reimported_count": {"type": "integer"},
			"resource_paths": {"type": "array"},
			"invalid_paths": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": false,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_reimport_resources"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_reimport_resources(params: Dictionary) -> Dictionary:
	var raw_paths: Array = params.get("resource_paths", [])
	if raw_paths.is_empty():
		return {"error": "Missing required parameter: resource_paths"}

	var refresh_metadata: bool = params.get("refresh_metadata", true)
	var editor_interface: EditorInterface = _get_editor_interface()
	if not editor_interface:
		return {"error": "Editor interface not available"}

	var fs: EditorFileSystem = editor_interface.get_resource_filesystem()
	if not fs:
		return {"error": "Failed to get EditorFileSystem"}

	if fs.is_scanning():
		return {
			"status": "busy",
			"requested_count": raw_paths.size(),
			"reimported_count": 0,
			"resource_paths": [],
			"invalid_paths": [],
			"scan_progress": fs.get_scanning_progress()
		}

	var valid_paths: Array[String] = []
	var invalid_paths: Array[Dictionary] = []
	for raw_path in raw_paths:
		var resource_path: String = str(raw_path).strip_edges()
		var validation: Dictionary = PathValidator.validate_path(resource_path)
		if not validation["valid"]:
			invalid_paths.append({"path": resource_path, "error": validation["error"]})
			continue
		resource_path = validation["sanitized"]
		if not FileAccess.file_exists(resource_path):
			invalid_paths.append({"path": resource_path, "error": "File not found"})
			continue
		valid_paths.append(resource_path)

	if valid_paths.is_empty():
		return {
			"status": "no_valid_paths",
			"requested_count": raw_paths.size(),
			"reimported_count": 0,
			"resource_paths": [],
			"invalid_paths": invalid_paths
		}

	if refresh_metadata:
		for resource_path in valid_paths:
			fs.update_file(resource_path)

	var packed_paths: PackedStringArray = PackedStringArray()
	for resource_path in valid_paths:
		packed_paths.append(resource_path)
	fs.reimport_files(packed_paths)

	return {
		"status": "success",
		"requested_count": raw_paths.size(),
		"reimported_count": valid_paths.size(),
		"resource_paths": valid_paths,
		"invalid_paths": invalid_paths
	}

# ============================================================================
# get_import_metadata - 读取 .import 元数据
# ============================================================================

func _register_get_import_metadata(server_core: RefCounted) -> void:
	var tool_name: String = "get_import_metadata"
	var description: String = "Read Godot import metadata for a source asset, including importer settings and imported artifact paths."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {
				"type": "string",
				"description": "Source asset path such as 'res://icon.png'"
			}
		},
		"required": ["resource_path"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {"type": "string"},
			"import_config_path": {"type": "string"},
			"exists": {"type": "boolean"},
			"importer": {"type": "string"},
			"resource_type": {"type": "string"},
			"uid": {"type": "string"},
			"imported_path": {"type": "string"},
			"sections": {"type": "object"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_import_metadata"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_get_import_metadata(params: Dictionary) -> Dictionary:
	var resource_path: String = str(params.get("resource_path", "")).strip_edges()
	if resource_path.is_empty():
		return {"error": "Missing required parameter: resource_path"}

	var validation: Dictionary = PathValidator.validate_path(resource_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	resource_path = validation["sanitized"]

	var import_config_path: String = resource_path + ".import"
	if not FileAccess.file_exists(import_config_path):
		return {
			"resource_path": resource_path,
			"import_config_path": import_config_path,
			"exists": false
		}

	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(import_config_path)
	if load_error != OK:
		return {"error": "Failed to load import metadata: " + error_string(load_error)}

	var sections: Dictionary = {}
	for raw_section in config.get_sections():
		var section_name: String = str(raw_section)
		var section_values: Dictionary = {}
		for raw_key in config.get_section_keys(section_name):
			var key_name: String = str(raw_key)
			section_values[key_name] = config.get_value(section_name, key_name)
		sections[section_name] = section_values

	var remap: Dictionary = sections.get("remap", {})
	var deps: Dictionary = sections.get("deps", {})
	var params_section: Dictionary = sections.get("params", {})

	return {
		"resource_path": resource_path,
		"import_config_path": import_config_path,
		"exists": true,
		"importer": str(remap.get("importer", "")),
		"resource_type": str(remap.get("type", "")),
		"uid": str(remap.get("uid", "")),
		"imported_path": str(remap.get("path", "")),
		"dependencies": deps,
		"params": params_section,
		"sections": sections
	}

# ============================================================================
# get_resource_uid_info - 读取资源 UID 信息
# ============================================================================

func _register_get_resource_uid_info(server_core: RefCounted) -> void:
	var tool_name: String = "get_resource_uid_info"
	var description: String = "Inspect Godot ResourceUID mappings for a resource path or uid:// identifier."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {
				"type": "string",
				"description": "Resource path to inspect."
			},
			"uid": {
				"type": "string",
				"description": "Optional uid:// identifier to resolve."
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {"type": "string"},
			"uid": {"type": "string"},
			"uid_id": {"type": "string"},
			"editor_uid": {"type": "string"},
			"resolved_path": {"type": "string"},
			"exists": {"type": "boolean"},
			"has_uid_mapping": {"type": "boolean"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_resource_uid_info"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_get_resource_uid_info(params: Dictionary) -> Dictionary:
	var resource_path: String = str(params.get("resource_path", "")).strip_edges()
	var uid_text: String = str(params.get("uid", "")).strip_edges()
	if resource_path.is_empty() and uid_text.is_empty():
		return {"error": "Provide resource_path or uid"}

	if not resource_path.is_empty():
		var validation: Dictionary = PathValidator.validate_path(resource_path)
		if not validation["valid"]:
			return {"error": "Invalid path: " + validation["error"]}
		resource_path = validation["sanitized"]
		if uid_text.is_empty():
			var mapped_uid: String = ResourceUID.path_to_uid(resource_path)
			if mapped_uid.begins_with("uid://"):
				uid_text = mapped_uid

	if not uid_text.is_empty() and not uid_text.begins_with("uid://"):
		return {"error": "uid must start with uid://"}

	var resolved_path: String = ""
	if not uid_text.is_empty():
		resolved_path = ResourceUID.uid_to_path(uid_text)
		if resource_path.is_empty():
			resource_path = resolved_path

	if not resource_path.is_empty() and uid_text.is_empty():
		var remapped_uid: String = ResourceUID.path_to_uid(resource_path)
		if remapped_uid.begins_with("uid://"):
			uid_text = remapped_uid
			resolved_path = ResourceUID.uid_to_path(uid_text)

	var effective_path: String = resource_path if not resource_path.is_empty() else resolved_path
	var exists: bool = not effective_path.is_empty() and FileAccess.file_exists(effective_path)
	var has_uid_mapping: bool = uid_text.begins_with("uid://")

	return {
		"resource_path": resource_path,
		"uid": uid_text,
		"uid_id": "",
		"resolved_path": resolved_path,
		"exists": exists,
		"has_uid_mapping": has_uid_mapping,
		"editor_uid": ""
	}

# ============================================================================
# fix_resource_uid - 生成或修复资源 UID
# ============================================================================

func _register_fix_resource_uid(server_core: RefCounted) -> void:
	var tool_name: String = "fix_resource_uid"
	var description: String = "Ensure a resource file has a persisted UID and refresh the editor filesystem mapping."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {
				"type": "string",
				"description": "Resource path to repair, e.g. 'res://resources/example.tres'"
			}
		},
		"required": ["resource_path"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"resource_path": {"type": "string"},
			"previous_uid": {"type": "string"},
			"uid": {"type": "string"},
			"uid_id": {"type": "string"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": false,
		"destructiveHint": false,
		"idempotentHint": false,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_fix_resource_uid"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_fix_resource_uid(params: Dictionary) -> Dictionary:
	var resource_path: String = str(params.get("resource_path", "")).strip_edges()
	if resource_path.is_empty():
		return {"error": "Missing required parameter: resource_path"}

	var validation: Dictionary = PathValidator.validate_path(resource_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	resource_path = validation["sanitized"]

	if not FileAccess.file_exists(resource_path):
		return {"error": "File not found: " + resource_path}

	var previous_uid: String = ResourceUID.path_to_uid(resource_path)
	if not previous_uid.begins_with("uid://"):
		previous_uid = ""

	var uid_id: int = ResourceSaver.get_resource_id_for_path(resource_path, true)
	if uid_id == ResourceUID.INVALID_ID:
		return {"error": "Failed to generate resource UID for: " + resource_path}

	var set_error: Error = ResourceSaver.set_uid(resource_path, uid_id)
	if set_error != OK:
		return {"error": "Failed to persist resource UID: " + error_string(set_error)}

	var editor_interface: EditorInterface = _get_editor_interface()
	if editor_interface:
		var fs: EditorFileSystem = editor_interface.get_resource_filesystem()
		if fs:
			fs.update_file(resource_path)

	var uid_text: String = ResourceUID.path_to_uid(resource_path)
	return {
		"status": "success",
		"resource_path": resource_path,
		"previous_uid": previous_uid,
		"uid": uid_text,
		"uid_id": str(uid_id)
	}

# ============================================================================
# get_resource_dependencies - 读取资源依赖
# ============================================================================

func _register_get_resource_dependencies(server_core: RefCounted) -> void:
	var tool_name: String = "get_resource_dependencies"
	var description: String = "List parsed resource dependencies using Godot's ResourceLoader dependency metadata."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {
				"type": "string",
				"description": "Resource path to inspect."
			}
		},
		"required": ["resource_path"]
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"resource_path": {"type": "string"},
			"dependency_count": {"type": "integer"},
			"dependencies": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_get_resource_dependencies"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_get_resource_dependencies(params: Dictionary) -> Dictionary:
	var resource_path: String = str(params.get("resource_path", "")).strip_edges()
	if resource_path.is_empty():
		return {"error": "Missing required parameter: resource_path"}

	var validation: Dictionary = PathValidator.validate_path(resource_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	resource_path = validation["sanitized"]

	if not FileAccess.file_exists(resource_path):
		return {"error": "File not found: " + resource_path}

	var dependencies: Array = _parse_resource_dependencies(resource_path)
	return {
		"resource_path": resource_path,
		"dependency_count": dependencies.size(),
		"dependencies": dependencies
	}

# ============================================================================
# scan_missing_resource_dependencies - 扫描缺失依赖
# ============================================================================

func _register_scan_missing_resource_dependencies(server_core: RefCounted) -> void:
	var tool_name: String = "scan_missing_resource_dependencies"
	var description: String = "Scan project resources for broken or missing dependency references."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {
				"type": "string",
				"description": "Directory to scan. Default is res://.",
				"default": "res://"
			},
			"max_results": {
				"type": "integer",
				"description": "Maximum missing dependency issues to return. Default is 200.",
				"default": 200
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {"type": "string"},
			"scanned_resources": {"type": "integer"},
			"issue_count": {"type": "integer"},
			"issues": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_scan_missing_resource_dependencies"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_scan_missing_resource_dependencies(params: Dictionary) -> Dictionary:
	var search_path: String = str(params.get("search_path", "res://")).strip_edges()
	var max_results: int = max(1, int(params.get("max_results", 200)))

	var validation: Dictionary = PathValidator.validate_directory_path(search_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	search_path = validation["sanitized"]

	var dependency_extensions: Array[String] = [
		".tscn", ".scn", ".tres", ".res", ".gd", ".cs", ".gdshader", ".material"
	]
	var resources: Array[String] = []
	_collect_resources(search_path, dependency_extensions, resources)
	resources.sort()

	var issues: Array = []
	for resource_path in resources:
		var dependencies: Array = _parse_resource_dependencies(resource_path)
		for dependency in dependencies:
			if bool(dependency.get("missing", false)):
				issues.append({
					"owner_path": resource_path,
					"dependency": dependency
				})
				if issues.size() >= max_results:
					return {
						"search_path": search_path,
						"scanned_resources": resources.size(),
						"issue_count": issues.size(),
						"issues": issues,
						"truncated": true
					}

	return {
		"search_path": search_path,
		"scanned_resources": resources.size(),
		"issue_count": issues.size(),
		"issues": issues,
		"truncated": false
	}

func _register_scan_cyclic_resource_dependencies(server_core: RefCounted) -> void:
	var tool_name: String = "scan_cyclic_resource_dependencies"
	var description: String = "Scan project resources for cyclic dependency chains based on parsed ResourceLoader dependency metadata."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {
				"type": "string",
				"description": "Directory to scan. Default is res://.",
				"default": "res://"
			},
			"max_results": {
				"type": "integer",
				"description": "Maximum cyclic dependency issues to return. Default is 100.",
				"default": 100
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {"type": "string"},
			"scanned_resources": {"type": "integer"},
			"issue_count": {"type": "integer"},
			"issues": {"type": "array"},
			"truncated": {"type": "boolean"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_scan_cyclic_resource_dependencies"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_scan_cyclic_resource_dependencies(params: Dictionary) -> Dictionary:
	var search_path: String = str(params.get("search_path", "res://")).strip_edges()
	var max_results: int = max(1, int(params.get("max_results", 100)))

	var validation: Dictionary = PathValidator.validate_directory_path(search_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	search_path = validation["sanitized"]

	var dependency_extensions: Array[String] = [
		".tscn", ".scn", ".tres", ".res", ".gd", ".cs", ".gdshader", ".material"
	]
	var resources: Array[String] = []
	_collect_resources(search_path, dependency_extensions, resources)
	resources.sort()

	var graph: Dictionary = {}
	for resource_path in resources:
		graph[resource_path] = _collect_existing_dependency_paths(resource_path)

	var issues: Array = []
	var seen_cycles: Dictionary = {}
	for resource_path in resources:
		var stack: Array = []
		var visiting: Dictionary = {}
		var cycle_paths: Array = []
		_find_cycles_from_resource(resource_path, graph, stack, visiting, seen_cycles, cycle_paths, max_results - issues.size())
		for cycle_path in cycle_paths:
			issues.append({
				"owner_path": resource_path,
				"cycle_path": cycle_path,
				"cycle_length": cycle_path.size() - 1
			})
			if issues.size() >= max_results:
				return {
					"search_path": search_path,
					"scanned_resources": resources.size(),
					"issue_count": issues.size(),
					"issues": issues,
					"truncated": true
				}

	return {
		"search_path": search_path,
		"scanned_resources": resources.size(),
		"issue_count": issues.size(),
		"issues": issues,
		"truncated": false
	}

func _parse_resource_dependencies(resource_path: String) -> Array:
	var dependencies: Array = []
	for raw_dependency in ResourceLoader.get_dependencies(resource_path):
		var raw_text: String = str(raw_dependency)
		var entry: Dictionary = {
			"raw": raw_text,
			"uid": "",
			"fallback_path": "",
			"resolved_path": "",
			"exists": false,
			"missing": false
		}

		if raw_text.contains("::"):
			entry["uid"] = raw_text.get_slice("::", 0)
			entry["fallback_path"] = raw_text.get_slice("::", 2)
			var resolved_path: String = ""
			if str(entry["uid"]).begins_with("uid://"):
				resolved_path = ResourceUID.uid_to_path(str(entry["uid"]))
			if resolved_path.is_empty():
				resolved_path = str(entry["fallback_path"])
			entry["resolved_path"] = resolved_path
		else:
			entry["fallback_path"] = raw_text
			entry["resolved_path"] = raw_text

		var resolved_exists: bool = false
		var resolved_path_str: String = str(entry["resolved_path"])
		var fallback_path_str: String = str(entry["fallback_path"])
		if not resolved_path_str.is_empty():
			resolved_exists = FileAccess.file_exists(resolved_path_str)
		if not resolved_exists and not fallback_path_str.is_empty():
			resolved_exists = FileAccess.file_exists(fallback_path_str)

		entry["exists"] = resolved_exists
		entry["missing"] = not resolved_exists
		dependencies.append(entry)

	return dependencies

func _collect_existing_dependency_paths(resource_path: String) -> Array:
	var paths: Array = []
	for dependency in _parse_resource_dependencies(resource_path):
		if bool(dependency.get("missing", false)):
			continue
		var resolved_path: String = str(dependency.get("resolved_path", ""))
		var fallback_path: String = str(dependency.get("fallback_path", ""))
		var effective_path: String = resolved_path if not resolved_path.is_empty() else fallback_path
		if effective_path.is_empty():
			continue
		if not paths.has(effective_path):
			paths.append(effective_path)
	return paths

func _find_cycles_from_resource(current_path: String, graph: Dictionary, stack: Array, visiting: Dictionary, seen_cycles: Dictionary, issues: Array, remaining_budget: int) -> void:
	if remaining_budget <= 0:
		return
	if bool(visiting.get(current_path, false)):
		var cycle_start: int = stack.find(current_path)
		if cycle_start >= 0:
			var cycle_path: Array = stack.slice(cycle_start)
			cycle_path.append(current_path)
			var cycle_key: String = _canonicalize_cycle_path(cycle_path)
			if not seen_cycles.has(cycle_key):
				seen_cycles[cycle_key] = true
				issues.append(cycle_path)
		return
	if stack.has(current_path):
		return

	visiting[current_path] = true
	stack.append(current_path)
	for dependency_path in graph.get(current_path, []):
		if not graph.has(dependency_path):
			continue
		_find_cycles_from_resource(dependency_path, graph, stack, visiting, seen_cycles, issues, remaining_budget - issues.size())
		if issues.size() >= remaining_budget:
			break
	stack.pop_back()
	visiting.erase(current_path)

func _canonicalize_cycle_path(cycle_path: Array) -> String:
	if cycle_path.size() <= 1:
		return JSON.stringify(cycle_path)
	var nodes: Array = cycle_path.slice(0, cycle_path.size() - 1)
	if nodes.is_empty():
		return JSON.stringify(cycle_path)
	var best_rotation: Array = []
	for start_index in range(nodes.size()):
		var rotated: Array = []
		for offset in range(nodes.size()):
			rotated.append(nodes[(start_index + offset) % nodes.size()])
		if best_rotation.is_empty() or JSON.stringify(rotated) < JSON.stringify(best_rotation):
			best_rotation = rotated
	best_rotation.append(best_rotation[0])
	return JSON.stringify(best_rotation)

# ============================================================================
# detect_broken_scripts - 批量检测脚本诊断
# ============================================================================

func _register_detect_broken_scripts(server_core: RefCounted) -> void:
	var tool_name: String = "detect_broken_scripts"
	var description: String = "Scan GDScript files for syntax errors and lightweight warnings."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {
				"type": "string",
				"description": "Directory to scan. Default is res://.",
				"default": "res://"
			},
			"include_warnings": {
				"type": "boolean",
				"description": "Whether to include lightweight warnings such as untyped var declarations. Default is true.",
				"default": true
			},
			"max_results": {
				"type": "integer",
				"description": "Maximum number of script issue entries to return. Default is 200.",
				"default": 200
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {"type": "string"},
			"scanned_scripts": {"type": "integer"},
			"broken_count": {"type": "integer"},
			"warning_count": {"type": "integer"},
			"issues": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_detect_broken_scripts"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_detect_broken_scripts(params: Dictionary) -> Dictionary:
	var search_path: String = str(params.get("search_path", "res://")).strip_edges()
	var include_warnings: bool = params.get("include_warnings", true)
	var max_results: int = max(1, int(params.get("max_results", 200)))

	var validation: Dictionary = PathValidator.validate_directory_path(search_path)
	if not validation["valid"]:
		return {"error": "Invalid path: " + validation["error"]}
	search_path = validation["sanitized"]

	var scripts: Array[String] = []
	_collect_resources(search_path, [".gd"], scripts)
	scripts.sort()

	var issues: Array = []
	var broken_count: int = 0
	var warning_count: int = 0

	for script_path in scripts:
		var diagnostics: Dictionary = _analyze_script_diagnostics(script_path, include_warnings)
		if diagnostics.has("error"):
			issues.append({
				"script_path": script_path,
				"severity": "error",
				"errors": [{"line": 0, "column": 0, "message": str(diagnostics["error"])}],
				"warnings": []
			})
			broken_count += 1
		else:
			var has_errors: bool = int(diagnostics.get("error_count", 0)) > 0
			var has_warnings: bool = int(diagnostics.get("warning_count", 0)) > 0
			var is_autoload_aware: bool = bool(diagnostics.get("autoload_aware", false))
			if is_autoload_aware and not has_errors:
				if has_warnings or include_warnings:
					issues.append({
						"script_path": script_path,
						"severity": "warning",
						"errors": diagnostics.get("errors", []),
						"warnings": diagnostics.get("warnings", [])
					})
					warning_count += 1
			elif has_errors or has_warnings:
				issues.append({
					"script_path": script_path,
					"severity": "error" if has_errors else "warning",
					"errors": diagnostics.get("errors", []),
					"warnings": diagnostics.get("warnings", [])
				})
				if has_errors:
					broken_count += 1
				if has_warnings:
					warning_count += 1

		if issues.size() >= max_results:
			break

	return {
		"search_path": search_path,
		"scanned_scripts": scripts.size(),
		"broken_count": broken_count,
		"warning_count": warning_count,
		"issues": issues,
		"truncated": issues.size() >= max_results and scripts.size() > issues.size()
	}

# ============================================================================
# audit_project_health - 汇总项目健康诊断
# ============================================================================

func _register_audit_project_health(server_core: RefCounted) -> void:
	var tool_name: String = "audit_project_health"
	var description: String = "Run a lightweight project health audit covering broken scripts and missing resource dependencies."

	var input_schema: Dictionary = {
		"type": "object",
		"properties": {
			"search_path": {
				"type": "string",
				"description": "Directory to scan. Default is res://.",
				"default": "res://"
			},
			"include_warnings": {
				"type": "boolean",
				"description": "Whether to include lightweight script warnings. Default is true.",
				"default": true
			},
			"max_results": {
				"type": "integer",
				"description": "Maximum issue entries per category. Default is 200.",
				"default": 200
			}
		}
	}

	var output_schema: Dictionary = {
		"type": "object",
		"properties": {
			"status": {"type": "string"},
			"search_path": {"type": "string"},
			"summary": {"type": "object"},
			"broken_scripts": {"type": "array"},
			"missing_dependencies": {"type": "array"},
			"cyclic_dependencies": {"type": "array"}
		}
	}

	var annotations: Dictionary = {
		"readOnlyHint": true,
		"destructiveHint": false,
		"idempotentHint": true,
		"openWorldHint": false
	}

	server_core.register_tool(tool_name, description, input_schema,
						  Callable(self, "_tool_audit_project_health"),
						  output_schema, annotations,
						  "supplementary", "Project-Advanced")

func _tool_audit_project_health(params: Dictionary) -> Dictionary:
	var search_path: String = str(params.get("search_path", "res://")).strip_edges()
	var include_warnings: bool = params.get("include_warnings", true)
	var max_results: int = max(1, int(params.get("max_results", 200)))

	var broken_scripts_result: Dictionary = _tool_detect_broken_scripts({
		"search_path": search_path,
		"include_warnings": include_warnings,
		"max_results": max_results
	})
	if broken_scripts_result.has("error"):
		return broken_scripts_result

	var missing_dependencies_result: Dictionary = _tool_scan_missing_resource_dependencies({
		"search_path": search_path,
		"max_results": max_results
	})
	if missing_dependencies_result.has("error"):
		return missing_dependencies_result

	var cyclic_dependencies_result: Dictionary = _tool_scan_cyclic_resource_dependencies({
		"search_path": search_path,
		"max_results": max_results
	})
	if cyclic_dependencies_result.has("error"):
		return cyclic_dependencies_result

	var summary: Dictionary = {
		"scanned_scripts": int(broken_scripts_result.get("scanned_scripts", 0)),
		"broken_scripts": int(broken_scripts_result.get("broken_count", 0)),
		"script_warnings": int(broken_scripts_result.get("warning_count", 0)),
		"scanned_resources": int(missing_dependencies_result.get("scanned_resources", 0)),
		"missing_dependencies": int(missing_dependencies_result.get("issue_count", 0)),
		"cyclic_dependencies": int(cyclic_dependencies_result.get("issue_count", 0))
	}
	var hard_failures: int = summary["broken_scripts"] + summary["missing_dependencies"] + summary["cyclic_dependencies"]
	var status: String = "healthy"
	if hard_failures > 0:
		status = "failing"
	elif summary["script_warnings"] > 0:
		status = "warning"

	return {
		"status": status,
		"search_path": broken_scripts_result.get("search_path", search_path),
		"summary": summary,
		"broken_scripts": broken_scripts_result.get("issues", []),
		"missing_dependencies": missing_dependencies_result.get("issues", []),
		"cyclic_dependencies": cyclic_dependencies_result.get("issues", []),
		"truncated": bool(broken_scripts_result.get("truncated", false)) or bool(missing_dependencies_result.get("truncated", false)) or bool(cyclic_dependencies_result.get("truncated", false))
	}

func _analyze_script_diagnostics(script_path: String, include_warnings: bool) -> Dictionary:
	var file: FileAccess = FileAccess.open(script_path, FileAccess.READ)
	if not file:
		return {"error": "Failed to open file"}
	var content: String = file.get_as_text()
	file.close()

	var validation_content: String = _strip_class_names(content)
	var test_script: GDScript = GDScript.new()
	test_script.source_code = validation_content
	var reload_error: Error = test_script.reload()

	var errors: Array = []
	var warnings: Array = []
	var autoload_aware: bool = false

	if reload_error != OK:
		var autoload_decls: String = _build_autoload_declarations()
		if not autoload_decls.is_empty():
			var retry_content: String = autoload_decls + "\n" + validation_content
			var retry_script: GDScript = GDScript.new()
			retry_script.source_code = retry_content
			var retry_err: Error = retry_script.reload()
			if retry_err == OK:
				autoload_aware = true
				if include_warnings:
					warnings.append({
						"line": 0,
						"column": 0,
						"message": "Script validates successfully with Autoload/global class awareness"
					})
		if not autoload_aware:
			var source_lines: PackedStringArray = content.split("\n")
			for i in range(source_lines.size()):
				var line: String = source_lines[i].strip_edges()
				if line.is_empty():
					continue
				if _is_likely_script_error_line(line):
					errors.append({
						"line": i + 1,
						"column": 0,
						"message": "Syntax error near: " + line
					})
					break
			if errors.is_empty():
				errors.append({
					"line": 0,
					"column": 0,
					"message": "Script has syntax errors"
				})

	if include_warnings and reload_error == OK:
		var source_lines_for_warning: PackedStringArray = content.split("\n")
		for i in range(source_lines_for_warning.size()):
			var warning_line: String = source_lines_for_warning[i].strip_edges()
			if warning_line.begins_with("var ") and not ":" in warning_line and not "=" in warning_line:
				warnings.append({
					"line": i + 1,
					"column": 0,
					"message": "Variable lacks type hint"
				})

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"error_count": errors.size(),
		"warning_count": warnings.size(),
		"autoload_aware": autoload_aware
	}

func _strip_class_names(source: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var result: PackedStringArray = []
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.begins_with("class_name "):
			result.append("")
		else:
			result.append(line)
	return "\n".join(result)

func _build_autoload_declarations() -> String:
	var decls: PackedStringArray = []
	for property_info in ProjectSettings.get_property_list():
		var property_name: String = str(property_info.get("name", ""))
		if not property_name.begins_with("autoload/"):
			continue
		var autoload_name: String = property_name.trim_prefix("autoload/")
		decls.append("var %s" % autoload_name)
	var global_classes: PackedStringArray = ProjectSettings.get_global_class_list()
	for class_name_str in global_classes:
		if not class_name_str.is_empty():
			decls.append("var %s" % class_name_str)
	return "\n".join(decls)

func _is_likely_script_error_line(line: String) -> bool:
	var line_lower: String = line.to_lower()
	if line_lower.contains("unexpected") or line_lower.contains("expected") or line_lower.contains("indent"):
		return true
	if line.ends_with("(") or line.ends_with(",") or line.count("\"") % 2 == 1:
		return true
	return false

func _collect_project_autoloads_from_properties(properties: Array, values_by_name: Dictionary, orders_by_name: Dictionary) -> Array:
	var autoloads: Array = []
	for property_info in properties:
		var property_name: String = str(property_info.get("name", ""))
		if not property_name.begins_with("autoload/"):
			continue
		var raw_value: String = str(values_by_name.get(property_name, ""))
		var is_singleton: bool = raw_value.begins_with("*")
		var resolved_path: String = raw_value.substr(1) if is_singleton else raw_value
		autoloads.append({
			"name": property_name.get_slice("/", 1),
			"path": resolved_path.simplify_path(),
			"is_singleton": is_singleton,
			"order": int(orders_by_name.get(property_name, 0)),
			"setting_name": property_name,
			"raw_value": raw_value
		})
	autoloads.sort_custom(Callable(self, "_compare_autoload_entries"))
	return autoloads

func _normalize_global_class_entries(entries: Array) -> Array:
	var classes: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		classes.append({
			"name": str(entry.get("class", "")),
			"path": str(entry.get("path", "")),
			"base": str(entry.get("base", "")),
			"language": str(entry.get("language", "")),
			"is_tool": bool(entry.get("is_tool", false)),
			"is_abstract": bool(entry.get("is_abstract", false)),
			"icon": str(entry.get("icon", ""))
		})
	classes.sort_custom(Callable(self, "_compare_global_class_entries"))
	return classes

func _find_project_global_class_entry(target_class_name: String) -> Dictionary:
	if not ProjectSettings.has_method("get_global_class_list"):
		return {}
	for entry in ProjectSettings.get_global_class_list():
		if not (entry is Dictionary):
			continue
		if str(entry.get("class", "")) == target_class_name:
			return entry
	return {}

func _build_classdb_api_metadata(target_class_name: String, filter: String = "") -> Dictionary:
	return {
		"class_name": target_class_name,
		"source": "classdb",
		"base_class": ClassDB.get_parent_class(target_class_name),
		"api_type": ClassDB.class_get_api_type(target_class_name),
		"methods": _normalize_method_entries(ClassDB.class_get_method_list(target_class_name), filter),
		"properties": _normalize_property_entries(ClassDB.class_get_property_list(target_class_name), filter),
		"signals": _normalize_signal_entries(ClassDB.class_get_signal_list(target_class_name), filter),
		"constants": _normalize_constant_entries(target_class_name, filter)
	}

func _normalize_method_entries(entries: Array, filter: String = "") -> Array:
	var methods: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var method_name: String = str(entry.get("name", ""))
		if method_name.is_empty():
			continue
		if not filter.is_empty() and not method_name.to_lower().contains(filter):
			continue
		methods.append({
			"name": method_name,
			"flags": int(entry.get("flags", 0)),
			"id": int(entry.get("id", 0)),
			"return": _normalize_typed_value_info(entry.get("return", {})),
			"arguments": _normalize_typed_value_info_array(entry.get("args", [])),
			"default_argument_count": entry.get("default_args", []).size()
		})
	methods.sort_custom(Callable(self, "_compare_named_entries"))
	return methods

func _normalize_property_entries(entries: Array, filter: String = "") -> Array:
	var properties: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var property_name: String = str(entry.get("name", ""))
		if property_name.is_empty():
			continue
		if not filter.is_empty() and not property_name.to_lower().contains(filter):
			continue
		properties.append({
			"name": property_name,
			"type": int(entry.get("type", TYPE_NIL)),
			"class_name": str(entry.get("class_name", "")),
			"hint": int(entry.get("hint", PROPERTY_HINT_NONE)),
			"hint_string": str(entry.get("hint_string", "")),
			"usage": int(entry.get("usage", 0)),
			"setter": str(entry.get("setter", "")),
			"getter": str(entry.get("getter", ""))
		})
	properties.sort_custom(Callable(self, "_compare_named_entries"))
	return properties

func _normalize_signal_entries(entries: Array, filter: String = "") -> Array:
	var signals: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var signal_name: String = str(entry.get("name", ""))
		if signal_name.is_empty():
			continue
		if not filter.is_empty() and not signal_name.to_lower().contains(filter):
			continue
		signals.append({
			"name": signal_name,
			"flags": int(entry.get("flags", 0)),
			"id": int(entry.get("id", 0)),
			"arguments": _normalize_typed_value_info_array(entry.get("args", []))
		})
	signals.sort_custom(Callable(self, "_compare_named_entries"))
	return signals

func _normalize_constant_entries(target_class_name: String, filter: String = "") -> Array:
	var constants: Array = []
	for constant_name in ClassDB.class_get_integer_constant_list(target_class_name):
		var constant_name_text: String = str(constant_name)
		if not filter.is_empty() and not constant_name_text.to_lower().contains(filter):
			continue
		constants.append({
			"name": constant_name_text,
			"value": ClassDB.class_get_integer_constant(target_class_name, constant_name_text),
			"enum": str(ClassDB.class_get_integer_constant_enum(target_class_name, constant_name_text))
		})
	constants.sort_custom(Callable(self, "_compare_named_entries"))
	return constants

func _normalize_typed_value_info_array(entries: Array) -> Array:
	var normalized: Array = []
	for entry in entries:
		normalized.append(_normalize_typed_value_info(entry))
	return normalized

func _normalize_typed_value_info(entry: Variant) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	return {
		"name": str(entry.get("name", "")),
		"type": int(entry.get("type", TYPE_NIL)),
		"class_name": str(entry.get("class_name", "")),
		"hint": int(entry.get("hint", PROPERTY_HINT_NONE)),
		"hint_string": str(entry.get("hint_string", "")),
		"usage": int(entry.get("usage", 0))
	}

func _collect_project_input_actions(action_name_filter: String = "") -> Array:
	var actions: Array = []
	for property_info in ProjectSettings.get_property_list():
		var property_name: String = str(property_info.get("name", ""))
		if not property_name.begins_with("input/"):
			continue
		var action_name: String = property_name.get_slice("/", 1)
		if not action_name_filter.is_empty() and action_name != action_name_filter:
			continue
		var raw_value: Variant = ProjectSettings.get_setting(property_name, {})
		if not (raw_value is Dictionary):
			continue
		var stored_events: Array = raw_value.get("events", [])
		var events: Array = []
		for stored_event in stored_events:
			if stored_event is InputEvent:
				events.append(_serialize_project_input_event(stored_event))
		actions.append({
			"action_name": action_name,
			"deadzone": float(raw_value.get("deadzone", 0.5)),
			"events": events,
			"event_count": events.size(),
			"setting_name": property_name
		})
	actions.sort_custom(Callable(self, "_sort_project_input_actions"))
	return actions

func _build_project_input_event(payload: Dictionary) -> InputEvent:
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
			_apply_project_input_modifiers(key_event, payload)
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
			mouse_button_event.position = _dict_to_project_vector2(payload.get("position", {}))
			mouse_button_event.global_position = _dict_to_project_vector2(payload.get("global_position", payload.get("position", {})))
			_apply_project_input_modifiers(mouse_button_event, payload)
			return mouse_button_event
		"mouse_motion":
			var mouse_motion_event := InputEventMouseMotion.new()
			mouse_motion_event.position = _dict_to_project_vector2(payload.get("position", {}))
			mouse_motion_event.global_position = _dict_to_project_vector2(payload.get("global_position", payload.get("position", {})))
			mouse_motion_event.relative = _dict_to_project_vector2(payload.get("relative", {}))
			mouse_motion_event.velocity = _dict_to_project_vector2(payload.get("velocity", {}))
			mouse_motion_event.button_mask = int(payload.get("button_mask", 0))
			mouse_motion_event.pressure = float(payload.get("pressure", 0.0))
			mouse_motion_event.pen_inverted = bool(payload.get("pen_inverted", false))
			_apply_project_input_modifiers(mouse_motion_event, payload)
			return mouse_motion_event
		_:
			return null

func _apply_project_input_modifiers(event: InputEventWithModifiers, payload: Dictionary) -> void:
	event.alt_pressed = bool(payload.get("alt_pressed", false))
	event.shift_pressed = bool(payload.get("shift_pressed", false))
	event.ctrl_pressed = bool(payload.get("ctrl_pressed", false))
	event.meta_pressed = bool(payload.get("meta_pressed", false))
	event.command_or_control_autoremap = bool(payload.get("command_or_control_autoremap", false))

func _dict_to_project_vector2(value: Variant) -> Vector2:
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO

func _serialize_project_input_event(event: InputEvent) -> Dictionary:
	if event is InputEventAction:
		return {
			"type": "action",
			"action_name": String(event.action),
			"pressed": event.pressed,
			"strength": event.strength
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
	return {"type": "unknown", "class": event.get_class()}

func _inspect_csproj_file(project_path: String) -> Dictionary:
	var parser := XMLParser.new()
	var open_error: Error = parser.open(project_path)
	if open_error != OK:
		return {"path": project_path, "error": "Failed to open csproj: " + str(open_error)}

	var result: Dictionary = {
		"path": project_path,
		"sdk": "",
		"target_frameworks": [],
		"assembly_name": "",
		"root_namespace": "",
		"nullable": "",
		"lang_version": "",
		"package_references": [],
		"project_references": []
	}
	var current_text_field: String = ""

	while true:
		var read_error: Error = parser.read()
		if read_error == ERR_FILE_EOF:
			break
		if read_error != OK:
			result["error"] = "Failed to parse csproj: " + str(read_error)
			break

		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name: String = parser.get_node_name()
				match node_name:
					"Project":
						result["sdk"] = parser.get_named_attribute_value_safe("Sdk")
					"TargetFramework", "TargetFrameworks", "AssemblyName", "RootNamespace", "Nullable", "LangVersion":
						current_text_field = node_name
					"PackageReference":
						result["package_references"].append({
							"include": parser.get_named_attribute_value_safe("Include"),
							"version": parser.get_named_attribute_value_safe("Version"),
							"condition": parser.get_named_attribute_value_safe("Condition")
						})
					"ProjectReference":
						result["project_references"].append({
							"include": parser.get_named_attribute_value_safe("Include"),
							"name": parser.get_named_attribute_value_safe("Name")
						})
			XMLParser.NODE_TEXT:
				if current_text_field.is_empty():
					continue
				var text_value: String = parser.get_node_data().strip_edges()
				if text_value.is_empty():
					continue
				match current_text_field:
					"TargetFramework":
						result["target_frameworks"] = [text_value]
					"TargetFrameworks":
						result["target_frameworks"] = _split_semicolon_values(text_value)
					"AssemblyName":
						result["assembly_name"] = text_value
					"RootNamespace":
						result["root_namespace"] = text_value
					"Nullable":
						result["nullable"] = text_value
					"LangVersion":
						result["lang_version"] = text_value
			XMLParser.NODE_ELEMENT_END:
				current_text_field = ""

	return result

func _inspect_solution_file(solution_path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(solution_path, FileAccess.READ)
	if not file:
		return {"path": solution_path, "error": "Failed to open solution file"}

	var entries: Array = []
	while not file.eof_reached():
		var raw_line: String = file.get_line()
		var line: String = raw_line.strip_edges()
		if not line.begins_with("Project("):
			continue
		var marker_index: int = line.find(" = ")
		if marker_index == -1:
			continue
		var tail: String = line.substr(marker_index + 3)
		var segments: PackedStringArray = tail.split(",")
		if segments.size() < 2:
			continue
		entries.append({
			"name": segments[0].strip_edges().trim_prefix("\"").trim_suffix("\""),
			"path": segments[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
		})
	file.close()

	return {
		"path": solution_path,
		"project_count": entries.size(),
		"projects": entries
	}

func _split_semicolon_values(value: String) -> Array:
	var values: Array = []
	for segment in value.split(";"):
		var trimmed: String = segment.strip_edges()
		if not trimmed.is_empty():
			values.append(trimmed)
	return values

func _serialize_tileset_source(source_id: int, source: TileSetSource, include_tiles: bool) -> Dictionary:
	var source_entry: Dictionary = {
		"source_id": source_id,
		"class_name": source.get_class(),
		"tile_count": source.get_tiles_count()
	}

	if source is TileSetAtlasSource:
		var atlas_source: TileSetAtlasSource = source as TileSetAtlasSource
		var texture: Texture2D = atlas_source.texture
		source_entry["source_type"] = "atlas"
		source_entry["texture_path"] = texture.resource_path if texture else ""
		source_entry["texture_size"] = _serialize_vector2(texture.get_size()) if texture else {}
		source_entry["margins"] = _serialize_vector2i(atlas_source.margins)
		source_entry["separation"] = _serialize_vector2i(atlas_source.separation)
		source_entry["texture_region_size"] = _serialize_vector2i(atlas_source.texture_region_size)
		source_entry["atlas_grid_size"] = _serialize_vector2i(atlas_source.get_atlas_grid_size())
		source_entry["uses_texture_padding"] = atlas_source.use_texture_padding
		if include_tiles:
			var atlas_tiles: Array = []
			for tile_index in range(atlas_source.get_tiles_count()):
				var atlas_coords: Vector2i = atlas_source.get_tile_id(tile_index)
				var alternatives: Array = []
				for alt_index in range(atlas_source.get_alternative_tiles_count(atlas_coords)):
					alternatives.append(atlas_source.get_alternative_tile_id(atlas_coords, alt_index))
				atlas_tiles.append({
					"atlas_coords": _serialize_vector2i(atlas_coords),
					"size_in_atlas": _serialize_vector2i(atlas_source.get_tile_size_in_atlas(atlas_coords)),
					"texture_region": _serialize_rect2i(atlas_source.get_tile_texture_region(atlas_coords)),
					"alternative_ids": alternatives,
					"alternative_count": alternatives.size()
				})
			source_entry["tiles"] = atlas_tiles
	elif source is TileSetScenesCollectionSource:
		var scenes_source: TileSetScenesCollectionSource = source as TileSetScenesCollectionSource
		source_entry["source_type"] = "scenes_collection"
		source_entry["scene_tile_count"] = scenes_source.get_scene_tiles_count()
		if include_tiles:
			var scene_tiles: Array = []
			for tile_index in range(scenes_source.get_scene_tiles_count()):
				var scene_tile_id: int = scenes_source.get_scene_tile_id(tile_index)
				var packed_scene: PackedScene = scenes_source.get_scene_tile_scene(scene_tile_id)
				scene_tiles.append({
					"scene_tile_id": scene_tile_id,
					"scene_path": packed_scene.resource_path if packed_scene else ""
				})
			source_entry["scene_tiles"] = scene_tiles
	else:
		source_entry["source_type"] = "unknown"

	return source_entry

func _serialize_vector2i(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}

func _serialize_vector2(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}

func _serialize_rect2i(value: Rect2i) -> Dictionary:
	return {
		"position": _serialize_vector2i(value.position),
		"size": _serialize_vector2i(value.size)
	}

func _compare_autoload_entries(left: Dictionary, right: Dictionary) -> bool:
	var left_order: int = int(left.get("order", 0))
	var right_order: int = int(right.get("order", 0))
	if left_order == right_order:
		return str(left.get("name", "")) < str(right.get("name", ""))
	return left_order < right_order

func _compare_global_class_entries(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("name", "")) < str(right.get("name", ""))

func _compare_named_entries(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("name", "")) < str(right.get("name", ""))

func _sort_project_input_actions(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("action_name", "")) < str(right.get("action_name", ""))
