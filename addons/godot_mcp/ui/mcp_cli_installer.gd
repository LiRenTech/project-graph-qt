@tool
class_name MCPCliInstaller
extends RefCounted

var _http: HTTPRequest = null
var _scene_tree: SceneTree = null
var _release_config: Dictionary = {}

const CONFIG_PATH: String = "res://addons/godot_mcp/cli_release.json"

func _init() -> void:
	_load_config()

func set_scene_tree(tree: SceneTree) -> void:
	_scene_tree = tree

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("CLI release config not found: %s" % CONFIG_PATH)
		return
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_warning("Failed to parse CLI release config")
		return
	_release_config = json.data

func cli_version() -> String:
	return _release_config.get("version", "0.0.0")

func platform_target() -> String:
	match OS.get_name():
		"Windows":
			return "x86_64-pc-windows-msvc"
		"macOS":
			var arch: String = OS.get_processor_name().to_lower()
			if "arm" in arch:
				return "aarch64-apple-darwin"
			return "x86_64-apple-darwin"
		_:
			return "x86_64-unknown-linux-gnu"

func platform_exe_name() -> String:
	var targets: Dictionary = _release_config.get("targets", {})
	var target: String = platform_target()
	return targets.get(target, "gdmcp.exe" if OS.get_name() == "Windows" else "gdmcp")

func detect_state(project_path: String) -> Dictionary:
	var install_dir: String = project_path.path_join(".gdmcp/bin")
	var exe_path: String = install_dir.path_join(platform_exe_name())
	var installed: bool = FileAccess.file_exists(exe_path)
	return {
		"installed": installed,
		"exe_path": exe_path,
		"install_dir": install_dir,
		"version": cli_version(),
	}

func download_url(source: String) -> String:
	if source == "github":
		var tmpl: String = _release_config.get("github", {}).get("url_template", "")
		return tmpl.replace("{version}", cli_version()).replace("{target}", platform_target())
	var quark: Dictionary = _release_config.get("quark", {})
	return quark.get("direct_download", "")

func download_page_url() -> String:
	return _release_config.get("quark", {}).get("page_url", "")

func install_from(source: String, install_dir: String, on_complete: Callable) -> void:
	var url: String = download_url(source)
	if url.is_empty():
		# Quark can't direct-download; open browser
		if source == "quark":
			OS.shell_open(download_page_url())
			on_complete.call(false, "Quark cloud drive does not support direct download. Browser opened — download manually and place %s in:\n%s" % [platform_exe_name(), install_dir])
		else:
			on_complete.call(false, "Download URL not configured for source: %s" % source)
		return

	if _http == null:
		_http = HTTPRequest.new()
		_scene_tree.root.add_child(_http)
	else:
		if _http.request_completed.is_connected(_on_download_completed):
			_http.request_completed.disconnect(_on_download_completed)
	_http.request_completed.connect(_on_download_completed.bind(on_complete, install_dir), CONNECT_ONE_SHOT)
	var error: int = _http.request(url)
	if error != OK:
		on_complete.call(false, "Download request failed: error code %d" % error)

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, on_complete: Callable, install_dir: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		on_complete.call(false, "Download failed (HTTP %d). Try the alternate download source." % response_code)
		return

	# Save zip to temp file, then extract with ZIPReader
	var tmp_zip: String = install_dir.path_join("_gdmcp_download.zip")
	DirAccess.make_dir_recursive_absolute(install_dir)
	var tmp_file: FileAccess = FileAccess.open(tmp_zip, FileAccess.WRITE)
	if tmp_file == null:
		on_complete.call(false, "Cannot write temp file to %s" % tmp_zip)
		return
	tmp_file.store_buffer(body)
	tmp_file.close()

	var zip_reader: ZIPReader = ZIPReader.new()
	var err: int = zip_reader.open(tmp_zip)
	if err != OK:
		DirAccess.remove_absolute(tmp_zip)
		on_complete.call(false, "Failed to open downloaded archive")
		return

	var exe_name: String = platform_exe_name()
	var exe_data: PackedByteArray = zip_reader.read_file(exe_name)
	zip_reader.close()
	DirAccess.remove_absolute(tmp_zip)

	if exe_data.is_empty():
		on_complete.call(false, "Archive does not contain %s" % exe_name)
		return

	DirAccess.make_dir_recursive_absolute(install_dir)
	var exe_path: String = install_dir.path_join(exe_name)
	var file: FileAccess = FileAccess.open(exe_path, FileAccess.WRITE)
	if file == null:
		on_complete.call(false, "Cannot write to %s" % exe_path)
		return
	file.store_buffer(exe_data)
	file.close()

	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", exe_path])

	on_complete.call(true, "CLI installed to %s" % exe_path)