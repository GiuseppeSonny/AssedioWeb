extends CanvasLayer

@onready var find_match_btn: Button = $FindMatchBtn
@onready var waiting_label: Label = $WaitingLabel
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	find_match_btn.disabled = true
	waiting_label.visible = false
	status_label.text = "Signing in..."

	Auth.signed_in.connect(_on_signed_in)
	Matchmaking.room_joined.connect(_on_room_joined)
	Auth.sign_in_anonymous()

	get_tree().set_auto_accept_quit(false)

func _on_signed_in() -> void:
	find_match_btn.disabled = false
	status_label.text = "Ready"

func _on_find_match_btn_pressed() -> void:
	find_match_btn.disabled = true
	waiting_label.visible = true
	status_label.text = ""
	Matchmaking.join()

func _on_room_joined(_room_id: String) -> void:
	get_tree().change_scene_to_file("res://scenes/Room.tscn")

# --- T17: Disconnect handling ---

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_gracefully()

func _quit_gracefully() -> void:
	if Matchmaking.room_id != "":
		Matchmaking.leave()
		await Matchmaking.room_left
	get_tree().quit()
