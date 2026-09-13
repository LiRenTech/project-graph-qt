class_name ToolDefinition
extends RefCounted

var name: String = ""
var description: String = ""
var input_schema: Dictionary = {}
var output_schema: Dictionary = {}
var annotations: Dictionary = {}
var callable: Callable = Callable()
var category: String = "core"
var group: String = ""
var policy: ToolPolicy = ToolPolicy.new()

static func from_legacy(tool: Variant) -> ToolDefinition:
	var definition := ToolDefinition.new()
	definition.name = str(tool.name)
	definition.description = str(tool.description)
	definition.input_schema = tool.input_schema.duplicate(true)
	definition.output_schema = tool.output_schema.duplicate(true)
	definition.annotations = tool.annotations.duplicate(true)
	definition.callable = tool.callable
	definition.category = str(tool.category)
	definition.group = str(tool.group)
	definition.policy = ToolPolicy.from_metadata(definition.category, definition.annotations)
	definition.policy.mcp_visible = bool(tool.enabled)
	return definition

func is_valid() -> bool:
	return not name.is_empty() and not description.is_empty() and callable.is_valid()

func to_mcp_dict() -> Dictionary:
	var result: Dictionary = {
		"name": name,
		"description": description,
		"inputSchema": input_schema,
		"x_category": category,
		"x_group": group,
	}
	if not output_schema.is_empty():
		result["outputSchema"] = output_schema
	if not annotations.is_empty():
		result["annotations"] = annotations
	return result

func to_cli_summary() -> Dictionary:
	return {
		"name": name,
		"summary": description,
		"category": category,
		"group": group,
		"risk": policy.risk_level,
		"cli_allowed": policy.cli_allowed and policy.available,
		"schema_hash": get_schema_hash(),
	}

func to_cli_schema() -> Dictionary:
	return {
		"name": name,
		"description": description,
		"input_schema": input_schema,
		"output_schema": output_schema,
		"annotations": annotations,
		"category": category,
		"group": group,
		"policy": policy.to_dict(),
		"schema_hash": get_schema_hash(),
	}

func get_schema_hash() -> String:
	return _stable_stringify({
		"name": name,
		"description": description,
		"input_schema": input_schema,
		"output_schema": output_schema,
		"annotations": annotations,
		"category": category,
		"group": group,
	}).sha256_text()

static func _stable_stringify(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var keys: Array = dictionary.keys()
			keys.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
			var parts: PackedStringArray = PackedStringArray()
			for key in keys:
				parts.append(JSON.stringify(str(key)) + ":" + _stable_stringify(dictionary[key]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var array: Array = value
			var parts: PackedStringArray = PackedStringArray()
			for item in array:
				parts.append(_stable_stringify(item))
			return "[" + ",".join(parts) + "]"
		_:
			return JSON.stringify(value)
