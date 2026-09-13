class_name ToolPolicy
extends RefCounted

var available: bool = true
var mcp_visible: bool = true
var cli_allowed: bool = true
var risk_level: String = "read"
var requires_apply: bool = false
var requires_open_world_permission: bool = false

static func from_metadata(category: String, annotations: Dictionary) -> ToolPolicy:
	var policy := ToolPolicy.new()
	policy.mcp_visible = category == "core"
	policy.cli_allowed = true
	policy.requires_apply = bool(annotations.get("destructiveHint", false))
	policy.requires_open_world_permission = bool(annotations.get("openWorldHint", false))
	if policy.requires_apply:
		policy.risk_level = "destructive"
	elif bool(annotations.get("readOnlyHint", false)):
		policy.risk_level = "read"
	else:
		policy.risk_level = "write"
	return policy

func to_dict() -> Dictionary:
	return {
		"available": available,
		"mcp_visible": mcp_visible,
		"cli_allowed": cli_allowed,
		"risk_level": risk_level,
		"requires_apply": requires_apply,
		"requires_open_world_permission": requires_open_world_permission,
	}
