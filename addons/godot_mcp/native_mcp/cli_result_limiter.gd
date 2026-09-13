class_name CliResultLimiter
extends RefCounted

const DEFAULT_MAX_BYTES: int = 65536
const DEFAULT_LIST_LIMIT: int = 50
const MAX_MAX_BYTES: int = 4 * 1024 * 1024
const COLLECTION_KEYS: PackedStringArray = [
	"resources", "scripts", "scenes", "logs", "nodes", "tools",
	"items", "results", "children",
]

func apply(value: Variant, options: Dictionary = {}) -> Dictionary:
	var fields: PackedStringArray = _parse_fields(options.get("fields", PackedStringArray()))
	var limit: int = DEFAULT_LIST_LIMIT
	if options.has("limit"):
		limit = int(options["limit"])
		if limit <= 0:
			return {"error": {"code": "INVALID_ARGUMENT", "message": "limit must be greater than zero"}}
	var cursor: int = maxi(int(str(options.get("cursor", "0"))), 0)
	var depth: int = int(options.get("depth", -1))
	var max_bytes: int = clampi(int(options.get("max_bytes", DEFAULT_MAX_BYTES)), 1024, MAX_MAX_BYTES)
	var transformed: Variant = _limit_depth(value, depth) if depth >= 0 else value
	if not fields.is_empty():
		transformed = _project_fields(transformed, fields)
	var pagination: Dictionary = _paginate(transformed, limit, cursor)
	transformed = pagination["data"]
	var next_cursor: String = str(pagination["next_cursor"])
	var serialized: String = JSON.stringify(transformed)
	var size_bytes: int = serialized.to_utf8_buffer().size()
	if size_bytes <= max_bytes:
		return {
			"data": transformed,
			"truncated": not next_cursor.is_empty(),
			"next_cursor": next_cursor,
		}
	return {
		"data": null,
		"truncated": true,
		"next_cursor": next_cursor,
		"error": {
			"code": "OUTPUT_TOO_LARGE",
			"message": "Output exceeds max_bytes; use fields, limit, depth, or an output file",
			"size_bytes": size_bytes,
			"max_bytes": max_bytes,
		},
	}

func _paginate(value: Variant, limit: int, cursor: int) -> Dictionary:
	if limit <= 0:
		return {"data": value, "next_cursor": ""}
	if value is Array:
		return _slice_array(value, limit, cursor)
	if value is Dictionary:
		var source: Dictionary = value
		for key in COLLECTION_KEYS:
			if source.get(key) is Array:
				var source_array: Array = source[key]
				var backend_paged: bool = source.has("total_available") and int(source["total_available"]) > source_array.size()
				var slice_cursor: int = 0 if backend_paged else cursor
				var sliced: Dictionary = _slice_array(source_array, limit, slice_cursor)
				var result: Dictionary = source.duplicate(true)
				result[key] = sliced["data"]
				if result.has("count"):
					result["count"] = (sliced["data"] as Array).size()
				var next_cursor: String = str(sliced["next_cursor"])
				if source.has("total_available"):
					var next_offset: int = cursor + (sliced["data"] as Array).size()
					if int(source["total_available"]) > next_offset:
						next_cursor = str(next_offset)
				return {"data": result, "next_cursor": next_cursor}
	return {"data": value, "next_cursor": ""}

func _slice_array(value: Array, limit: int, cursor: int) -> Dictionary:
	var start: int = mini(cursor, value.size())
	var end: int = mini(start + limit, value.size())
	return {
		"data": value.slice(start, end),
		"next_cursor": str(end) if end < value.size() else "",
	}

func _parse_fields(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	if value is Array:
		return PackedStringArray(value)
	if value is String and not value.is_empty():
		return value.split(",", false)
	return PackedStringArray()

func _project_fields(value: Variant, fields: PackedStringArray) -> Variant:
	if value is Array:
		var projected_array: Array = []
		for item in value:
			projected_array.append(_project_fields(item, fields))
		return projected_array
	if not (value is Dictionary):
		return value
	var source: Dictionary = value
	var projected: Dictionary = {}
	var matched_field: bool = false
	for field in fields:
		if source.has(field):
			projected[field] = _project_fields(source[field], fields)
			matched_field = true
	if source.has("children"):
		projected["children"] = _project_fields(source["children"], fields)
	if not matched_field:
		for key in source:
			var child: Variant = source[key]
			if child is Dictionary or child is Array:
				var projected_child: Variant = _project_fields(child, fields)
				if not _is_empty_container(projected_child):
					projected[key] = projected_child
	return projected

func _is_empty_container(value: Variant) -> bool:
	return (value is Dictionary or value is Array) and value.is_empty()

func _limit_depth(value: Variant, remaining_depth: int) -> Variant:
	if remaining_depth < 0:
		return value
	if remaining_depth == 0:
		if value is Dictionary or value is Array:
			return {"truncated": true}
		return value
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _limit_depth(value[key], remaining_depth - 1)
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_limit_depth(item, remaining_depth - 1))
		return result
	return value
