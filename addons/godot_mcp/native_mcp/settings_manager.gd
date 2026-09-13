class_name MCPSettingsManager
extends "res://addons/godot_mcp/native_mcp/config_manager.gd"

const CONFIG_FILE_NAME: String = "mcp_settings.cfg"
const SECTION_SETTINGS: String = "settings"

const DEFAULT_SETTINGS: Dictionary = {
	"transport_mode": "http",
	"http_port": 9080,
	"auth_enabled": false,
	"auth_token": "",
	"sse_enabled": true,
	"allow_remote": false,
	"cors_origin": "*",
	"auto_start": false,
	"log_level": 2,
	"security_level": 1,
	"rate_limit": 100,
	"language": "en"
}

func _init() -> void:
	config_file_name = CONFIG_FILE_NAME
	config_section = SECTION_SETTINGS
	storage_version = 1

func load_settings() -> Dictionary:
	var saved: Dictionary = load_config()
	var merged: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	for key in saved:
		if merged.has(key):
			merged[key] = saved[key]
	return merged

func save_settings(settings: Dictionary) -> bool:
	return save_config(settings)