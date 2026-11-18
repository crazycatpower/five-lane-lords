import http from "node:http";
import crypto from "node:crypto";

const PORT = Number(process.env.PORT || 24680);
const ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const clients = new Map(); // socket -> { id, version, lord, deck, name, buffer, closed, partner, roomCode }
const queue = []; // waiting sockets in FIFO order
const rooms = new Map(); // code -> hostSocket
let nextId = 1;

function encodeFrame(text) {
  const payload = Buffer.from(text, "utf8");
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x81;
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}

function encodeControl(opcode, payload = Buffer.alloc(0)) {
  const header = Buffer.alloc(2);
  header[0] = 0x80 | (opcode & 0x0f);
  header[1] = Math.min(125, payload.length);
  return Buffer.concat([header, payload.subarray(0, 125)]);
}

function sendJson(socket, obj) {
  const c = clients.get(socket);
  if (!c || c.closed || socket.destroyed) return;
  try {
    socket.write(encodeFrame(JSON.stringify(obj)));
  } catch {
    cleanupSocket(socket);
  }
}

function removeFromQueue(socket) {
  const idx = queue.indexOf(socket);
  if (idx !== -1) queue.splice(idx, 1);
}

function removeOwnedRoom(socket) {
  const c = clients.get(socket);
  if (c && c.roomCode && rooms.get(c.roomCode) === socket) {
    rooms.delete(c.roomCode);
    c.roomCode = "";
  }
}

function broadcastStats() {
  const msg = { t: "stats", online: clients.size, queued: queue.length };
  for (const s of clients.keys()) sendJson(s, msg);
}

function generateRoomCode() {
  for (let attempt = 0; attempt < 64; attempt++) {
    let code = "";
    for (let i = 0; i < 4; i++) {
      code += ROOM_ALPHABET[crypto.randomInt(0, ROOM_ALPHABET.length)];
    }
    if (!rooms.has(code)) return code;
  }
  return String(Date.now()).slice(-4);
}

function startPair(s0, s1) {
  const c0 = clients.get(s0);
  const c1 = clients.get(s1);
  if (!c0 || !c1 || c0.closed || c1.closed) return;
  removeFromQueue(s0);
  removeFromQueue(s1);
  removeOwnedRoom(s0);
  removeOwnedRoom(s1);
  c0.partner = s1;
  c1.partner = s0;
  const seed = crypto.randomInt(1, 2000000000);
  const decks = [c0.deck, c1.deck];
  const lords = [c0.lord, c1.lord];
  const names = [c0.name || "紅方領主", c1.name || "藍方領主"];
  sendJson(s0, { t: "matched", team: 0, seed, decks, lords, names });
  sendJson(s1, { t: "matched", team: 1, seed, decks, lords, names });
  broadcastStats();
}

function handleMessage(socket, rawText) {
  let msg;
  try {
    msg = JSON.parse(rawText);
  } catch {
    return;
  }
  if (!msg || typeof msg !== "object") return;
  const c = clients.get(socket);
  if (!c) return;

  switch (msg.t) {
    case "ping":
      sendJson(socket, { t: "stats", online: clients.size, queued: queue.length });
      break;
    case "queue": {
      if (c.partner) break;
      removeFromQueue(socket);
      removeOwnedRoom(socket);
      c.version = String(msg.version || "");
      c.lord = String(msg.lord || "lion");
      c.deck = Array.isArray(msg.deck) ? msg.deck : [];
      c.name = String(msg.name || "");
      const matchIdx = queue.findIndex((other) => {
        const oc = clients.get(other);
        return oc && !oc.closed && other !== socket && oc.version === c.version;
      });
      if (matchIdx !== -1) {
        const peer = queue.splice(matchIdx, 1)[0];
        startPair(peer, socket);
      } else {
        queue.push(socket);
        sendJson(socket, { t: "queued", online: clients.size, queued: queue.length });
        broadcastStats();
      }
      break;
    }
    case "cancel":
      removeFromQueue(socket);
      removeOwnedRoom(socket);
      broadcastStats();
      break;
    case "create_room": {
      if (c.partner) break;
      removeFromQueue(socket);
      removeOwnedRoom(socket);
      c.version = String(msg.version || "");
      c.lord = String(msg.lord || "lion");
      c.deck = Array.isArray(msg.deck) ? msg.deck : [];
      c.name = String(msg.name || "");
      const code = generateRoomCode();
      c.roomCode = code;
      rooms.set(code, socket);
      sendJson(socket, { t: "room_created", code, online: clients.size });
      break;
    }
    case "join_room": {
      if (c.partner) break;
      removeFromQueue(socket);
      removeOwnedRoom(socket);
      const code = String(msg.code || "").trim().toUpperCase();
      const host = rooms.get(code);
      if (!host || !clients.has(host) || host === socket) {
        sendJson(socket, { t: "error", msg: "找不到房間代碼：" + code });
        break;
      }
      const hc = clients.get(host);
      c.version = String(msg.version || "");
      c.lord = String(msg.lord || "lion");
      c.deck = Array.isArray(msg.deck) ? msg.deck : [];
      c.name = String(msg.name || "");
      if (hc.version !== c.version) {
        sendJson(socket, { t: "error", msg: "雙方遊戲版本不同，請更新到同一版" });
        break;
      }
      rooms.delete(code);
      hc.roomCode = "";
      startPair(host, socket);
      break;
    }
    case "f":
    case "h": {
      if (c.partner && clients.has(c.partner)) {
        const pc = clients.get(c.partner);
        if (!pc.closed && !c.partner.destroyed) {
          try {
            c.partner.write(encodeFrame(rawText));
          } catch {
            cleanupSocket(c.partner);
          }
        }
      }
      break;
    }
    default:
      break;
  }
}

function pumpFrames(socket) {
  const c = clients.get(socket);
  if (!c) return;
  while (c.buffer.length >= 2) {
    const b0 = c.buffer[0];
    const b1 = c.buffer[1];
    const opcode = b0 & 0x0f;
    const masked = (b1 & 0x80) !== 0;
    let payloadLen = b1 & 0x7f;
    let offset = 2;
    if (payloadLen === 126) {
      if (c.buffer.length < 4) return;
      payloadLen = c.buffer.readUInt16BE(2);
      offset = 4;
    } else if (payloadLen === 127) {
      if (c.buffer.length < 10) return;
      const bigLen = c.buffer.readBigUInt64BE(2);
      if (bigLen > 1048576n) {
        socket.destroy();
        return;
      }
      payloadLen = Number(bigLen);
      offset = 10;
    }
    const maskBytes = masked ? 4 : 0;
    if (c.buffer.length < offset + maskBytes + payloadLen) return;
    const mask = masked ? c.buffer.subarray(offset, offset + 4) : null;
    const dataStart = offset + maskBytes;
    const payload = Buffer.from(c.buffer.subarray(dataStart, dataStart + payloadLen));
    c.buffer = c.buffer.subarray(dataStart + payloadLen);

    if (masked && mask) {
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
    }

    if (opcode === 0x8) {
      try { socket.end(encodeControl(0x8)); } catch {}
      cleanupSocket(socket);
      return;
    } else if (opcode === 0x9) {
      try { socket.write(encodeControl(0xA, payload)); } catch {}
    } else if (opcode === 0x1 || opcode === 0x2) {
      handleMessage(socket, payload.toString("utf8"));
    }
  }
}

function cleanupSocket(socket) {
  const c = clients.get(socket);
  if (!c) return;
  c.closed = true;
  removeFromQueue(socket);
  removeOwnedRoom(socket);
  if (c.partner && clients.has(c.partner)) {
    const pc = clients.get(c.partner);
    pc.partner = null;
    sendJson(c.partner, { t: "peer_left" });
  }
  c.partner = null;
  clients.delete(socket);
  broadcastStats();
}

const server = http.createServer((req, res) => {
  res.writeHead(200, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
  });
  res.end(
    JSON.stringify({
      ok: true,
      online: clients.size,
      queued: queue.length,
      rooms: rooms.size,
    })
  );
});

server.on("upgrade", (req, socket) => {
  const key = req.headers["sec-websocket-key"];
  if (!key) {
    socket.destroy();
    return;
  }
  const accept = crypto
    .createHash("sha1")
    .update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    .digest("base64");
  socket.write(
    [
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${accept}`,
      "\r\n",
    ].join("\r\n")
  );
  clients.set(socket, {
    id: nextId++,
    version: "",
    lord: "lion",
    deck: [],
    name: "",
    buffer: Buffer.alloc(0),
    closed: false,
    partner: null,
    roomCode: "",
  });
  sendJson(socket, { t: "stats", online: clients.size, queued: queue.length });

  socket.on("data", (chunk) => {
    const c = clients.get(socket);
    if (!c) return;
    c.buffer = Buffer.concat([c.buffer, chunk]);
    pumpFrames(socket);
  });
  socket.on("close", () => cleanupSocket(socket));
  socket.on("error", () => cleanupSocket(socket));
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Five Lane Lords Matchmaker listening on :${PORT}`);
});
