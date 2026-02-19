extends Node

var room_id: String = ""

signal room_joined(room_id: String)
signal room_left

func join() -> void:
	Firebase.call_function("joinRoom", {}, func(data: Variant) -> void:
		print("Matchmaking: joinRoom raw response = ", JSON.stringify(data))
		if data == null or not data.has("result"):
			push_error("Matchmaking: joinRoom failed — " + JSON.stringify(data))
			return
		room_id = data["result"]["room_id"]
		print("Matchmaking: room_id = '", room_id, "'  Auth.uid = '", Auth.uid, "'")
		if room_id == "":
			push_error("Matchmaking: got empty room_id")
			return
		emit_signal("room_joined", room_id)
	)

func leave() -> void:
	if room_id == "":
		emit_signal("room_left")
		return
	Firebase.call_function("leaveRoom", {"room_id": room_id}, func(_data: Variant) -> void:
		room_id = ""
		emit_signal("room_left")
	)
