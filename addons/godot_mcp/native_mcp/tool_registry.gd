class_name ToolRegistry
extends RefCounted

var _tools: Dictionary = {}

func register_tool(definition: ToolDefinition) -> Error:
	if definition == null or not definition.is_valid():
		return ERR_INVALID_PARAMETER
	_tools[definition.name] = definition
	return OK

func unregister_tool(name: String) -> bool:
	if not _tools.has(name):
		return false
	_tools.erase(name)
	return true

func get_tool(name: String) -> ToolDefinition:
	return _tools.get(name, null)

func has_tool(name: String) -> bool:
	return _tools.has(name)

func size() -> int:
	return _tools.size()

func clear() -> void:
	_tools.clear()

func list_tools(filter: Dictionary = {}) -> Array[ToolDefinition]:
	var result: Array[ToolDefinition] = []
	var names: Array = _tools.keys()
	names.sort()
	for name in names:
		var definition: ToolDefinition = _tools[name]
		if not _matches_filter(definition, filter):
			continue
		result.append(definition)
	return result

func search_tools(query: String, limit: int = 5) -> Array[Dictionary]:
	var normalized_query: String = _normalize(query)
	var query_tokens: PackedStringArray = normalized_query.split(" ", false)
	var scored: Array[Dictionary] = []
	for definition in list_tools({"cli_allowed": true, "available": true}):
		var score: int = _score(definition, normalized_query, query_tokens)
		if score <= 0:
			continue
		var summary: Dictionary = definition.to_cli_summary()
		summary["score"] = score
		scored.append(summary)
	scored.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left["score"]) == int(right["score"]):
			return str(left["name"]) < str(right["name"])
		return int(left["score"]) > int(right["score"])
	)
	var bounded_limit: int = clampi(limit, 1, 20)
	return scored.slice(0, mini(scored.size(), bounded_limit))

func get_catalog_hash() -> String:
	var summaries: Array[Dictionary] = []
	for definition in list_tools({"cli_allowed": true, "available": true}):
		summaries.append(definition.to_cli_summary())
	return ToolDefinition._stable_stringify(summaries).sha256_text()

func to_cli_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in list_tools({"cli_allowed": true, "available": true}):
		result.append(definition.to_cli_summary())
	return result

func _matches_filter(definition: ToolDefinition, filter: Dictionary) -> bool:
	if filter.has("available") and definition.policy.available != bool(filter["available"]):
		return false
	if filter.has("mcp_visible") and definition.policy.mcp_visible != bool(filter["mcp_visible"]):
		return false
	if filter.has("cli_allowed") and definition.policy.cli_allowed != bool(filter["cli_allowed"]):
		return false
	if filter.has("category") and definition.category != str(filter["category"]):
		return false
	if filter.has("group") and definition.group != str(filter["group"]):
		return false
	return true

func _score(definition: ToolDefinition, normalized_query: String, query_tokens: PackedStringArray) -> int:
	if normalized_query.is_empty():
		return 1
	var normalized_name: String = _normalize(definition.name)
	var normalized_description: String = _normalize(definition.description)
	var normalized_group: String = _normalize(definition.group + " " + definition.category)
	if normalized_name == normalized_query:
		return 500
	if normalized_name.begins_with(normalized_query):
		return 400
	if _all_tokens_in(query_tokens, normalized_name):
		return 300
	if _all_tokens_in(query_tokens, normalized_name + " " + normalized_description):
		return 200
	if _any_token_in(query_tokens, normalized_description):
		return 100
	if _any_token_in(query_tokens, normalized_group):
		return 50
	return 0

func _normalize(value: String) -> String:
	var tokens: PackedStringArray = value.to_lower().replace("_", " ").replace("-", " ").strip_edges().split(" ", false)
	return " ".join(tokens)

func _all_tokens_in(tokens: PackedStringArray, value: String) -> bool:
	if tokens.is_empty():
		return false
	for token in tokens:
		if not value.contains(token):
			return false
	return true

func _any_token_in(tokens: PackedStringArray, value: String) -> bool:
	for token in tokens:
		if value.contains(token):
			return true
	return false
