import { DurableObject } from "cloudflare:workers";

const encoder = new TextEncoder();
const burst = 8 * 1024 * 1024;

// prefix joins a wire protocol label and a byte string without re-encoding it.
function prefix(label, bytes) {
  const tag = encoder.encode(label);
  const result = new Uint8Array(tag.length + bytes.length);
  result.set(tag);
  result.set(bytes, tag.length);
  return result;
}

async function proves(id, challenge, answer) {
  if (answer.byteLength !== 96) return false;
  const pub = new Uint8Array(answer, 0, 32);
  const digest = await crypto.subtle.digest("SHA-256", prefix("nushi-relay/1 id\0", pub));
  const name = btoa(String.fromCharCode(...new Uint8Array(digest))).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  if (name !== id) return false;
  const key = await crypto.subtle.importKey("raw", pub, "Ed25519", false, ["verify"]);
  return crypto.subtle.verify("Ed25519", key, new Uint8Array(answer, 32), prefix("nushi-relay/1 listen\0" + id + "\0", challenge));
}

// Each room owns the sockets for one rendezvous ID. Only short handshakes
// keep a timer and buffers in memory. Waiting and paired sockets hibernate.
export class Room extends DurableObject {
  pending = new Map();

  fetch(request) {
    const [, , side, id] = new URL(request.url).pathname.split("/");
    const limit = side === "dial" ? 16 : 32;
    if (this.ctx.getWebSockets(side).length >= limit) return new Response("busy", { status: 503 });

    const [client, ws] = Object.values(new WebSocketPair());
    const tag = crypto.randomUUID();
    this.ctx.acceptWebSocket(ws, [side, tag]);
    ws.serializeAttachment({ tag, phase: side, tokens: burst, last: Date.now() });
    this.wait(ws, side === "listen" ? 4403 : 4404);
    if (side === "listen") {
      const challenge = crypto.getRandomValues(new Uint8Array(32));
      Object.assign(this.pending.get(ws), { id, challenge });
      ws.send(prefix("nushi-relay/1 challenge\0", challenge));
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  wait(ws, code) {
    this.forget(ws);
    const timer = setTimeout(() => this.end(ws, code), 10_000);
    this.pending.set(ws, { timer });
  }

  forget(ws) {
    clearTimeout(this.pending.get(ws)?.timer);
    this.pending.delete(ws);
  }

  waiting() {
    return this.ctx.getWebSockets("listen").find(ws =>
      ws.readyState === WebSocket.OPEN && ws.deserializeAttachment().phase === "waiting");
  }

  pair(listener, dialer, first) {
    this.forget(dialer);
    const l = listener.deserializeAttachment();
    const d = dialer.deserializeAttachment();
    listener.serializeAttachment({ ...l, phase: "paired", other: d.tag });
    dialer.serializeAttachment({ ...d, phase: "paired", other: l.tag });
    listener.send(first);
  }

  async webSocketMessage(ws, message) {
    try {
      const s = ws.deserializeAttachment();
      if (!(message instanceof ArrayBuffer) || message.byteLength > 65535) return this.end(ws, 4400);
      const now = Date.now();
      s.tokens = Math.min(burst, s.tokens + (now - s.last) * 1048576 / 1000) - Math.max(512, message.byteLength);
      if (s.tokens < 0) return this.end(ws, 4429);
      s.last = now;
      ws.serializeAttachment(s);
      if (s.phase === "paired") {
        const [peer] = this.ctx.getWebSockets(s.other);
        if (!peer || peer.readyState !== WebSocket.OPEN) return this.end(ws);
        peer.send(message);
        return;
      }
      const p = this.pending.get(ws);
      if (s.phase === "listen" && p?.challenge) {
        ws.serializeAttachment({ ...s, phase: "verifying" });
        const valid = await proves(p.id, p.challenge, message);
        if (!valid || this.pending.get(ws) !== p) return this.end(ws, 4403);
        this.forget(ws);
        const previous = this.waiting();
        if (previous) this.end(previous);
        const until = Date.now() + 3600_000;
        ws.serializeAttachment({ ...s, phase: "waiting", until });
        this.ctx.waitUntil(this.ctx.storage.setAlarm(until));
        ws.send(new ArrayBuffer(0));
        for (const [dialer, pending] of this.pending) {
          if (pending.first && dialer.readyState === WebSocket.OPEN) {
            this.pair(ws, dialer, pending.first);
            break;
          }
        }
        return;
      }
      if (s.phase === "dial" && p && !p.first) {
        const listener = this.waiting();
        if (listener) return this.pair(listener, ws, message);
        this.wait(ws, 4404);
        this.pending.get(ws).first = message;
        return;
      }
      this.end(ws, 4400);
    } catch {
      this.end(ws, 4400);
    }
  }

  async alarm() {
    const ws = this.waiting();
    if (!ws) return;
    const { until } = ws.deserializeAttachment();
    if (Date.now() >= until) this.end(ws);
    else await this.ctx.storage.setAlarm(until);
  }

  end(ws, code = 1000) {
    this.forget(ws);
    const s = ws.deserializeAttachment();
    ws.serializeAttachment({ phase: "closed" });
    if (s.other) {
      const [peer] = this.ctx.getWebSockets(s.other);
      if (peer) {
        peer.serializeAttachment({ phase: "closed" });
        peer.close(code);
      }
    }
    ws.close(code);
  }

  webSocketClose(ws) { this.end(ws); }
  webSocketError(ws) { this.end(ws); }
}
