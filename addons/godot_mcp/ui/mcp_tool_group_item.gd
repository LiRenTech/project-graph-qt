@tool
class_name MCPToolGroupItem
extends VBoxContainer

var _group_name: String = ""
var _is_collapsed: bool = false
var _group_check: CheckBox = null
var _translation_manager: MCPTranslationManager = null

signal group_toggled(group_name: String, enabled: bool)
signal item_toggled(tool_name: String, enabled: bool)

func setup(group_name: String, items: Array, translation_manager = null) -> void:
	_group_name = group_name
	_translation_manager = translation_manager

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)

	var collapse_button: Button = Button.new()
	collapse_button.text = "▼"
	collapse_button.flat = true
	collapse_button.tooltip_text = "Collapse/Expand"
	collapse_button.pressed.connect(_toggle_collapse)
	header.add_child(collapse_button)

	_group_check = CheckBox.new()
	_group_check.text = _group_name
	_group_check.add_theme_font_size_override("font_size", 13)
	_group_check.toggled.connect(_on_group_toggled)
	header.add_child(_group_check)

	var count_label: Label = Label.new()
	count_label.name = "CountLabel"
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(count_label)

	var sep: HSeparator = HSeparator.new()
	header.add_child(sep)

	var tool_container: VBoxContainer = VBoxContainer.new()
	tool_container.name = "ToolContainer"
	add_child(tool_container)

	for item in items:
		var tool_name: String = item.get("name", "")
		var description: String = item.get("description", "")
		var enabled: bool = item.get("enabled", true)
		var category: String = item.get("category", "core")

		var translated_desc: String = _tr(tool_name)
		if translated_desc != tool_name:
			description = translated_desc

		var tool_item: MCPToolItem = MCPToolItem.new()
		tool_item.setup(tool_name, description, enabled, category, _group_name)
		tool_item.tool_toggled.connect(_on_tool_item_toggled)
		tool_container.add_child(tool_item)

	_update_count()

func get_group_name() -> String:
	return _group_name

func get_all_tools_enabled() -> bool:
	var container: VBoxContainer = get_tool_container()
	if container == null:
		return true
	for child in container.get_children():
		var tool_item: MCPToolItem = child as MCPToolItem
		if tool_item and not tool_item.is_enabled():
			return false
	return true

func set_group_enabled(enabled: bool) -> void:
	var container: VBoxContainer = get_tool_container()
	if container == null:
		return
	for child in container.get_children():
		var tool_item: MCPToolItem = child as MCPToolItem
		if tool_item:
			tool_item.set_enabled(enabled)

func get_tool_container() -> VBoxContainer:
	for child in get_children():
		if child.name == "ToolContainer":
			return child as VBoxContainer
	return null

func _tr(key: String) -> String:
	if _translation_manager:
		return _translation_manager.get_text(key)
	return key

func _toggle_collapse() -> void:
	_is_collapsed = not _is_collapsed
	var container: VBoxContainer = get_tool_container()
	if container:
		container.visible = not _is_collapsed
	var btn: Button = get_child(0).get_child(0) as Button
	if btn:
		btn.text = "▶" if _is_collapsed else "▼"

func _on_group_toggled(button_pressed: bool) -> void:
	set_group_enabled(button_pressed)
	group_toggled.emit(_group_name, button_pressed)
	_update_count()

func _on_tool_item_toggled(tool_name: String, enabled: bool) -> void:
	_update_count()
	item_toggled.emit(tool_name, enabled)

func _update_count() -> void:
	var container: VBoxContainer = get_tool_container()
	if container == null:
		return
	var total: int = 0
	var enabled: int = 0
	for child in container.get_children():
		var tool_item: MCPToolItem = child as MCPToolItem
		if tool_item:
			total += 1
			if tool_item.is_enabled():
				enabled += 1

	var header: HBoxContainer = get_child(0) as HBoxContainer
	if header:
		var count_label: Label = header.get_node("CountLabel") as Label
		if count_label:
			count_label.text = _tr("ui.enabled_format") % [enabled, total]

	if _group_check:
		_group_check.set_block_signals(true)
		_group_check.button_pressed = (enabled == total and total > 0)
		_group_check.set_block_signals(false)
