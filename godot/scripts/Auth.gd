extends Node

var uid: String = ""
var id_token: String = ""

signal signed_in

func sign_in_anonymous() -> void:
	var url = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + FirebaseConfig.API_KEY
	if OS.get_name() == "Web":
		_fetch_post(url, {"returnSecureToken": true}, _on_sign_in_data)
	else:
		var http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(_on_sign_in_http.bind(http))
		http.request(url, PackedStringArray(["Content-Type: application/json", "Accept-Encoding: identity"]), HTTPClient.METHOD_POST,
				JSON.stringify({"returnSecureToken": true}))

func _fetch_post(url: String, body: Dictionary, callback: Callable) -> void:
	var body_json := JSON.stringify(body)
	var js := """
		(async () => {
			try {
				const r = await fetch('%s', {
					method: 'POST',
					headers: {'Content-Type': 'application/json'},
					body: '%s'
				});
				const t = await r.text();
				window._godot_auth_result = t;
			} catch(e) {
				window._godot_auth_result = JSON.stringify({error: e.toString()});
			}
		})();
	""".format([url, body_json.replace("'", "\\'")], "%s")
	JavaScriptBridge.eval(js)
	_poll_js_result(callback)

var _poll_timer: Timer = null
var _poll_callback: Callable

func _poll_js_result(callback: Callable) -> void:
	_poll_callback = callback
	_poll_timer = Timer.new()
	add_child(_poll_timer)
	_poll_timer.wait_time = 0.1
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_check_js_result)
	_poll_timer.start()

func _check_js_result() -> void:
	var result = JavaScriptBridge.eval("window._godot_auth_result")
	if result == null or result == JavaScriptBridge.eval("undefined"):
		return
	JavaScriptBridge.eval("delete window._godot_auth_result")
	_poll_timer.stop()
	_poll_timer.queue_free()
	_poll_timer = null
	var data: Variant = JSON.parse_string(str(result))
	_poll_callback.call(data)

func _on_sign_in_data(data: Variant) -> void:
	if data == null or not data.has("localId"):
		push_error("Auth: sign-in failed — " + str(data))
		return
	uid = data["localId"]
	id_token = data["idToken"]
	emit_signal("signed_in")

func _on_sign_in_http(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data == null or not data.has("localId"):
		push_error("Auth: sign-in failed — " + body.get_string_from_utf8())
		return
	uid = data["localId"]
	id_token = data["idToken"]
	emit_signal("signed_in")
