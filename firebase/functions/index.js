const { onCall } = require("firebase-functions/v2/https");
const { getDatabase } = require("firebase-admin/database");
const { initializeApp } = require("firebase-admin/app");

initializeApp();

exports.joinRoom = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("unauthenticated");
  }
  const uid = request.auth.uid;
  const db = getDatabase();
  const roomsRef = db.ref("rooms");

  const snapshot = await roomsRef
    .orderByChild("status")
    .equalTo("waiting")
    .limitToFirst(1)
    .get();

  let roomId;
  if (snapshot.exists()) {
    snapshot.forEach((child) => {
      roomId = child.key;
    });
    await roomsRef.child(`${roomId}/players/${uid}`).set({
      x: 160,
      y: 120,
      last_seen: Date.now(),
    });
    await roomsRef.child(`${roomId}/status`).set("full");
  } else {
    const newRoom = roomsRef.push();
    roomId = newRoom.key;
    await newRoom.set({
      status: "waiting",
      players: {
        [uid]: { x: 64, y: 64, last_seen: Date.now() },
      },
    });
  }

  return { room_id: roomId };
});

exports.leaveRoom = onCall(async (request) => {
  if (!request.auth) {
    throw new Error("unauthenticated");
  }
  const uid = request.auth.uid;
  const { room_id } = request.data;

  if (!room_id) {
    throw new Error("room_id is required");
  }

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
