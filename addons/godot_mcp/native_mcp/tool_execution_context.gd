class_name ToolExecutionContext
extends RefCounted

var caller: String = "mcp"
var request_id: String = ""
var dry_run: bool = false
var apply_confirmed: bool = false
var allow_open_world: bool = false
var max_bytes: int = 65536
var fields: PackedStringArray = PackedStringArray()
var limit: int = 0
var cursor: String = ""
var depth: int = -1
