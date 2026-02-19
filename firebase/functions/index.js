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

  // Find a waiting room
  const snapshot = await roomsRef
    .orderByChild("status")
    .equalTo("waiting")
    .limitToFirst(10)
    .get();

  let roomId = null;
  const STALE_MS = 30000;
  const now = Date.now();

  if (snapshot.exists()) {
    // Find a non-stale waiting room and try to claim it atomically
    for (const child of Object.values(snapshot.val())) {
      // skip stale rooms (host disconnected)
      const players = child.players || {};
      const playerUids = Object.keys(players);
      const isStale = playerUids.length === 0 ||
        playerUids.every(p => (now - (players[p].last_seen || 0)) > STALE_MS);
      if (isStale) continue;
      // skip if this player is already in this room
      if (players[uid]) continue;
      roomId = Object.keys(snapshot.val()).find(k => snapshot.val()[k] === child);
      break;
    }

    if (roomId) {
      const roomRef = roomsRef.child(roomId);
      const result = await roomRef.transaction((room) => {
        if (room === null) return room;
        if (room.status !== "waiting") return; // abort — already taken
        if (room.players && room.players[uid]) return; // already in this room
        room.status = "full";
        if (!room.players) room.players = {};
        room.players[uid] = { x: 160, y: 120, last_seen: Date.now() };
        return room;
      });
      if (!result.committed) roomId = null;
    }
  }

  if (roomId === null) {
    // Create a new waiting room
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
