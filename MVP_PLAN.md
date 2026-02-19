# ASSEDIO (com.scirocco.assedio) — MVP Plan

## Goal
Two players can join a closed room, move their characters, and see each other's positions in real time.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Game Client | Godot 4 (GDScript) — project: `com.scirocco.assedio` |
| Realtime Sync | Firebase Realtime Database |
| Server Logic | Firebase Cloud Functions (Node.js, free Spark plan) |
| Auth | Firebase Anonymous Auth |

> **Free tier constraints:** Cloud Functions on Spark plan support outbound calls only to Google services. All game state lives in Realtime Database; Functions are used only for join/leave room logic (no outbound HTTP needed).

---

## Architecture Overview

```
[Godot Client A]                    [Godot Client B]
      |                                    |
      |-- HTTPS REST / Firebase SDK ------>|
      |                                    |
      +----------> Firebase <--------------+
                  |         |
         Realtime DB    Cloud Functions
         (positions)   (room management)
```

- Clients write their own position directly to Realtime Database.
- Clients listen to the other player's position node via Firebase's real-time listener.
- Cloud Functions handle room creation, player join/leave, and basic validation.
- No peer-to-peer; Firebase DB is the single source of truth.

---

## Firebase Realtime Database Schema

```json
{
  "rooms": {
    "<room_id>": {
      "status": "waiting | full | closed",
      "players": {
        "<uid_A>": {
          "x": 320.0,
          "y": 240.0,
          "last_seen": 1708000000000
        },
        "<uid_B>": {
          "x": 400.0,
          "y": 300.0,
          "last_seen": 1708000000001
        }
      }
    }
  }
}
```

### Database Rules (`database.rules.json`)

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

- Each player can only write their own position node (keyed by their UID).
- Any authenticated user can read the room (needed to see the other player).

---

## Cloud Functions (Node.js)

Only two functions are needed for the MVP. Both run on the free Spark plan.

### `joinRoom` (HTTPS Callable)
1. Verify Firebase Auth token (automatic with callable functions).
2. Find a room with `status === "waiting"`, or create a new one.
3. Add the calling UID to `rooms/<room_id>/players`.
4. If the room now has 2 players, set `status = "full"`.
5. Return `{ room_id }` to the client.

### `leaveRoom` (HTTPS Callable)
1. Verify token.
2. Remove the player's node from `rooms/<room_id>/players`.
3. If the room is now empty, delete the room document.
4. If one player remains, set `status = "waiting"`.

> **Stale player cleanup:** Each position write includes a `last_seen` timestamp. A scheduled Cloud Function (or client-side check) can remove players inactive for > 30 seconds. For the MVP this can be a simple client-side disconnect handler.

---

## Godot Project Structure

```
game/
├── project.godot
├── scenes/
│   ├── Main.tscn           # Entry point, handles auth + matchmaking UI
│   ├── Room.tscn           # The closed room / game world
│   └── Player.tscn         # Player character (local + remote variant)
├── scripts/
│   ├── Firebase.gd         # Singleton: wraps Firebase REST API calls
│   ├── Auth.gd             # Anonymous sign-in, stores uid + id_token
│   ├── Matchmaking.gd      # Calls joinRoom / leaveRoom Cloud Functions
│   ├── RoomSync.gd         # Reads/writes positions to Realtime DB
│   └── Player.gd           # Movement logic, input handling
├── assets/
│   ├── sprites/            # Character sprites (placeholder rectangles for MVP)
│   └── tilemaps/           # Room tilemap (single closed room)
└── firebase_config.gd      # Firebase project credentials (NOT committed to git)
```

---

## Godot Networking Approach

Godot 4 does not have a native Firebase SDK. The client communicates via:

1. **Firebase Auth REST API** — anonymous sign-in to get a `uid` and `idToken`.
2. **Firebase Realtime Database REST API** — `PUT` to write position, `GET` with SSE stream (`?stream=true`) to listen for changes.
3. **Cloud Functions HTTPS Callable** — standard `POST` with the `idToken` in the Authorization header.

All calls use Godot's `HTTPRequest` node or `HTTPClient`.

### Position Update Loop (`RoomSync.gd`)
```gdscript
# Called every physics frame or on a timer (e.g. 100ms)
func push_position(x: float, y: float) -> void:
    var path = "/rooms/%s/players/%s.json?auth=%s" % [room_id, uid, id_token]
    var body = JSON.stringify({"x": x, "y": y, "last_seen": Time.get_unix_time_from_system() * 1000})
    http.request(BASE_URL + path, headers, HTTPClient.METHOD_PUT, body)

# SSE listener reads the other player's node and updates their RemotePlayer position
```

---

## Scenes Detail

### `Main.tscn`
- On `_ready`: call `Auth.gd` → anonymous sign-in.
- Show "Find Match" button.
- On button press: call `Matchmaking.joinRoom()` → on success, load `Room.tscn`.

### `Room.tscn`
- Contains a `TileMap` node (single walled room, ~640×480 px).
- Spawns `Player.tscn` (local) at a fixed start position.
- Spawns a second `Player.tscn` (remote, input disabled) when the other player joins.
- `RoomSync.gd` attached here: starts SSE listener on `rooms/<room_id>/players`.
- On SSE event: update remote player's position via interpolation (`lerp`).

### `Player.tscn`
- `CharacterBody2D` + `CollisionShape2D` + `Sprite2D`.
- `Player.gd`: reads arrow keys / WASD, moves with `move_and_slide()`, respects room walls.
- A boolean `is_local` flag disables input for the remote instance.

---

## Implementation Steps (ordered)

### Phase 1 — Firebase Setup (no Godot yet)
1. Create a Firebase project (free Spark plan).
2. Enable **Anonymous Authentication**.
3. Enable **Realtime Database** (start in test mode, then apply rules above).
4. Enable **Cloud Functions** (requires billing account linked, but stays free under limits).
5. Deploy `database.rules.json`.
6. Write and deploy `joinRoom` and `leaveRoom` functions.
7. Test functions with `curl` or Postman.

### Phase 2 — Godot Firebase Layer
1. Create `firebase_config.gd` with `API_KEY`, `PROJECT_ID`, `DB_URL`.
2. Implement `Auth.gd`: POST to `identitytoolkit.googleapis.com` → store `uid` + `idToken`.
3. Implement `Firebase.gd`: generic `http_put`, `http_get`, `http_post` helpers.
4. Implement `Matchmaking.gd`: calls `joinRoom` / `leaveRoom`.
5. Test: print `room_id` to console after matchmaking.

### Phase 3 — Room & Movement
1. Build `Room.tscn` with a simple walled tilemap.
2. Build `Player.tscn` with placeholder sprite and collision.
3. Implement `Player.gd` movement (WASD, `move_and_slide`).
4. Implement `RoomSync.gd`:
   - Timer-based `push_position` (every 100 ms).
   - SSE listener for the remote player node.
5. Spawn remote player when SSE detects a second UID in the room.
6. Interpolate remote player position with `lerp`.

### Phase 4 — Polish & Cleanup
1. Handle disconnect: call `leaveRoom` on `_notification(NOTIFICATION_WM_CLOSE_REQUEST)`.
2. Show a "Waiting for opponent…" label until room is full.
3. Constrain player movement to room bounds.
4. Add basic medieval sprite placeholders.

---

## Free Tier Limits Check

| Resource | Free Limit | MVP Usage |
|---|---|---|
| Realtime DB storage | 1 GB | ~negligible |
| Realtime DB simultaneous connections | 100 | 2 |
| Realtime DB download | 10 GB/month | ~few MB |
| Cloud Functions invocations | 125K/month | ~few hundred |
| Cloud Functions compute | 40K GB-sec/month | ~negligible |

**Conclusion:** The MVP fits entirely within the Firebase free Spark plan.

---

## Out of Scope for MVP
- Rooms with more than 2 players
- Persistent player accounts
- Chat
- Combat or game mechanics
- Anti-cheat (server-authoritative position validation)
- Mobile input
