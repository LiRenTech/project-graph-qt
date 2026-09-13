@tool
extends VBoxContainer

var _plugin: EditorPlugin = null
var _server_core: RefCounted = null

var _status_label: Label = null
var _start_button: Button = null
var _stop_button: Button = null
var _auto_start_check: CheckBox = null
var _vibe_coding_mode_check: CheckBox = null
var _log_level_option: OptionButton = null
var _security_level_option: OptionButton = null
var _tools_list_container: VBoxContainer = null
var _tools_count_label: Label = null

var _transport_mode_option: OptionButton = null
var _http_config_container: VBoxContainer = null
var _http_port_spin: SpinBox = null
var _auth_enabled_check: CheckBox = null
var _auth_token_edit: LineEdit = null
var _sse_enabled_check: CheckBox = null
var _allow_remote_check: CheckBox = null
var _cors_origin_edit: LineEdit = null
var _rate_limit_spin: SpinBox = null
var _connection_info_label: Label = null

var _transport_title_label: Label = null
var _transport_mode_label: Label = null
var _http_port_label: Label = null
var _auth_token_label: Label = null
var _cors_origin_label: Label = null
var _log_level_label: Label = null
var _security_label: Label = null
var _rate_limit_label: Label = null
var _language_label: Label = null
var _refresh_tools_button: Button = null
var _open_log_button: Button = null

var _tab_container: TabContainer = null
var _debounce_timer: Timer = null
var _group_widgets: Dictionary = {}
var _language_option: OptionButton = null

var _log_file_path: String = "user://mcp_server.log"
var _log_file_flush_count: int = 10
var _log_pending_write: Array[String] = []
var _log_file_initialized: bool = false
var _max_log_file_size: int = 5242880

var _translation_manager: MCPTranslationManager = null
var _settings_manager: MCPSettingsManager = null
var _cli_installer: MCPCliInstaller = null
var _cli_title_label: Label = null
var _cli_desc_label: Label = null
var _cli_status_title_label: Label = null
var _cli_status_label: Label = null
var _cli_install_button: Button = null
var _cli_source_option: OptionButton = null
var _cli_skill_button: Button = null

func _ready() -> void:
	_translation_manager = MCPTranslationManager.new()
	_translation_manager.load_all()
	_settings_manager = MCPSettingsManager.new()
	_create_ui()
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(_debounce_timer)

func _exit_tree() -> void:
	_flush_log_to_file()
	if _debounce_timer:
		_debounce_timer.stop()

func set_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin
	if _translation_manager == null:
		_translation_manager = MCPTranslationManager.new()
		_translation_manager.load_all()
	if _settings_manager == null:
		_settings_manager = MCPSettingsManager.new()
	if _plugin and _plugin.has_method("get_native_server"):
		_server_core = _plugin.get_native_server()
	_load_settings()
	_refresh_translations()

func set_server_core(server_core: RefCounted) -> void:
	_server_core = server_core
	_update_ui_state()
	_refresh_tools_list()

func _tr(key: String) -> String:
	if _translation_manager:
		return _translation_manager.get_text(key)
	return key

func _trf(key: String, args: Array) -> String:
	var text: String = _tr(key)
	var placeholder_count: int = 0
	for i in text.length():
		if text[i] == "%":
			i += 1
			if i < text.length() and text[i] in "dsf":
				placeholder_count += 1
	if placeholder_count > 0 and placeholder_count == args.size():
		return text % args
	return text

func _create_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	add_child(_create_status_bar())

	_tab_container = TabContainer.new()
	_tab_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_tab_container)

	var settings_tab: VBoxContainer = _create_settings_tab()
	var tools_tab: VBoxContainer = _create_tools_tab()

	_tab_container.add_child(settings_tab)
	_tab_container.add_child(tools_tab)

	_tab_container.set_tab_title(0, _tr("ui.settings"))
	_tab_container.set_tab_title(1, _tr("ui.tool_manager"))
	var cli_tab: VBoxContainer = _create_cli_tab()
	_tab_container.add_child(cli_tab)
	_tab_container.set_tab_title(2, _tr("ui.cli_tools"))
	_refresh_cli_translations()

	_update_ui_state()
	_refresh_tools_list()
	_init_cli_installer()

func _create_status_bar() -> HBoxContainer:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	_status_label = Label.new()
	_status_label.text = _tr("ui.status_unknown")
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.add_child(_status_label)

	_connection_info_label = Label.new()
	_connection_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_connection_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_connection_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_connection_info_label)

	_start_button = Button.new()
	_start_button.text = _tr("ui.start_server")
	_start_button.pressed.connect(_on_start_pressed)
	bar.add_child(_start_button)

	_stop_button = Button.new()
	_stop_button.text = _tr("ui.stop_server")
	_stop_button.pressed.connect(_on_stop_pressed)
	bar.add_child(_stop_button)

	return bar

func _create_settings_tab() -> VBoxContainer:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 4)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	_transport_title_label = Label.new()
	_transport_title_label.text = _tr("ui.transport_settings")
	_transport_title_label.add_theme_font_size_override("font_size", 13)
	content.add_child(_transport_title_label)

	var transport_hbox: HBoxContainer = HBoxContainer.new()
	content.add_child(transport_hbox)

	_transport_mode_label = Label.new()
	_transport_mode_label.text = _tr("ui.transport_mode")
	transport_hbox.add_child(_transport_mode_label)

	_transport_mode_option = OptionButton.new()
	_transport_mode_option.add_item("http", 1)
	_transport_mode_option.item_selected.connect(_on_transport_mode_selected)
	transport_hbox.add_child(_transport_mode_option)

	_http_config_container = VBoxContainer.new()
	_http_config_container.add_theme_constant_override("separation", 4)
	content.add_child(_http_config_container)

	var port_hbox: HBoxContainer = HBoxContainer.new()
	_http_config_container.add_child(port_hbox)

	_http_port_label = Label.new()
	_http_port_label.text = _tr("ui.http_port")
	port_hbox.add_child(_http_port_label)

	_http_port_spin = SpinBox.new()
	_http_port_spin.min_value = 1024
	_http_port_spin.max_value = 65535
	_http_port_spin.value = 9080
	_http_port_spin.step = 1
	_http_port_spin.value_changed.connect(_on_http_port_changed)
	port_hbox.add_child(_http_port_spin)

	var auth_hbox: HBoxContainer = HBoxContainer.new()
	_http_config_container.add_child(auth_hbox)

	_auth_enabled_check = CheckBox.new()
	_auth_enabled_check.text = _tr("ui.enable_auth")
	_auth_enabled_check.toggled.connect(_on_auth_enabled_toggled)
	auth_hbox.add_child(_auth_enabled_check)

	_auth_token_label = Label.new()
	_auth_token_label.text = _tr("ui.auth_token")
	auth_hbox.add_child(_auth_token_label)

	_auth_token_edit = LineEdit.new()
	_auth_token_edit.secret = true
	_auth_token_edit.placeholder_text = _tr("ui.token_placeholder")
	_auth_token_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auth_token_edit.text_changed.connect(_on_auth_token_changed)
	auth_hbox.add_child(_auth_token_edit)

	_sse_enabled_check = CheckBox.new()
	_sse_enabled_check.text = _tr("ui.enable_sse")
	_sse_enabled_check.toggled.connect(_on_sse_enabled_toggled)
	_http_config_container.add_child(_sse_enabled_check)

	_allow_remote_check = CheckBox.new()
	_allow_remote_check.text = _tr("ui.allow_remote")
	_allow_remote_check.toggled.connect(_on_allow_remote_toggled)
	_http_config_container.add_child(_allow_remote_check)

	var cors_hbox: HBoxContainer = HBoxContainer.new()
	_http_config_container.add_child(cors_hbox)

	_cors_origin_label = Label.new()
	_cors_origin_label.text = _tr("ui.cors_origin")
	cors_hbox.add_child(_cors_origin_label)

	_cors_origin_edit = LineEdit.new()
	_cors_origin_edit.text = "*"
	_cors_origin_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cors_origin_edit.text_changed.connect(_on_cors_origin_changed)
	cors_hbox.add_child(_cors_origin_edit)

	_http_config_container.visible = false

	content.add_child(HSeparator.new())

	_auto_start_check = CheckBox.new()
	_auto_start_check.text = _tr("ui.auto_start")
	_auto_start_check.toggled.connect(_on_auto_start_toggled)
	content.add_child(_auto_start_check)

	_vibe_coding_mode_check = CheckBox.new()
	_vibe_coding_mode_check.text = _tr("ui.vibe_coding_mode")
	_vibe_coding_mode_check.toggled.connect(_on_vibe_coding_mode_toggled)
	content.add_child(_vibe_coding_mode_check)

	var log_hbox: HBoxContainer = HBoxContainer.new()
	content.add_child(log_hbox)

	_log_level_label = Label.new()
	_log_level_label.text = _tr("ui.log_level")
	log_hbox.add_child(_log_level_label)

	_log_level_option = OptionButton.new()
	_log_level_option.add_item("ERROR", 0)
	_log_level_option.add_item("WARN", 1)
	_log_level_option.add_item("INFO", 2)
	_log_level_option.add_item("DEBUG", 3)
	_log_level_option.item_selected.connect(_on_log_level_selected)
	log_hbox.add_child(_log_level_option)

	var security_hbox: HBoxContainer = HBoxContainer.new()
	content.add_child(security_hbox)

	_security_label = Label.new()
	_security_label.text = _tr("ui.security")
	security_hbox.add_child(_security_label)

	_security_level_option = OptionButton.new()
	_security_level_option.add_item("PERMISSIVE", 0)
	_security_level_option.add_item("STRICT", 1)
	_security_level_option.item_selected.connect(_on_security_level_selected)
	security_hbox.add_child(_security_level_option)

	var rate_hbox: HBoxContainer = HBoxContainer.new()
	content.add_child(rate_hbox)

	_rate_limit_label = Label.new()
	_rate_limit_label.text = _tr("ui.rate_limit")
	rate_hbox.add_child(_rate_limit_label)

	_rate_limit_spin = SpinBox.new()
	_rate_limit_spin.min_value = 10
	_rate_limit_spin.max_value = 1000
	_rate_limit_spin.step = 10
	_rate_limit_spin.value = 100
	_rate_limit_spin.value_changed.connect(_on_rate_limit_changed)
	rate_hbox.add_child(_rate_limit_spin)

	content.add_child(HSeparator.new())

	var lang_hbox: HBoxContainer = HBoxContainer.new()
	content.add_child(lang_hbox)

	_language_label = Label.new()
	_language_label.text = _tr("ui.language")
	lang_hbox.add_child(_language_label)

	_language_option = OptionButton.new()
	_language_option.add_item(_tr("ui.english"), 0)
	_language_option.add_item(_tr("ui.chinese"), 1)
	_language_option.item_selected.connect(_on_language_selected)
	lang_hbox.add_child(_language_option)

	content.add_child(HSeparator.new())

	_open_log_button = Button.new()
	_open_log_button.text = _tr("ui.open_log")
	_open_log_button.pressed.connect(_open_log_file)
	_open_log_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	content.add_child(_open_log_button)

	return tab

func _create_tools_tab() -> VBoxContainer:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 4)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)

	var toolbar: HBoxContainer = HBoxContainer.new()
	content.add_child(toolbar)

	_refresh_tools_button = Button.new()
	_refresh_tools_button.text = _tr("ui.refresh_tools")
	_refresh_tools_button.pressed.connect(_refresh_tools_list)
	toolbar.add_child(_refresh_tools_button)

	_tools_count_label = Label.new()
	_tools_count_label.text = _tr("ui.tools_init")
	_tools_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_tools_count_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(scroll)

	_tools_list_container = VBoxContainer.new()
	_tools_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tools_list_container)

	return tab

func _update_ui_state() -> void:
	if not _status_label:
		return

	var is_running: bool = false
	if _server_core and _server_core.has_method("is_running"):
		is_running = _server_core.is_running()

	if is_running:
		_status_label.text = _tr("ui.status_running")
		_status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		_status_label.text = _tr("ui.status_stopped")
		_status_label.add_theme_color_override("font_color", Color.RED)

	if _start_button:
		_start_button.disabled = is_running
	if _stop_button:
		_stop_button.disabled = not is_running

	if _plugin:
		if _auto_start_check:
			_auto_start_check.button_pressed = _plugin.auto_start

		if _vibe_coding_mode_check:
			_vibe_coding_mode_check.button_pressed = _plugin.vibe_coding_mode if _plugin.get("vibe_coding_mode") != null else true

		if _log_level_option:
			_log_level_option.select(_plugin.log_level)

		if _security_level_option:
			_security_level_option.select(_plugin.security_level)

		if _transport_mode_option:
			var mode: String = _plugin.transport_mode if _plugin.get("transport_mode") != null else "stdio"
			_transport_mode_option.selected = 0 if mode == "stdio" else 1
			_http_config_container.visible = (mode == "http")

		if _http_port_spin:
			_http_port_spin.value = _plugin.http_port if _plugin.get("http_port") != null else 9080

		if _auth_enabled_check:
			_auth_enabled_check.button_pressed = _plugin.auth_enabled if _plugin.get("auth_enabled") != null else false

		if _auth_token_edit:
			_auth_token_edit.text = _plugin.auth_token if _plugin.get("auth_token") != null else ""

		if _sse_enabled_check:
			_sse_enabled_check.button_pressed = _plugin.sse_enabled if _plugin.get("sse_enabled") != null else true

		if _allow_remote_check:
			_allow_remote_check.button_pressed = _plugin.allow_remote if _plugin.get("allow_remote") != null else false

		if _cors_origin_edit:
			_cors_origin_edit.text = _plugin.cors_origin if _plugin.get("cors_origin") != null else "*"

		if _rate_limit_spin:
			_rate_limit_spin.value = _plugin.rate_limit if _plugin.get("rate_limit") != null else 100

	if _transport_mode_option:
		_transport_mode_option.disabled = is_running

	if _http_config_container:
		_set_controls_disabled(_http_config_container, is_running)

	if _auth_token_edit:
		var auth_on: bool = _auth_enabled_check.button_pressed if _auth_enabled_check else false
		_auth_token_edit.editable = auth_on and not is_running

	if _connection_info_label:
		var mode: String = "stdio"
		if _plugin and _plugin.get("transport_mode") != null:
			mode = _plugin.transport_mode
		if mode == "http" and is_running:
			var port: int = 9080
			if _plugin and _plugin.get("http_port") != null:
				port = _plugin.http_port
			_connection_info_label.text = _trf("ui.connection_url", [port])
		elif mode == "stdio" and is_running:
			_connection_info_label.text = _tr("ui.connection_stdio")
		else:
			_connection_info_label.text = ""

func _set_controls_disabled(container: Container, disabled: bool) -> void:
	for child in container.get_children():
		if child is SpinBox or child is LineEdit:
			child.editable = not disabled
		elif child is CheckBox or child is OptionButton or child is Button:
			child.disabled = disabled
		elif child is Container:
			_set_controls_disabled(child, disabled)

func _on_start_pressed() -> void:
	if not _plugin:
		return
	_plugin.start_server()
	await get_tree().process_frame
	_update_ui_state()

func _on_stop_pressed() -> void:
	if not _plugin:
		return
	_plugin.stop_server()
	await get_tree().process_frame
	_update_ui_state()

func _on_auto_start_toggled(button_pressed: bool) -> void:
	if _plugin:
		_plugin.auto_start = button_pressed
	_debounce_save()

func _on_vibe_coding_mode_toggled(button_pressed: bool) -> void:
	if _plugin:
		_plugin.vibe_coding_mode = button_pressed
	_debounce_save()

func _on_log_level_selected(index: int) -> void:
	if _plugin:
		_plugin.log_level = index
	_debounce_save()

func _on_security_level_selected(index: int) -> void:
	if _plugin:
		_plugin.security_level = index
	_debounce_save()

func _on_transport_mode_selected(index: int) -> void:
	var mode: String = _transport_mode_option.get_item_text(index)
	if _plugin:
		_plugin.transport_mode = mode
	_http_config_container.visible = (mode == "http")
	_update_ui_state()
	_debounce_save()

func _on_http_port_changed(value: float) -> void:
	if _plugin:
		_plugin.http_port = int(value)
	_debounce_save()

func _on_auth_enabled_toggled(enabled: bool) -> void:
	if _plugin:
		_plugin.auth_enabled = enabled
	if _auth_token_edit:
		_auth_token_edit.editable = enabled
	_debounce_save()

func _on_auth_token_changed(text: String) -> void:
	if _plugin:
		_plugin.auth_token = text
	_debounce_save()

func _on_sse_enabled_toggled(enabled: bool) -> void:
	if _plugin:
		_plugin.sse_enabled = enabled
	_debounce_save()

func _on_allow_remote_toggled(enabled: bool) -> void:
	if _plugin:
		_plugin.allow_remote = enabled
	_debounce_save()

func _on_cors_origin_changed(text: String) -> void:
	if _plugin:
		_plugin.cors_origin = text
	_debounce_save()

func _on_rate_limit_changed(value: float) -> void:
	if _plugin:
		_plugin.rate_limit = int(value)
	_debounce_save()

func _open_log_file() -> void:
	# Flush pending writes before opening so the file has the latest data
	_flush_log_to_file()
	var path: String = ProjectSettings.globalize_path(_log_file_path)
	# Build a proper file:// URI that works on Windows, macOS, and Linux.
	# globalize_path returns e.g. "C:/Users/..." (Windows) or "/Users/..." (macOS/Linux).
	# file:// expects exactly one slash before the absolute path: file:///C:/... or file:///home/...
	if not path.begins_with("/"):
		path = "/" + path
	OS.shell_open("file://" + path)

func clear_log() -> void:
	_log_pending_write.clear()
	var file: FileAccess = FileAccess.open(_log_file_path, FileAccess.WRITE)
	if file:
		file.store_string("")
		file.close()

func _refresh_tools_list() -> void:
	if not _tools_list_container:
		return

	for child in _tools_list_container.get_children():
		child.queue_free()
	_group_widgets.clear()

	var tools: Array = []
	if _server_core and _server_core.has_method("get_registered_tools"):
		tools = _server_core.get_registered_tools()

	var classifier = null
	if _server_core and _server_core.has_method("get_classifier"):
		classifier = _server_core.get_classifier()

	var tools_by_group: Dictionary = {}
	for tool_info in tools:
		var group: String = tool_info.get("group", "")
		if not tools_by_group.has(group):
			tools_by_group[group] = []
		tools_by_group[group].append(tool_info)

	var all_groups: Array = []
	if classifier and classifier.has_method("get_all_groups"):
		all_groups = classifier.get_all_groups()

	var core_group_names: Array = []
	var supp_group_names: Array = []
	for group_name in all_groups:
		if tools_by_group.has(group_name):
			var sample: Dictionary = tools_by_group[group_name][0]
			var cat: String = sample.get("category", "core")
			if cat == "supplementary":
				supp_group_names.append(group_name)
			else:
				core_group_names.append(group_name)

	if core_group_names.size() > 0:
		var core_section: Label = Label.new()
		core_section.text = _tr("ui.core_tools")
		core_section.add_theme_font_size_override("font_size", 14)
		core_section.add_theme_color_override("font_color", Color(0.3, 0.7, 0.7))
		core_section.add_theme_constant_override("margin_top", 4)
		_tools_list_container.add_child(core_section)

		for group_name in core_group_names:
			_create_group_widget(group_name, tools_by_group[group_name])

	if supp_group_names.size() > 0:
		var supp_section: Label = Label.new()
		supp_section.text = _tr("ui.supplementary_tools")
		supp_section.add_theme_font_size_override("font_size", 14)
		supp_section.add_theme_color_override("font_color", Color(0.7, 0.7, 0.3))
		supp_section.add_theme_constant_override("margin_top", 8)
		_tools_list_container.add_child(supp_section)

		for group_name in supp_group_names:
			_create_group_widget(group_name, tools_by_group[group_name])

	_update_tools_count()

func _create_group_widget(group_name: String, group_tools: Array) -> void:
	var widget: MCPToolGroupItem = MCPToolGroupItem.new()
	widget.setup(group_name, group_tools, _translation_manager)
	widget.group_toggled.connect(_on_group_toggled)
	widget.item_toggled.connect(_on_tool_toggled)
	_tools_list_container.add_child(widget)
	_group_widgets[group_name] = widget

func _on_tool_toggled(tool_name: String, enabled: bool) -> void:
	if _server_core and _server_core.has_method("set_tool_enabled"):
		_server_core.set_tool_enabled(tool_name, enabled)
	_update_tools_count()
	_debounce_save()

func _on_group_toggled(group_name: String, enabled: bool) -> void:
	if _server_core and _server_core.has_method("set_group_enabled"):
		_server_core.set_group_enabled(group_name, enabled)
	_update_tools_count()
	_debounce_save()

func _update_tools_count() -> void:
	if not _tools_count_label:
		return
	var tools: Array = []
	if _server_core and _server_core.has_method("get_registered_tools"):
		tools = _server_core.get_registered_tools()
	var core_total: int = 0
	var core_enabled: int = 0
	var supp_total: int = 0
	var supp_enabled: int = 0
	for tool_info in tools:
		var cat: String = tool_info.get("category", "core")
		var en: bool = tool_info.get("enabled", true)
		if cat == "supplementary":
			supp_total += 1
			if en:
				supp_enabled += 1
		else:
			core_total += 1
			if en:
				core_enabled += 1
	_tools_count_label.text = _trf("ui.tools_count", [
		core_enabled, core_total, supp_enabled, supp_total,
		core_enabled + supp_enabled, core_total + supp_total
	])

func _refresh_translations() -> void:
	if _tab_container:
		_tab_container.set_tab_title(0, _tr("ui.settings"))
		_tab_container.set_tab_title(1, _tr("ui.tool_manager"))
		_tab_container.set_tab_title(2, _tr("ui.cli_tools"))
	_refresh_cli_translations()
	if _start_button:
		_start_button.text = _tr("ui.start_server")
	if _stop_button:
		_stop_button.text = _tr("ui.stop_server")
	if _auth_enabled_check:
		_auth_enabled_check.text = _tr("ui.enable_auth")
	if _sse_enabled_check:
		_sse_enabled_check.text = _tr("ui.enable_sse")
	if _allow_remote_check:
		_allow_remote_check.text = _tr("ui.allow_remote")
	if _auto_start_check:
		_auto_start_check.text = _tr("ui.auto_start")
	if _vibe_coding_mode_check:
		_vibe_coding_mode_check.text = _tr("ui.vibe_coding_mode")
	if _auth_token_edit:
		_auth_token_edit.placeholder_text = _tr("ui.token_placeholder")
	if _transport_title_label:
		_transport_title_label.text = _tr("ui.transport_settings")
	if _transport_mode_label:
		_transport_mode_label.text = _tr("ui.transport_mode")
	if _http_port_label:
		_http_port_label.text = _tr("ui.http_port")
	if _auth_token_label:
		_auth_token_label.text = _tr("ui.auth_token")
	if _cors_origin_label:
		_cors_origin_label.text = _tr("ui.cors_origin")
	if _log_level_label:
		_log_level_label.text = _tr("ui.log_level")
	if _security_label:
		_security_label.text = _tr("ui.security")
	if _rate_limit_label:
		_rate_limit_label.text = _tr("ui.rate_limit")
	if _language_label:
		_language_label.text = _tr("ui.language")
	if _refresh_tools_button:
		_refresh_tools_button.text = _tr("ui.refresh_tools")
	if _open_log_button:
		_open_log_button.text = _tr("ui.open_log")
	if _language_option:
		var current_locale: String = _translation_manager.get_locale() if _translation_manager else "en"
		var locales: Array = _translation_manager.get_available_locales() if _translation_manager else ["en", "zh"]
		_language_option.set_block_signals(true)
		_language_option.clear()
		_language_option.add_item(_tr("ui.english"), 0)
		_language_option.add_item(_tr("ui.chinese"), 1)
		var idx: int = locales.find(current_locale)
		if idx >= 0:
			_language_option.select(idx)
		_language_option.set_block_signals(false)
	if _tools_count_label:
		_tools_count_label.text = _tr("ui.tools_init")
	_update_ui_state()
	_update_connection_info()
	_refresh_tools_list()

func _update_connection_info() -> void:
	if not _connection_info_label:
		return
	var is_running: bool = false
	if _server_core and _server_core.has_method("is_running"):
		is_running = _server_core.is_running()
	var mode: String = "stdio"
	if _plugin and _plugin.get("transport_mode") != null:
		mode = _plugin.transport_mode
	if mode == "http" and is_running:
		var port: int = 9080
		if _plugin and _plugin.get("http_port") != null:
			port = _plugin.http_port
		_connection_info_label.text = _tr("ui.connection_url") % [port]
	elif mode == "stdio" and is_running:
		_connection_info_label.text = _tr("ui.connection_stdio")
	else:
		_connection_info_label.text = ""

func _load_settings() -> void:
	if not _settings_manager:
		return
	var s: Dictionary = _settings_manager.load_settings()
	_transport_mode_option.select(0 if s.transport_mode == "http" else 1)
	_http_port_spin.value = s.http_port
	_auth_enabled_check.button_pressed = s.auth_enabled
	_auth_token_edit.text = s.auth_token
	_sse_enabled_check.button_pressed = s.sse_enabled
	_allow_remote_check.button_pressed = s.allow_remote
	_cors_origin_edit.text = s.cors_origin
	_auto_start_check.button_pressed = s.auto_start
	_log_level_option.select(s.log_level)
	_security_level_option.select(s.security_level)
	_rate_limit_spin.value = s.rate_limit
	if _translation_manager and s.language != _translation_manager.get_locale():
		_translation_manager.set_locale(s.language)
		_refresh_translations()
	if _language_option:
		var locales: Array = _translation_manager.get_available_locales() if _translation_manager else ["en", "zh"]
		var idx: int = locales.find(s.language)
		if idx >= 0:
			_language_option.set_block_signals(true)
			_language_option.select(idx)
			_language_option.set_block_signals(false)

func _save_settings() -> void:
	if not _settings_manager:
		return
	var settings: Dictionary = {
		"transport_mode": _transport_mode_option.get_item_text(_transport_mode_option.selected) if _transport_mode_option else "http",
		"http_port": int(_http_port_spin.value) if _http_port_spin else 9080,
		"auth_enabled": _auth_enabled_check.button_pressed if _auth_enabled_check else false,
		"auth_token": _auth_token_edit.text if _auth_token_edit else "",
		"sse_enabled": _sse_enabled_check.button_pressed if _sse_enabled_check else true,
		"allow_remote": _allow_remote_check.button_pressed if _allow_remote_check else false,
		"cors_origin": _cors_origin_edit.text if _cors_origin_edit else "*",
		"auto_start": _auto_start_check.button_pressed if _auto_start_check else false,
		"log_level": _log_level_option.selected if _log_level_option else 2,
		"security_level": _security_level_option.selected if _security_level_option else 1,
		"rate_limit": int(_rate_limit_spin.value) if _rate_limit_spin else 100,
		"language": _translation_manager.get_locale() if _translation_manager else "en"
	}
	_settings_manager.save_settings(settings)

func _on_language_selected(index: int) -> void:
	var locales: Array = _translation_manager.get_available_locales() if _translation_manager else ["en", "zh"]
	if index >= 0 and index < locales.size():
		_translation_manager.set_locale(locales[index])
		_refresh_translations()
	_debounce_save()

func _debounce_save() -> void:
	if _debounce_timer:
		_debounce_timer.start(0.5)

func _on_debounce_timeout() -> void:
	if _server_core and _server_core.has_method("save_tool_states"):
		_server_core.save_tool_states()
	if _server_core and _server_core.has_method("notify_tool_list_changed"):
		_server_core.notify_tool_list_changed()
	_save_settings()

func update_log(message: String) -> void:
	if Thread.is_main_thread():
		_append_log(message)
	else:
		call_deferred("_append_log", message)

func _append_log(message: String) -> void:
	_log_pending_write.append(message)
	if _log_pending_write.size() >= _log_file_flush_count:
		_flush_log_to_file()

func _flush_log_to_file() -> void:
	if _log_pending_write.is_empty():
		return
	if not _log_file_initialized:
		if FileAccess.file_exists(_log_file_path):
			var existing: FileAccess = FileAccess.open(_log_file_path, FileAccess.READ)
			if existing:
				var size: int = existing.get_length()
				existing.close()
				if size > _max_log_file_size:
					# File too large: keep only the tail (~half max size),
					# discarding older entries from the front.
					var f: FileAccess = FileAccess.open(_log_file_path, FileAccess.READ)
					if f:
						var tail_size: int = _max_log_file_size / 2
						f.seek_end(-tail_size)
						# Skip to the start of a line to avoid truncation mid-line
						f.get_line()  # discard partial first line
						var tail: String = f.get_as_text()
						f.close()
						f = FileAccess.open(_log_file_path, FileAccess.WRITE)
						if f:
							f.store_string("[MCP] Log trimmed (exceeded max size)\n")
							f.store_string(tail)
							f.close()
		var file: FileAccess = FileAccess.open(_log_file_path, FileAccess.WRITE)
		if file:
			file.close()
		_log_file_initialized = true
	var file: FileAccess = FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		for line in _log_pending_write:
			file.store_line(line)
		file.close()
	_log_pending_write.clear()


func refresh() -> void:
	if Thread.is_main_thread():
		_update_ui_state()
		_refresh_tools_list()
	else:
		call_deferred("_update_ui_state")
		call_deferred("_refresh_tools_list")

func _create_cli_tab() -> VBoxContainer:
	var tab: VBoxContainer = VBoxContainer.new()
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 4)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	_cli_title_label = Label.new()
	_cli_title_label.text = _tr("ui.cli_title")
	_cli_title_label.add_theme_font_size_override("font_size", 13)
	content.add_child(_cli_title_label)

	_cli_desc_label = Label.new()
	_cli_desc_label.text = _tr("ui.cli_description")
	_cli_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_cli_desc_label)

	var sep: HSeparator = HSeparator.new()
	content.add_child(sep)

	var status_hbox: HBoxContainer = HBoxContainer.new()
	content.add_child(status_hbox)
	_cli_status_title_label = Label.new()
	_cli_status_title_label.text = _tr("ui.cli_status")
	status_hbox.add_child(_cli_status_title_label)
	_cli_status_label = Label.new()
	_cli_status_label.text = ""
	status_hbox.add_child(_cli_status_label)

	var install_hbox: HBoxContainer = HBoxContainer.new()
	content.add_child(install_hbox)

	_cli_source_option = OptionButton.new()
	_cli_source_option.add_item(_tr("ui.cli_source_github"))
	_cli_source_option.add_item(_tr("ui.cli_source_quark"))
	install_hbox.add_child(_cli_source_option)

	_cli_install_button = Button.new()
	_cli_install_button.text = _tr("ui.cli_install")
	_cli_install_button.pressed.connect(_on_cli_install_pressed)
	install_hbox.add_child(_cli_install_button)

	var skill_hbox: HBoxContainer = HBoxContainer.new()
	content.add_child(skill_hbox)
	_cli_skill_button = Button.new()
	_cli_skill_button.text = _tr("ui.cli_skill_download")
	_cli_skill_button.pressed.connect(_on_cli_skill_download_pressed)
	skill_hbox.add_child(_cli_skill_button)

	return tab

func _init_cli_installer() -> void:
	if _cli_installer == null:
		_cli_installer = MCPCliInstaller.new()
		_cli_installer.set_scene_tree(get_tree())
	_refresh_cli_status()

func _ensure_cli_installer() -> void:
	if _cli_installer == null:
		_cli_installer = MCPCliInstaller.new()
		_cli_installer.set_scene_tree(get_tree())

func _refresh_cli_translations() -> void:
	if _cli_title_label:
		_cli_title_label.text = _tr("ui.cli_title")
	if _cli_desc_label:
		_cli_desc_label.text = _tr("ui.cli_description")
	if _cli_status_title_label:
		_cli_status_title_label.text = _tr("ui.cli_status")
	if _cli_source_option:
		_cli_source_option.set_item_text(0, _tr("ui.cli_source_github"))
		_cli_source_option.set_item_text(1, _tr("ui.cli_source_quark"))
	if _cli_skill_button:
		_cli_skill_button.text = _tr("ui.cli_skill_download")
	_refresh_cli_status()

func _refresh_cli_status() -> void:
	_ensure_cli_installer()
	if _cli_installer == null:
		return
	var project_path: String = ProjectSettings.globalize_path("res://")
	var state: Dictionary = _cli_installer.detect_state(project_path)
	if state.installed:
		_cli_status_label.text = _trf("ui.cli_installed", [state.version])
		_cli_status_label.add_theme_color_override("font_color", Color.GREEN)
		_cli_install_button.text = _tr("ui.cli_reinstall")
	else:
		_cli_status_label.text = _tr("ui.cli_not_installed")
		_cli_status_label.add_theme_color_override("font_color", Color.ORANGE)
		_cli_install_button.text = _tr("ui.cli_install")

func _on_cli_install_pressed() -> void:
	_ensure_cli_installer()
	if _cli_installer == null:
		return
	var source: String = "github" if _cli_source_option.selected == 0 else "quark"
	var project_path: String = ProjectSettings.globalize_path("res://")
	var install_dir: String = project_path.path_join(".gdmcp/bin")
	_cli_install_button.disabled = true
	_cli_install_button.text = _tr("ui.cli_downloading")
	_cli_installer.install_from(source, install_dir, _on_cli_install_completed)

func _on_cli_install_completed(success: bool, message: String) -> void:
	_cli_install_button.disabled = false
	if success:
		_cli_status_label.text = _trf("ui.cli_installed", [_cli_installer.cli_version()])
		_cli_status_label.add_theme_color_override("font_color", Color.GREEN)
		_cli_install_button.text = _tr("ui.cli_reinstall")
		_show_cli_message(_tr("ui.cli_install_success") + "\n" + message)
	else:
		_show_cli_message(_tr("ui.cli_install_failed") + "\n" + message)
	_refresh_cli_status()


func _on_cli_skill_download_pressed() -> void:
	OS.shell_open("https://github.com/yurineko73/Godot-MCP-Native/tree/main/skills/gdmcp")

func _show_cli_message(text: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "gdmcp CLI"
	dialog.dialog_text = text
	dialog.size = Vector2(500, 300)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)