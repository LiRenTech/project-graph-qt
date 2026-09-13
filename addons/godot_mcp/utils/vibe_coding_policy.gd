@tool
class_name MCPVibeCodingPolicy
extends RefCounted

const BLOCK_REASON: String = "vibe_coding_mode"

static func evaluate_editor_focus(vibe_coding_mode: bool, params: Dictionary) -> Dictionary:
	if not vibe_coding_mode:
		return {"blocked": false}
	if bool(params.get("allow_ui_focus", false)):
		return {"blocked": false}
	return {
		"blocked": true,
		"reason": BLOCK_REASON,
		"error": "Vibe Coding mode is enabled. This tool would change editor focus or selection. Pass allow_ui_focus=true or disable Vibe Coding mode to allow it."
	}

static func evaluate_runtime_window(vibe_coding_mode: bool, params: Dictionary) -> Dictionary:
	if not vibe_coding_mode:
		return {"blocked": false}
	if bool(params.get("allow_window", false)):
		return {"blocked": false}
	return {
		"blocked": true,
		"reason": BLOCK_REASON,
		"error": "Vibe Coding mode is enabled. This tool would open or control a runtime window. Pass allow_window=true or disable Vibe Coding mode to allow it."
	}

static func should_grab_focus(vibe_coding_mode: bool, params: Dictionary, default_grab_focus: bool = true) -> bool:
	if vibe_coding_mode and not bool(params.get("allow_ui_focus", false)):
		return false
	return bool(params.get("grab_focus", default_grab_focus))
