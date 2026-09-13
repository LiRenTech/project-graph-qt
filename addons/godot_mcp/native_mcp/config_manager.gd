class_name MCPConfigManager
extends RefCounted

var config_file_name: String = "mcp_config.cfg"
var config_section: String = "config"
var storage_version: int = 1

func load_config() -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(get_storage_path())
	if err != OK:
		return {}

	if not _validate_config_integrity(config):
		return {}

	var stored_version: int = config.get_value("meta", "version", 0)
	if stored_version < storage_version:
		_migrate_config(config, stored_version)

	var states: Dictionary = {}
	if config.has_section(config_section):
		for key in config.get_section_keys(config_section):
			states[key] = config.get_value(config_section, key)
	return states

func save_config(data: Dictionary) -> bool:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", storage_version)
	for key in data:
		config.set_value(config_section, key, data[key])
	_add_checksum(config)
	var err: Error = config.save(get_storage_path())
	return err == OK

func get_storage_path() -> String:
	return "user://" + config_file_name

func _validate_config_integrity(config: ConfigFile) -> bool:
	if not config.has_section("meta"):
		return false
	if not config.has_section_key("meta", "checksum"):
		return true
	var stored_checksum: String = config.get_value("meta", "checksum", "")
	var raw: String = _serialize_config_data(config)
	var computed: String = raw.md5_text()
	return stored_checksum == computed

func _add_checksum(config: ConfigFile) -> void:
	var raw: String = _serialize_config_data(config)
	var checksum: String = raw.md5_text()
	config.set_value("meta", "checksum", checksum)

func _serialize_config_data(config: ConfigFile) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if config.has_section(config_section):
		for key in config.get_section_keys(config_section):
			var val = config.get_value(config_section, key)
			lines.append(config_section + "/" + key + "=" + str(val))
	return "\n".join(lines)

func _migrate_config(config: ConfigFile, from_version: int) -> void:
	if from_version < 1:
		config.set_value("meta", "version", 1)