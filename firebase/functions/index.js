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

  const STALE_MS = 30000;
  const now = Date.now();

  // Find a waiting room that is not stale and doesn't already have this player
  const snapshot = await roomsRef
    .orderByChild("status")
    .equalTo("waiting")
    .limitToFirst(10)
    .get();

  let joinRoomId = null;

  if (snapshot.exists()) {
    for (const [key, room] of Object.entries(snapshot.val())) {
      const players = room.players || {};
      const uids = Object.keys(players);
      const isStale = uids.length === 0 ||
        uids.every(p => (now - (players[p].last_seen || 0)) > STALE_MS);
      if (isStale) continue;
      if (players[uid]) continue; // already in this room
      joinRoomId = key;
      break;
    }
  }

  if (joinRoomId) {
    // Join the existing waiting room
    await roomsRef.child(`${joinRoomId}/players/${uid}`).set({
      x: 160, y: 120, last_seen: now,
    });
    await roomsRef.child(`${joinRoomId}/status`).set("full");
    return { room_id: joinRoomId };
  }

  // No suitable room found — create a new waiting room
  const newRoom = roomsRef.push();
  const newRoomId = newRoom.key;
  await newRoom.set({
    status: "waiting",
    players: { [uid]: { x: 64, y: 64, last_seen: now } },
  });
  return { room_id: newRoomId };
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
