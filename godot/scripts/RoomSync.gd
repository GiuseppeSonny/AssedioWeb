extends Node

signal remote_moved(pos: Vector2)
signal remote_disconnected

var room_id: String = ""
var local_player: CharacterBody2D = null

var _push_timer: Timer = null

var _sse_client: HTTPClient = null
var _sse_connected: bool = false
var _sse_request_sent: bool = false
var _sse_buffer: String = ""
var _sse_path: String = ""

func start(rid: String, player: CharacterBody2D) -> void:
	room_id = rid
	local_player = player
	_start_push_timer()
	_start_sse_listener()

func stop() -> void:
	if _push_timer:
		_push_timer.stop()
		_push_timer.queue_free()
		_push_timer = null
	if _sse_client:
		_sse_client.close()
		_sse_client = null

# --- T13: Position push ---

func _start_push_timer() -> void:
	_push_timer = Timer.new()
	add_child(_push_timer)
	_push_timer.wait_time = 0.1
	_push_timer.autostart = true
	_push_timer.timeout.connect(_push_position)
	_push_timer.start()

func _push_position() -> void:
	if local_player == null or room_id == "":
		return
	var path := "/rooms/%s/players/%s" % [room_id, Auth.uid]
	Firebase.db_put(path, {
		"x": local_player.position.x,
		"y": local_player.position.y,
		"last_seen": Time.get_unix_time_from_system() * 1000
	}, func(_r: Variant) -> void: pass)

# --- T14a: Open SSE connection ---

func _start_sse_listener() -> void:
	var host := FirebaseConfig.DB_URL.replace("https://", "")
	_sse_path = "/rooms/%s/players.json?auth=%s" % [room_id, Auth.id_token]
	_sse_client = HTTPClient.new()
	_sse_client.connect_to_host("https://" + host, 443, TLSOptions.client())
	_sse_connected = false
	_sse_request_sent = false
	_sse_buffer = ""

# --- T14b: Poll and buffer SSE chunks ---

func _process(_delta: float) -> void:
	if _sse_client == null:
		return
	_sse_client.poll()
	var status := _sse_client.get_status()

	if status == HTTPClient.STATUS_CONNECTED and not _sse_request_sent:
		_sse_client.request(HTTPClient.METHOD_GET, _sse_path,
				PackedStringArray(["Accept: text/event-stream"]))
		_sse_request_sent = true

	elif status == HTTPClient.STATUS_BODY:
		var chunk := _sse_client.read_response_body_chunk()
		if chunk.size() > 0:
			_sse_buffer += chunk.get_string_from_utf8()
			_flush_sse_buffer()

	elif status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_CANT_CONNECT:
		push_error("RoomSync SSE: connection error, retrying...")
		_start_sse_listener()

func _flush_sse_buffer() -> void:
	while "\n" in _sse_buffer:
		var idx := _sse_buffer.find("\n")
		var line := _sse_buffer.substr(0, idx)
		_sse_buffer = _sse_buffer.substr(idx + 1)
		_parse_sse_line(line.strip_edges())

# --- T14c: Parse SSE lines and emit remote_moved ---

func _parse_sse_line(line: String) -> void:
	if not line.begins_with("data:"):
		return
	var json: Variant = JSON.parse_string(line.substr(5).strip_edges())
	if json == null or not json.has("data") or json["data"] == null:
		return
	var players: Dictionary = json["data"]
	var found_remote := false
	for player_uid in players:
		if player_uid == Auth.uid:
			continue
		found_remote = true
		var p: Dictionary = players[player_uid]
		emit_signal("remote_moved", Vector2(float(p["x"]), float(p["y"])))
	if not found_remote:
		emit_signal("remote_disconnected")
