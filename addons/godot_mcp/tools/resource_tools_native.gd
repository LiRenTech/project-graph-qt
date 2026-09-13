# resource_tools_native.gd
# 资源工具 - 实现 MCP 资源读取功能
# 版本: 1.0
# 作者: AI Assistant
# 日期: 2026-05-01

@tool
class_name ResourceToolsNative
extends RefCounted

var _editor_interface: EditorInterface = null
var _base_control: Control = null
var _log_callback: Callable = Callable()

func set_log_callback(callback: Callable) -> void:
	_log_callback = callback

func initialize(editor_interface: EditorInterface, base_control: Control) -> void:
	_editor_interface = editor_interface
	_base_control = base_control
	if _log_callback.is_valid():
		_log_callback.call("INFO", "初始化完成")

# ===========================================
# 资源读取功能
# ===========================================

## 读取场景列表资源
func _resource_scene_list(params: Dictionary) -> Dictionary:
	var scenes: Array = []
	var dir = DirAccess.open("res://")

	if not dir:
		return {"contents": [{"uri": "godot://scene/list", "mimeType": "application/json", "text": "{}"}]}

	_find_files_recursive(dir, ".tscn", scenes)

	return {
		"contents": [{
			"uri": "godot://scene/list",
			"mimeType": "application/json",
			"text": JSON.stringify({
				"scenes": scenes,
				"count": scenes.size(),
				"timestamp": Time.get_unix_time_from_system()
			}, "\t", true)
		}]
	}

## 读取当前场景资源
func _resource_scene_current(params: Dictionary) -> Dictionary:
	if not _editor_interface:
		return {"contents": [{"uri": "godot://scene/current", "mimeType": "application/json", "text": "{}"}]}

	var scene_root: Node = _editor_interface.get_edited_scene_root()
	if not scene_root:
		return {"contents": [{"uri": "godot://scene/current", "mimeType": "application/json", "text": "{}"}]}

	var scene_info: Dictionary = {
		"name": scene_root.name,
		"path": scene_root.scene_file_path,
		"type": scene_root.get_class(),
		"node_count": _count_nodes(scene_root),
		"children": _get_node_tree(scene_root, 2)
	}

	return {
		"contents": [{
			"uri": "godot://scene/current",
			"mimeType": "application/json",
			"text": JSON.stringify(scene_info, "\t", true)
		}]
	}

## 读取脚本列表资源
func _resource_script_list(params: Dictionary) -> Dictionary:
	var scripts: Array = []
	var dir = DirAccess.open("res://")

	if not dir:
		return {"contents": [{"uri": "godot://script/list", "mimeType": "application/json", "text": "{}"}]}

	_find_files_recursive(dir, ".gd", scripts)

	return {
		"contents": [{
			"uri": "godot://script/list",
			"mimeType": "application/json",
			"text": JSON.stringify({
				"scripts": scripts,
				"count": scripts.size(),
				"timestamp": Time.get_unix_time_from_system()
			}, "\t", true)
		}]
	}

## 读取当前脚本资源
func _resource_script_current(params: Dictionary) -> Dictionary:
	if not _editor_interface:
		return {"contents": [{"uri": "godot://script/current", "mimeType": "application/json", "text": "{}"}]}

	var script_editor = _editor_interface.get_script_editor()
	if not script_editor:
		return {"contents": [{"uri": "godot://script/current", "mimeType": "application/json", "text": "{}"}]}

	var current_script = script_editor.get_current_script()
	if not current_script:
		return {"contents": [{"uri": "godot://script/current", "mimeType": "application/json", "text": "{}"}]}

	var script_path: String = current_script.resource_path
	if not FileAccess.file_exists(script_path):
		return {"contents": [{"uri": "godot://script/current", "mimeType": "application/json", "text": "{}"}]}

	var file = FileAccess.open(script_path, FileAccess.READ)
	if not file:
		return {"contents": [{"uri": "godot://script/current", "mimeType": "application/json", "text": "{}"}]}

	var script_content: String = file.get_as_text()
	file.close()

	var line_count: int = 0
	if not script_content.is_empty():
		line_count = script_content.split("\n").size()

	var script_info: Dictionary = {
		"path": script_path,
		"name": current_script.get_class(),
		"content": script_content,
		"line_count": line_count,
		"timestamp": Time.get_unix_time_from_system()
	}

	return {
		"contents": [{
			"uri": "godot://script/current",
			"mimeType": "application/json",
			"text": JSON.stringify(script_info, "\t", true)
		}]
	}

## 读取项目信息资源
func _resource_project_info(params: Dictionary) -> Dictionary:
	var project_info: Dictionary = {
		"name": ProjectSettings.get_setting("application/config/name", "未命名项目"),
		"version": ProjectSettings.get_setting("application/config/version", "1.0"),
		"description": ProjectSettings.get_setting("application/config/description", ""),
		"author": ProjectSettings.get_setting("application/config/author", ""),
		"godot_version": _get_godot_version(),
		"project_path": OS.get_executable_path().get_base_dir(),
		"timestamp": Time.get_unix_time_from_system()
	}

	return {
		"contents": [{
			"uri": "godot://project/info",
			"mimeType": "application/json",
			"text": JSON.stringify(project_info, "\t", true)
		}]
	}

## 读取项目设置资源
func _resource_project_settings(params: Dictionary) -> Dictionary:
	var settings: Dictionary = {}
	var property_list: Array = ProjectSettings.get_property_list()

	for property in property_list:
		var property_name: String = property.get("name", "")
		if property_name.begins_with("application/") or property_name.begins_with("display/") or property_name.begins_with("rendering/"):
			settings[property_name] = ProjectSettings.get_setting(property_name)

	return {
		"contents": [{
			"uri": "godot://project/settings",
			"mimeType": "application/json",
			"text": JSON.stringify({
				"settings": settings,
				"count": settings.size(),
				"timestamp": Time.get_unix_time_from_system()
			}, "\t", true)
		}]
	}

## 读取编辑器状态资源
func _resource_editor_state(params: Dictionary) -> Dictionary:
	if not _editor_interface:
		return {"contents": [{"uri": "godot://editor/state", "mimeType": "application/json", "text": "{}"}]}

	var editor_state: Dictionary = {
		"current_scene": "",
		"selected_nodes": [],
		"timestamp": Time.get_unix_time_from_system()
	}

	var scene_root: Node = _editor_interface.get_edited_scene_root()
	if scene_root:
		editor_state["current_scene"] = scene_root.scene_file_path

	var selection: EditorSelection = _editor_interface.get_selection()
	if selection:
		var selected_nodes: Array = selection.get_selected_nodes()
		for node in selected_nodes:
			editor_state["selected_nodes"].append(node.get_path())

	return {
		"contents": [{
			"uri": "godot://editor/state",
			"mimeType": "application/json",
			"text": JSON.stringify(editor_state, "\t", true)
		}]
	}

# ===========================================
# 辅助函数
# ===========================================

## 递归查找文件
static func _find_files_recursive(dir: DirAccess, extension: String, result: Array, base_path: String = "res://") -> void:
	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		var full_path: String = base_path.path_join(file_name)

		if dir.current_is_dir():
			var sub_dir: DirAccess = DirAccess.open(full_path + "/")
			if sub_dir:
				_find_files_recursive(sub_dir, extension, result, full_path + "/")
		elif file_name.ends_with(extension):
			result.append(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()

## 计算节点数量
static func _count_nodes(node: Node) -> int:
	var count: int = 1

	for child in node.get_children():
		count += _count_nodes(child)

	return count

## 获取节点树结构
static func _get_node_tree(node: Node, max_depth: int, current_depth: int = 0) -> Array:
	if current_depth >= max_depth:
		return []

	var result: Array = []

	for child in node.get_children():
		var child_info: Dictionary = {
			"name": child.name,
			"type": child.get_class(),
			"children": _get_node_tree(child, max_depth, current_depth + 1)
		}
		result.append(child_info)

	return result

## 获取Godot版本
static func _get_godot_version() -> Dictionary:
	return {
		"version": Engine.get_version_info()["string"],
		"major": Engine.get_version_info()["major"],
		"minor": Engine.get_version_info()["minor"],
		"patch": Engine.get_version_info()["patch"]
	}

# ===========================================
# 资源注册
# ===========================================

## 注册所有资源到MCPServerCore
func register_resources(server_core: RefCounted) -> void:
	if not server_core:
		if _log_callback.is_valid():
			_log_callback.call("ERROR", "server_core 为空")
		return

	server_core.register_resource(
		"godot://scene/list",
		"Godot Scene List",
		"application/json",
		Callable(self, "_resource_scene_list"),
		"List all scene files in the project"
	)

	server_core.register_resource(
		"godot://scene/current",
		"Current Godot Scene",
		"application/json",
		Callable(self, "_resource_scene_current"),
		"Get the currently edited scene info"
	)

	server_core.register_resource(
		"godot://script/list",
		"Godot Script List",
		"application/json",
		Callable(self, "_resource_script_list"),
		"List all GDScript files in the project"
	)

	server_core.register_resource(
		"godot://script/current",
		"Current Godot Script",
		"application/json",
		Callable(self, "_resource_script_current"),
		"Get the currently edited script info"
	)

	server_core.register_resource(
		"godot://project/info",
		"Godot Project Info",
		"application/json",
		Callable(self, "_resource_project_info"),
		"Get project information"
	)

	server_core.register_resource(
		"godot://project/settings",
		"Godot Project Settings",
		"application/json",
		Callable(self, "_resource_project_settings"),
		"Get project settings"
	)

	server_core.register_resource(
		"godot://editor/state",
		"Godot Editor State",
		"application/json",
		Callable(self, "_resource_editor_state"),
		"Get current editor state"
	)

	if _log_callback.is_valid():
		_log_callback.call("INFO", "已注册 7 个资源")
