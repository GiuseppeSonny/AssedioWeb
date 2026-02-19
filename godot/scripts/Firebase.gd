extends Node

func db_put(path: String, payload: Dictionary, callback: Callable) -> void:
	_request(
		FirebaseConfig.DB_URL + path + ".json?auth=" + Auth.id_token,
		HTTPClient.METHOD_PUT,
		payload,
		callback
	)

func db_get(path: String, callback: Callable) -> void:
	_request(
		FirebaseConfig.DB_URL + path + ".json?auth=" + Auth.id_token,
		HTTPClient.METHOD_GET,
		{},
		callback
	)

func call_function(name: String, data: Dictionary, callback: Callable) -> void:
	_request(
		FirebaseConfig.FUNCTIONS_URL + "/" + name,
		HTTPClient.METHOD_POST,
		{"data": data},
		callback,
		["Authorization: Bearer " + Auth.id_token]
	)

func _request(url: String, method: int, body: Dictionary, callback: Callable,
		extra_headers: Array = []) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_res: int, _code: int, _hdrs: PackedStringArray, b: PackedByteArray) -> void:
		http.queue_free()
		var parsed = JSON.parse_string(b.get_string_from_utf8())
		callback.call(parsed)
	)
	var headers: Array = ["Content-Type: application/json", "Accept-Encoding: identity"] + extra_headers
	var body_str: String = JSON.stringify(body) if not body.is_empty() else ""
	http.request(url, PackedStringArray(headers), method, body_str)
