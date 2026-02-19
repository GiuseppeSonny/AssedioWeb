extends Node2D

@onready var room_sync: Node = $RoomSync
@onready var waiting_label: Label = $CanvasLayer/WaitingLabel

var local_player: CharacterBody2D = null
var remote_player: CharacterBody2D = null

const PLAYER_SCENE := preload("res://scenes/Player.tscn")

func _ready() -> void:
	if Matchmaking.room_id == "" or Auth.uid == "":
		push_error("Room: entered without valid room_id or uid — returning to main")
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
		return
	_spawn_local_player()
	room_sync.remote_moved.connect(_on_remote_moved)
	room_sync.remote_disconnected.connect(_on_remote_disconnected)
	room_sync.start(Matchmaking.room_id, local_player)
	waiting_label.visible = true

func _spawn_local_player() -> void:
	local_player = PLAYER_SCENE.instantiate()
	local_player.is_local = true
	local_player.position = Vector2(64, 64)
	add_child(local_player)

# --- T15: Spawn remote player and lerp position ---

func _on_remote_moved(pos: Vector2) -> void:
	if remote_player == null:
		remote_player = PLAYER_SCENE.instantiate()
		remote_player.is_local = false
		remote_player.position = pos
		add_child(remote_player)
		waiting_label.visible = false

	remote_player.position = remote_player.position.lerp(pos, 0.3)

func _on_remote_disconnected() -> void:
	if remote_player != null:
		remote_player.queue_free()
		remote_player = null
	waiting_label.visible = true
