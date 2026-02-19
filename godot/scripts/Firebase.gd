extends Node

func db_put(path: String, payload: Dictionary, callback: Callable) -> void:
	var url := FirebaseConfig.DB_URL + path + ".json?auth=" + Auth.id_token
	if OS.get_name() == "Web":
		_fetch(url, "PUT", payload, {}, callback)
	else:
		_http_request(url, HTTPClient.METHOD_PUT, payload, [], callback)

func db_get(path: String, callback: Callable) -> void:
	var url := FirebaseConfig.DB_URL + path + ".json?auth=" + Auth.id_token
	if OS.get_name() == "Web":
		_fetch(url, "GET", {}, {}, callback)
	else:
		_http_request(url, HTTPClient.METHOD_GET, {}, [], callback)

func call_function(name: String, data: Dictionary, callback: Callable) -> void:
	var url := FirebaseConfig.FUNCTIONS_URL + "/" + name
	if OS.get_name() == "Web":
		_fetch(url, "POST", {"data": data}, {"Authorization": "Bearer " + Auth.id_token}, callback)
	else:
		_http_request(url, HTTPClient.METHOD_POST, {"data": data},
				["Authorization: Bearer " + Auth.id_token], callback)

var _pending_fetches: Array = []

func _fetch(url: String, method: String, body: Dictionary, extra_headers: Dictionary, callback: Callable) -> void:
	var slot := _pending_fetches.size()
	_pending_fetches.append(null)
	var body_str := JSON.stringify(body) if not body.is_empty() else ""
	var headers_js := "{\"Content-Type\": \"application/json\"}"
	for k in extra_headers:
		headers_js = headers_js.substr(0, headers_js.length() - 1) + ", \"%s\": \"%s\"}" % [k, extra_headers[k]]
	var body_js := "null" if body_str.is_empty() else "'%s'" % body_str.replace("'", "\\'")
	var key := "_godot_fetch_%d" % slot
	var js := """(async () => {
		try {
			const r = await fetch('%s', {method:'%s', headers:%s, body:%s});
			window['%s'] = await r.text();
		} catch(e) { window['%s'] = JSON.stringify({error:e.toString()}); }
	})();""".format([url, method, headers_js, body_js, key, key], "%s")
	JavaScriptBridge.eval(js)
	_poll_fetch(slot, key, callback)

func _poll_fetch(slot: int, key: String, callback: Callable) -> void:
	var t := Timer.new()
	add_child(t)
	t.wait_time = 0.1
	t.autostart = true
	t.timeout.connect(func() -> void:
		var result = JavaScriptBridge.eval("window['%s']" % key)
		if result == null:
			return
		JavaScriptBridge.eval("delete window['%s']" % key)
		t.stop()
		t.queue_free()
		if slot < _pending_fetches.size():
			_pending_fetches[slot] = true
		print("Firebase._fetch result [%s]: " % key, str(result).substr(0, 200))
		var parsed: Variant = JSON.parse_string(str(result))
		callback.call(parsed)
	)
	t.start()

func _http_request(url: String, method: int, body: Dictionary, extra_headers: Array, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_res: int, _code: int, _hdrs: PackedStringArray, b: PackedByteArray) -> void:
		http.queue_free()
		var parsed: Variant = JSON.parse_string(b.get_string_from_utf8())
		callback.call(parsed)
	)
	var headers: Array = ["Content-Type: application/json", "Accept-Encoding: identity"] + extra_headers
	var body_str: String = JSON.stringify(body) if not body.is_empty() else ""
	http.request(url, PackedStringArray(headers), method, body_str)
