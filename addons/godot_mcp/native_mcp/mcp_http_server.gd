extends "res://addons/godot_mcp/native_mcp/mcp_http_server_legacy.gd"

var _cli_api_handler: CliApiHandler = null

func _handle_post_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	if str(parsed.get("path", "")).begins_with("/cli/v1"):
		_dispatch_cli_request(peer, parsed)
		return
	super._handle_post_request(peer, parsed)

func _handle_get_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	if str(parsed.get("path", "")).begins_with("/cli/v1"):
		_dispatch_cli_request(peer, parsed)
		return
	super._handle_get_request(peer, parsed)

func _handle_options_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	if str(parsed.get("path", "")).begins_with("/cli/v1"):
		var response: String = "HTTP/1.1 204 No Content\r\n"
		response += "Access-Control-Allow-Origin: " + _cors_origin + "\r\n"
		response += "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
		response += "Access-Control-Allow-Headers: Content-Type, Authorization, X-GDMCP-API-Version\r\n"
		response += "Access-Control-Max-Age: 86400\r\n\r\n"
		peer.put_data(response.to_utf8_buffer())
		peer.disconnect_from_host()
		return
	super._handle_options_request(peer, parsed)

func _dispatch_cli_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	if not _allow_remote and not _is_loopback(peer):
		_send_cli_error(peer, 403, "REMOTE_CLI_DISABLED", "CLI API accepts loopback requests only")
		return
	call_deferred("_handle_cli_request_on_main", peer, parsed)

func _handle_cli_request_on_main(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	if _cli_api_handler == null:
		var plugin: Object = null
		if Engine.has_meta("GodotMCPPlugin"):
			plugin = Engine.get_meta("GodotMCPPlugin")
		var server_core: RefCounted = null
		if plugin != null:
			server_core = plugin.get("_native_server") as RefCounted
		_cli_api_handler = CliApiHandler.new()
		_cli_api_handler.configure(server_core, plugin, _auth_manager != null)
	var response: Dictionary = await _cli_api_handler.handle_request(
		str(parsed.get("method", "")),
		str(parsed.get("path", "")),
		parsed.get("headers", {}),
		str(parsed.get("body", ""))
	)
	_send_cli_response(peer, response)

func _send_cli_response(peer: StreamPeerTCP, response: Dictionary) -> void:
	_send_json_status(peer, int(response.get("status", 500)), response.get("body", {}))

func _send_cli_error(peer: StreamPeerTCP, status: int, code: String, message: String) -> void:
	_send_json_status(peer, status, {
		"schema_version": 1,
		"api_version": 1,
		"ok": false,
		"data": null,
		"error": {"code": code, "message": message, "retryable": false},
		"meta": {"truncated": false, "next_cursor": null},
	})

func _send_json_status(peer: StreamPeerTCP, status: int, data: Dictionary) -> void:
	var body: PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	var header: String = "HTTP/1.1 " + str(status) + " " + _status_text(status) + "\r\n"
	header += "Content-Type: application/json; charset=utf-8\r\n"
	header += "Content-Length: " + str(body.size()) + "\r\n"
	header += "Access-Control-Allow-Origin: " + _cors_origin + "\r\n"
	header += "Connection: close\r\n\r\n"
	peer.put_data(header.to_utf8_buffer() + body)
	peer.disconnect_from_host()

func _status_text(status: int) -> String:
	match status:
		200: return "OK"
		400: return "Bad Request"
		401: return "Unauthorized"
		403: return "Forbidden"
		404: return "Not Found"
		409: return "Conflict"
		413: return "Payload Too Large"
		422: return "Unprocessable Content"
		_: return "Error"

func _is_loopback(peer: StreamPeerTCP) -> bool:
	var host: String = peer.get_connected_host()
	return host == "127.0.0.1" or host == "::1" or host == "0:0:0:0:0:0:0:1"
