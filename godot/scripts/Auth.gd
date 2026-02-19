extends Node

var uid: String = ""
var id_token: String = ""

signal signed_in

func sign_in_anonymous() -> void:
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_sign_in.bind(http))
	var url = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + FirebaseConfig.API_KEY
	http.request(url, PackedStringArray(["Content-Type: application/json", "Accept-Encoding: identity"]), HTTPClient.METHOD_POST,
			JSON.stringify({"returnSecureToken": true}))

func _on_sign_in(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data == null or not data.has("localId"):
		push_error("Auth: sign-in failed — " + body.get_string_from_utf8())
		return
	uid = data["localId"]
	id_token = data["idToken"]
	emit_signal("signed_in")
