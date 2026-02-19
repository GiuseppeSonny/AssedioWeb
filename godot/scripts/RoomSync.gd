extends Node

signal remote_moved(pos: Vector2)
signal remote_disconnected

var room_id: String = ""
var local_player: CharacterBody2D = null

var _push_timer: Timer = null
var _poll_timer: Timer = null

# Desktop SSE vars
var _sse_client: HTTPClient = null
var _sse_request_sent: bool = false
var _sse_buffer: String = ""
var _sse_path: String = ""
var _sse_event: String = ""  # current SSE event type
var _sse_players_cache: Dictionary = {}  # last known full players snapshot

func start(rid: String, player: CharacterBody2D) -> void:
	room_id = rid
	local_player = player
	_start_push_timer()
	if OS.get_name() == "Web":
		_start_web_poll()
	else:
		_start_sse_listener()

func stop() -> void:
	if _push_timer:
		_push_timer.stop()
		_push_timer.queue_free()
		_push_timer = null
	if _poll_timer:
		_poll_timer.stop()
		_poll_timer.queue_free()
		_poll_timer = null
	if _sse_client:
		_sse_client.close()
		_sse_client = null

# --- Position push (both platforms) ---

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

# --- Web: fetch polling every 200ms ---

func _start_web_poll() -> void:
	_poll_timer = Timer.new()
	add_child(_poll_timer)
	_poll_timer.wait_time = 0.2
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_web_poll_tick)
	_poll_timer.start()

func _web_poll_tick() -> void:
	var url := FirebaseConfig.DB_URL + "/rooms/%s/players.json?auth=%s" % [room_id, Auth.id_token]
	var key := "_godot_sync_result"
	var js := """(async () => {
		try {
			const r = await fetch('%s');
			window['%s'] = await r.text();
		} catch(e) { window['%s'] = 'null'; }
	})();""".format([url, key, key], "%s")
	JavaScriptBridge.eval(js)
	_wait_for_poll_result(key)

var _waiting_poll: bool = false

func _wait_for_poll_result(key: String) -> void:
	if _waiting_poll:
		return
	_waiting_poll = true
	var t := Timer.new()
	add_child(t)
	t.wait_time = 0.05
	t.autostart = true
	t.timeout.connect(func() -> void:
		var result = JavaScriptBridge.eval("window['%s']" % key)
		if result == null:
			return
		JavaScriptBridge.eval("delete window['%s']" % key)
		t.stop()
		t.queue_free()
		_waiting_poll = false
		var players: Variant = JSON.parse_string(str(result))
		_process_players(players)
	)
	t.start()

func _process_players(players: Variant) -> void:
	if players == null or typeof(players) != TYPE_DICTIONARY:
		return
	var found_remote := false
	for player_uid in players:
		if player_uid == Auth.uid:
			continue
		var entry: Variant = players[player_uid]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not entry.has("x") or not entry.has("y"):
			continue
		found_remote = true
		emit_signal("remote_moved", Vector2(float(entry["x"]), float(entry["y"])))
	if not found_remote:
		emit_signal("remote_disconnected")

# --- Desktop: SSE via HTTPClient ---

func _start_sse_listener() -> void:
	var host := FirebaseConfig.DB_URL.replace("https://", "")
	_sse_path = "/rooms/%s/players.json?auth=%s" % [room_id, Auth.id_token]
	_sse_client = HTTPClient.new()
	_sse_client.connect_to_host("https://" + host, 443, TLSOptions.client())
	_sse_request_sent = false
	_sse_buffer = ""

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

func _parse_sse_line(line: String) -> void:
	if line.begins_with("event:"):
		_sse_event = line.substr(6).strip_edges()
		return
	if not line.begins_with("data:"):
		return
	var json: Variant = JSON.parse_string(line.substr(5).strip_edges())
	if json == null or not json.has("data"):
		return
	var path: String = json.get("path", "/")
	var data: Variant = json["data"]
	if _sse_event == "put" and path == "/":
		# Full snapshot of all players
		if typeof(data) == TYPE_DICTIONARY:
			_sse_players_cache = data
			_process_players(_sse_players_cache)
	elif _sse_event == "put" or _sse_event == "patch":
		# Partial update: path is like "/uid" or "/uid/x"
		var parts := path.lstrip("/").split("/")
		if parts.size() == 1 and parts[0] != "":
			# Full player update: /uid -> {x,y,...}
			if typeof(data) == TYPE_DICTIONARY:
				_sse_players_cache[parts[0]] = data
			elif data == null:
				_sse_players_cache.erase(parts[0])
			_process_players(_sse_players_cache)
		elif parts.size() == 2 and parts[0] != "":
			# Single field update: /uid/x -> float
			if not _sse_players_cache.has(parts[0]):
				_sse_players_cache[parts[0]] = {}
			_sse_players_cache[parts[0]][parts[1]] = data
			_process_players(_sse_players_cache)
	_sse_event = ""
