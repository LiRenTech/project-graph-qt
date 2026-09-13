class_name MCPToolStateManager
extends "res://addons/godot_mcp/native_mcp/config_manager.gd"

const CONFIG_FILE_NAME: String = "mcp_tool_state.cfg"
const SECTION_TOOLS: String = "tools"

var _classifier = null

func _init() -> void:
	config_file_name = CONFIG_FILE_NAME
	config_section = SECTION_TOOLS
	storage_version = 1
	_classifier = load("res://addons/godot_mcp/native_mcp/mcp_tool_classifier.gd").new()

func load_state() -> Dictionary:
	return load_config()

func save_state(enabled_states: Dictionary) -> bool:
	return save_config(enabled_states)

func apply_states_to_server(server_core: MCPServerCore, states: Dictionary) -> void:
	for tool_name in states:
		if server_core.has_tool(tool_name):
			var enabled: bool = states[tool_name]
			server_core.set_tool_enabled(tool_name, enabled)

func capture_states_from_server(server_core: MCPServerCore) -> Dictionary:
	var states: Dictionary = {}
	var tools = server_core.get_registered_tools()
	for tool_info in tools:
		states[tool_info["name"]] = tool_info["enabled"]
	return states

func validate_core_tool_limit(states: Dictionary) -> Dictionary:
	var core_tools: Array[String] = _classifier.get_core_tools()
	var enabled_core_count: int = 0
	var core_limit: int = _classifier.get_core_max_count()

	for tool_name in core_tools:
		var is_enabled: bool = states.get(tool_name, true)
		if is_enabled:
			enabled_core_count += 1

	var over_limit: bool = enabled_core_count > core_limit
	return {
		"over_limit": over_limit,
		"enabled_core_count": enabled_core_count,
		"core_limit": core_limit,
		"message": "Core tools enabled: %d/%d" % [enabled_core_count, core_limit]
	}