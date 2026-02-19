# ASSEDIO (com.scirocco.assedio) — MVP Subtasks

Each task below is self-contained and can be completed independently or handed off individually.
Complete them in order within each phase; phases can overlap once their first task is done.

---

## Phase 1 — Firebase Backend

### T01a · Create Firebase project
**Deliverable:** A Firebase project named `assedio` exists in the console.
- Go to [console.firebase.google.com](https://console.firebase.google.com), click **Add project**, name it `assedio`.
- Disable Google Analytics (not needed for MVP).
- **Done when:** Project dashboard loads at `console.firebase.google.com/project/assedio`.

---

### T01b · Enable Anonymous Authentication
**Deliverable:** Anonymous sign-in is active.
- **Authentication → Sign-in method → Anonymous → Enable**.
- **Done when:** Anonymous is listed as an enabled provider.

---

### T01c · Create Realtime Database
**Deliverable:** A Realtime Database instance exists and its URL is noted.
- **Realtime Database → Create database → choose region → Start in test mode**.
- Copy the `databaseURL` (e.g. `https://assedio-default-rtdb.firebaseio.com`).
- **Done when:** DB console shows an empty root node and the URL is saved.

---

### T01d · Link billing account and enable Cloud Functions
**Deliverable:** Cloud Functions tab is accessible.
- **Project Settings → Usage and billing → Modify plan → Blaze** (pay-as-you-go; free quota covers the MVP).
- **Build → Functions → Get started**.
- **Done when:** Functions dashboard loads without an "upgrade required" banner.

---

### T01e · Collect and save credentials
**Deliverable:** All values needed for `firebase_config.gd` are written down.
- **Project Settings → General → Your apps → Web app** (add one if absent).
- Copy: `apiKey`, `projectId`, `databaseURL`, Functions region (e.g. `us-central1`).
- **Done when:** All four values are recorded somewhere safe.

---

### T02 · Database security rules
**Deliverable:** `firebase/database.rules.json` deployed to the project.
- Create the file `firebase/database.rules.json`:
```json
{
  "rules": {
    "rooms": {
      "$room_id": {
        ".read": "auth != null",
        "players": {
          "$uid": {
            ".write": "auth != null && auth.uid === $uid"
          }
        }
      }
    }
  }
}
```
- Deploy with: `firebase deploy --only database`
- **Done when:** The rules are live and a test write with a mismatched UID is rejected.

---

### T03a · Write `joinRoom` Cloud Function code
**Deliverable:** `firebase/functions/index.js` contains `joinRoom` (not yet deployed).

```js
const { onCall } = require("firebase-functions/v2/https");
const { getDatabase } = require("firebase-admin/database");
const { initializeApp } = require("firebase-admin/app");

initializeApp();

exports.joinRoom = onCall(async (request) => {
  const uid = request.auth.uid;
  const db = getDatabase();
  const roomsRef = db.ref("rooms");
  const snapshot = await roomsRef.orderByChild("status").equalTo("waiting").limitToFirst(1).get();
  let roomId;
  if (snapshot.exists()) {
    snapshot.forEach((child) => { roomId = child.key; });
    await roomsRef.child(`${roomId}/players/${uid}`).set({ x: 64, y: 64, last_seen: Date.now() });
    await roomsRef.child(`${roomId}/status`).set("full");
  } else {
    const newRoom = roomsRef.push();
    roomId = newRoom.key;
    await newRoom.set({ status: "waiting", players: { [uid]: { x: 64, y: 64, last_seen: Date.now() } } });
  }
  return { room_id: roomId };
});
```
- **Done when:** File saved, `node -e "require('./index.js')"` exits without syntax errors.

---

### T03b · Deploy `joinRoom`
**Deliverable:** `joinRoom` is live and reachable via HTTPS.
- Run: `firebase deploy --only functions:joinRoom`
- **Done when:** CLI prints a function URL and Functions dashboard shows `joinRoom` as deployed.

---

### T04a · Write `leaveRoom` Cloud Function code
**Deliverable:** `leaveRoom` added to `firebase/functions/index.js` (not yet deployed).

```js
exports.leaveRoom = onCall(async (request) => {
  const uid = request.auth.uid;
  const { room_id } = request.data;
  const db = getDatabase();
  const roomRef = db.ref(`rooms/${room_id}`);
  await roomRef.child(`players/${uid}`).remove();
  const playersSnap = await roomRef.child("players").get();
  if (!playersSnap.exists()) {
    await roomRef.remove();
  } else {
    await roomRef.child("status").set("waiting");
  }
  return { ok: true };
});
```
- **Done when:** File saved, no syntax errors.

---

### T04b · Deploy `leaveRoom`
**Deliverable:** Both functions live in Firebase.
- Run: `firebase deploy --only functions:leaveRoom`
- **Done when:** Functions dashboard shows both `joinRoom` and `leaveRoom` as deployed.

---

### T05a · Get anonymous tokens
**Deliverable:** Two valid `idToken` values ready for testing.
```
POST https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=<API_KEY>
Body: { "returnSecureToken": true }
```
- Run twice to get Token A and Token B.
- **Done when:** Both responses contain a non-empty `idToken` and `localId`.

---

### T05b · Test `joinRoom` with two tokens
**Deliverable:** Two players join the same room; DB shows `status: "full"`.
- Call `joinRoom` with Token A, then Token B. Both should return the same `room_id`.
- Open the Firebase DB console and confirm `status` is `"full"` and two UIDs appear under `players`.
- **Done when:** DB shows the room with two players and `status: "full"`.

---

### T05c · Test `leaveRoom`
**Deliverable:** Leaving cleans up the room correctly.
- Call `leaveRoom` with Token A: DB should show `status: "waiting"` and only Token B's UID.
- Call `leaveRoom` with Token B: room node should be deleted entirely.
- **Done when:** DB shows no leftover room nodes.

---

## Phase 2 — Godot Firebase Layer

### T06 · Godot project scaffold
**Deliverable:** A runnable Godot 4 project with the correct folder structure and app identity.

- Create a new Godot 4 project in `game/godot/`.
- In **Project Settings → Application → Config**:
  - Name: `ASSEDIO`
  - Bundle identifier: `com.scirocco.assedio`
- Create empty folders: `scenes/`, `scripts/`, `assets/sprites/`, `assets/tilemaps/`.
- In **Project Settings → Autoload**, register (files created in later tasks):
  - `scripts/firebase_config.gd` → `FirebaseConfig`
  - `scripts/Auth.gd` → `Auth`
  - `scripts/Firebase.gd` → `Firebase`
  - `scripts/Matchmaking.gd` → `Matchmaking`
- **Done when:** Project opens and runs to a blank window without errors.

---

### T07a · Create `firebase_config.gd`
**Deliverable:** Credentials file exists with the four values from T01e. **Never commit to git** — add to `.gitignore`.

`scripts/firebase_config.gd`:
```gdscript
extends Node

const API_KEY       = "YOUR_API_KEY"
const PROJECT_ID    = "assedio"
const DB_URL        = "https://assedio-default-rtdb.firebaseio.com"
const FUNCTIONS_URL = "https://us-central1-assedio.cloudfunctions.net"
```
- Add `scripts/firebase_config.gd` to `.gitignore`.
- **Done when:** File exists and is registered as Autoload `FirebaseConfig`.

---

### T07b · Implement `Auth.gd`
**Deliverable:** Autoload singleton that signs in anonymously and stores `uid` + `id_token`.

`scripts/Auth.gd`:
```gdscript
extends Node

var uid: String = ""
var id_token: String = ""
signal signed_in

func sign_in_anonymous() -> void:
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_sign_in.bind(http))
    var url = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + FirebaseConfig.API_KEY
    http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST,
                 JSON.stringify({"returnSecureToken": true}))

func _on_sign_in(_result, _code, _headers, body, http: HTTPRequest) -> void:
    http.queue_free()
    var data = JSON.parse_string(body.get_string_from_utf8())
    uid = data["localId"]
    id_token = data["idToken"]
    emit_signal("signed_in")
```
- **Done when:** File saved, no GDScript parse errors.

---

### T07c · Verify anonymous sign-in
**Deliverable:** Running the project prints a valid `uid` to the Output panel.
- Add a temporary `_ready()` that calls `Auth.sign_in_anonymous()` and on `Auth.signed_in` prints `Auth.uid`.
- **Done when:** A non-empty UID (28-char string) appears in Output. Remove the temporary print after.

---

### T08 · `Firebase.gd` HTTP helper
**Deliverable:** A reusable singleton for all Firebase REST calls.

`scripts/Firebase.gd` — Autoload singleton:
```gdscript
extends Node

func db_put(path: String, payload: Dictionary, callback: Callable) -> void:
    _request(FirebaseConfig.DB_URL + path + ".json?auth=" + Auth.id_token,
             HTTPClient.METHOD_PUT, payload, callback)

func db_get(path: String, callback: Callable) -> void:
    _request(FirebaseConfig.DB_URL + path + ".json?auth=" + Auth.id_token,
             HTTPClient.METHOD_GET, {}, callback)

func call_function(name: String, data: Dictionary, callback: Callable) -> void:
    _request(FirebaseConfig.FUNCTIONS_URL + "/" + name,
             HTTPClient.METHOD_POST, {"data": data}, callback,
             ["Content-Type: application/json", "Authorization: Bearer " + Auth.id_token])

func _request(url: String, method: int, body: Dictionary, callback: Callable,
              extra_headers: Array = []) -> void:
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(func(res, code, hdrs, b):
        http.queue_free()
        callback.call(JSON.parse_string(b.get_string_from_utf8()))
    )
    var headers = ["Content-Type: application/json"] + extra_headers
    http.request(url, headers, method, JSON.stringify(body) if body else "")
```
- **Done when:** A test call to `Firebase.db_put("/test/ping", {"ok": true}, ...)` writes to the DB.

---

### T09 · `Matchmaking.gd`
**Deliverable:** The game can join a room and receive a `room_id`.

`scripts/Matchmaking.gd` — Autoload singleton:
```gdscript
extends Node

var room_id: String = ""
signal room_joined(room_id: String)
signal room_left

func join() -> void:
    Firebase.call_function("joinRoom", {}, func(data):
        room_id = data["result"]["room_id"]
        emit_signal("room_joined", room_id)
    )

func leave() -> void:
    if room_id == "":
        return
    Firebase.call_function("leaveRoom", {"room_id": room_id}, func(_data):
        room_id = ""
        emit_signal("room_left")
    )
```
- **Done when:** Calling `Matchmaking.join()` from a test script prints a valid `room_id`.

---

## Phase 3 — Game World

### T10a · Create TileSet
**Deliverable:** A `TileSet` resource with two tiles: floor and wall.
- In Godot editor: **TileMap → TileSet → New TileSet**.
- Add a 16×16 px floor tile (plain color or texture) and a 16×16 px wall tile.
- **Done when:** Both tiles are visible in the TileSet panel.

---

### T10b · Draw room layout
**Deliverable:** A closed room drawn in the TileMap (20×15 tiles, walls on all four sides).
- Select the wall tile and paint the border of a 20×15 grid.
- Fill the interior with the floor tile.
- **Done when:** The room is visible in the 2D editor with a clear wall border.

---

### T10c · Add wall collision
**Deliverable:** `CharacterBody2D` cannot pass through wall tiles.
- In the TileSet editor, select the wall tile → **Physics → Add collision polygon** (full-tile square).
- Place a `CharacterBody2D` in the scene and run; confirm it stops at walls.
- **Done when:** Player cannot walk outside the room boundary.

---

### T11 · `Player.tscn` — character scene
**Deliverable:** A visible player node with physics and collision.

- Create `scenes/Player.tscn`:
  - Root: `CharacterBody2D`
  - Children: `CollisionShape2D` (8×16 px capsule), `Sprite2D` (placeholder colored rectangle)
- Export a `@export var is_local: bool = true` variable.
- **Done when:** The scene can be instanced in `Room.tscn` and shows a colored rectangle.

---

### T12 · `Player.gd` — movement
**Deliverable:** The local player moves with WASD; the remote player does not respond to input.

`scripts/Player.gd`:
```gdscript
extends CharacterBody2D

@export var is_local: bool = true
const SPEED = 80.0

func _physics_process(_delta: float) -> void:
    if not is_local:
        return
    var dir = Vector2(
        Input.get_axis("ui_left", "ui_right"),
        Input.get_axis("ui_up", "ui_down")
    ).normalized()
    velocity = dir * SPEED
    move_and_slide()
```
- **Done when:** Local player moves smoothly and stops at room walls; remote instance stays still.

---

### T13 · `RoomSync.gd` — position push
**Deliverable:** The local player's position is written to Firebase every 100 ms.

`scripts/RoomSync.gd` (attached to `Room.tscn`):
```gdscript
extends Node

var local_player: CharacterBody2D
var room_id: String

func start(rid: String, player: CharacterBody2D) -> void:
    room_id = rid
    local_player = player
    var timer = Timer.new()
    add_child(timer)
    timer.wait_time = 0.1
    timer.autostart = true
    timer.timeout.connect(_push_position)
    timer.start()

func _push_position() -> void:
    var path = "/rooms/%s/players/%s" % [room_id, Auth.uid]
    Firebase.db_put(path, {
        "x": local_player.position.x,
        "y": local_player.position.y,
        "last_seen": Time.get_unix_time_from_system() * 1000
    }, func(_r): pass)
```
- **Done when:** Moving the local player updates the DB node every ~100 ms (visible in Firebase console).

---

### T14a · Open SSE connection
**Deliverable:** `RoomSync.gd` establishes a persistent HTTPS connection to the Realtime DB SSE endpoint.

Add to `RoomSync.gd`:
```gdscript
var _sse_client: HTTPClient
var _sse_connected: bool = false
signal remote_moved(pos: Vector2)

func start_sse_listener() -> void:
    var host = FirebaseConfig.DB_URL.replace("https://", "")
    _sse_client = HTTPClient.new()
    _sse_client.connect_to_host("https://" + host, 443, TLSOptions.client())
    _sse_connected = false
```
- **Done when:** Polling `_sse_client.get_status()` in `_process` eventually reaches `STATUS_CONNECTED`.

---

### T14b · Poll and buffer SSE chunks
**Deliverable:** Raw SSE text is received and buffered, handling partial lines correctly.

Add to `RoomSync.gd`:
```gdscript
var _sse_path: String
var _sse_buffer: String = ""

func _process(_delta: float) -> void:
    if _sse_client == null:
        return
    _sse_client.poll()
    var status = _sse_client.get_status()
    if status == HTTPClient.STATUS_CONNECTED and not _sse_connected:
        _sse_path = "/rooms/%s/players.json?auth=%s" % [room_id, Auth.id_token]
        _sse_client.request(HTTPClient.METHOD_GET, _sse_path, ["Accept: text/event-stream"])
        _sse_connected = true
    elif status == HTTPClient.STATUS_BODY:
        var chunk = _sse_client.read_response_body_chunk()
        if chunk.size() > 0:
            _sse_buffer += chunk.get_string_from_utf8()
            _flush_sse_buffer()

func _flush_sse_buffer() -> void:
    while "\n" in _sse_buffer:
        var idx = _sse_buffer.find("\n")
        var line = _sse_buffer.substr(0, idx)
        _sse_buffer = _sse_buffer.substr(idx + 1)
        _parse_sse_line(line)
```
- **Done when:** Lines are printed to Output when the DB is written to from another client.

---

### T14c · Parse SSE lines and emit `remote_moved`
**Deliverable:** Each position update from the remote player emits the `remote_moved` signal.

Add to `RoomSync.gd`:
```gdscript
func _parse_sse_line(line: String) -> void:
    if not line.begins_with("data:"):
        return
    var json = JSON.parse_string(line.substr(5).strip_edges())
    if json == null or not json.has("data") or json["data"] == null:
        return
    var players = json["data"]
    for player_uid in players:
        if player_uid != Auth.uid:
            var p = players[player_uid]
            emit_signal("remote_moved", Vector2(float(p["x"]), float(p["y"])))
```
- **Done when:** Moving the remote client causes `remote_moved` to fire on the listening client (verify with a `print` connected to the signal).

---

### T15 · Remote player spawn and interpolation
**Deliverable:** The remote player appears and moves smoothly on the local screen.

In `Room.tscn`'s script:
```gdscript
var remote_player: CharacterBody2D

func _on_remote_moved(pos: Vector2) -> void:
    if remote_player == null:
        remote_player = preload("res://scenes/Player.tscn").instantiate()
        remote_player.is_local = false
        add_child(remote_player)
    remote_player.position = remote_player.position.lerp(pos, 0.3)
```
- Connect `RoomSync.remote_moved` → `_on_remote_moved`.
- **Done when:** Two game windows open side by side show each other's character moving smoothly.

---

## Phase 4 — UI & Polish

### T16a · Build `Main.tscn` scene tree
**Deliverable:** The main menu scene has all UI nodes in place.
- Create `scenes/Main.tscn`.
- Add a `CanvasLayer` with:
  - `Label` (text: `ASSEDIO`, centered, large font)
  - `Button` (text: `Find Match`, disabled by default, name: `FindMatchBtn`)
  - `Label` (text: `Waiting for opponent…`, hidden by default, name: `WaitingLabel`)
- **Done when:** The scene opens in the editor showing the three UI elements correctly positioned.

---

### T16b · Wire `Main.gd` script logic
**Deliverable:** The full auth → matchmaking → scene transition flow works.

`scripts/Main.gd` attached to `Main.tscn`:
```gdscript
extends CanvasLayer

@onready var btn = $FindMatchBtn
@onready var waiting_label = $WaitingLabel

func _ready() -> void:
    btn.disabled = true
    Auth.signed_in.connect(_on_signed_in)
    Matchmaking.room_joined.connect(_on_room_joined)
    Auth.sign_in_anonymous()

func _on_signed_in() -> void:
    btn.disabled = false

func _on_btn_pressed() -> void:
    btn.disabled = true
    waiting_label.visible = true
    Matchmaking.join()

func _on_room_joined(_room_id: String) -> void:
    get_tree().change_scene_to_file("res://scenes/Room.tscn")
```
- Connect `FindMatchBtn.pressed` → `_on_btn_pressed` in the editor.
- **Done when:** Clicking "Find Match" transitions to `Room.tscn`.

---

### T17 · Disconnect handling
**Deliverable:** Leaving the game (window close or back to menu) cleans up the Firebase room.

- In `Main.gd` or a global Autoload:
```gdscript
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        Matchmaking.leave()
        await Matchmaking.room_left
        get_tree().quit()
```
- Also call `Matchmaking.leave()` when transitioning back to the main menu.
- **Done when:** Closing one client removes its player from the DB and the other client's remote player disappears.

---

### T18 · Waiting UI and room bounds
**Deliverable:** Players see a waiting message until both are connected; movement is clamped to room bounds.

- In `Room.tscn`: show a "Waiting for opponent…" overlay until `remote_player != null`.
- In `Player.gd`, clamp position after `move_and_slide()`:
```gdscript
position = position.clamp(Vector2(8, 8), Vector2(312, 232))
```
- **Done when:** Solo player sees the waiting label; it disappears when the second player joins.

---

### T19 · Placeholder medieval sprites
**Deliverable:** Each player has a distinct colored knight silhouette instead of a plain rectangle.

- Add two 16×32 px placeholder sprites to `assets/sprites/`:
  - `knight_blue.png` (local player)
  - `knight_red.png` (remote player)
- In `Player.tscn`, set `Sprite2D` texture to `knight_blue.png`.
- When spawning the remote player in T15, set its sprite to `knight_red.png`.
- **Done when:** Two visually distinct characters appear in the room.

---

## Phase 5 — End-to-End Test

### T20 · Full integration test
**Deliverable:** Two players move independently and see each other in real time.

Checklist:
- [ ] Open two instances of the exported game (or two Godot editor runs).
- [ ] Both sign in anonymously and click "Find Match".
- [ ] First client shows "Waiting for opponent…"; second client joins and both transition to the room.
- [ ] Moving Player A updates Player B's screen within ~200 ms.
- [ ] Moving Player B updates Player A's screen within ~200 ms.
- [ ] Closing one client removes it from the DB; the other client's remote player disappears.
- [ ] No errors in Godot Output or Firebase Functions logs.
- **Done when:** All checklist items pass.

---

## Dependency Map

```
T01a → T01b → T01c → T01d → T01e
T01e → T02
T01e → T03a → T03b
T03b → T04a → T04b
T04b → T05a → T05b → T05c

T01e → T06
T06 → T07a → T07b → T07c
T07c → T08 → T09

T05c + T09 → T13 → T14a → T14b → T14c → T15

T06 → T10a → T10b → T10c
T10c + T06 → T11 → T12

T15 + T12 → T16a → T16b → T17 → T18 → T19 → T20
```

### Task count: 35 subtasks across 5 phases
