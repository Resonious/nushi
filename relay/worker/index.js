export { Room } from "./room.js";

const socketPath = /^\/v1\/(listen|dial)\/[A-Za-z0-9_-]{16,128}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.protocol === "http:" && !["localhost", "127.0.0.1"].includes(url.hostname)) {
      url.protocol = "https:";
      return Response.redirect(url, 308);
    }
    if (!["GET", "HEAD"].includes(request.method)) {
      return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    if (url.pathname === "/healthz") return new Response("ok\n");
    if (url.pathname.startsWith("/v1/")) {
      if (!socketPath.test(url.pathname)) return new Response(null, { status: 404 });
      const origin = request.headers.get("Origin");
      if (origin !== null && origin !== url.origin) return new Response(null, { status: 403 });
      if (request.method !== "GET" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return new Response(null, { status: 426 });
      }
      const address = request.headers.get("CF-Connecting-IP") ?? "local";
      // Cloudflare supplies the normalized client address. Count IPv6 by
      // /48 so a client cannot reset its quota by rotating interface IDs.
      const key = address.includes(":")
        ? address.split("::")[0].split(":").concat("0", "0", "0").slice(0, 3).map(x => x || "0").join(":")
        : address;
      if (!(await env.UPGRADES.limit({ key })).success) {
        return new Response("busy", { status: 429 });
      }
      const id = url.pathname.split("/")[3];
      return env.ROOMS.getByName(id).fetch(request);
    }
    return phone(request, url, env.PHONE);
  },
};

// The same page, preview sandbox and cache policies as relay/web.go.
async function phone(request, url, assets) {
  if (url.pathname === "/") url.pathname = "/index.html";
  // Only canonical asset paths receive the headers selected for that file.
  if (/%|\\|\/\.|\.br$|\/\//.test(url.pathname)) return new Response(null, { status: 404 });
  const asset = await assets.fetch(new Request(url, request));
  const response = new Response(asset.body, asset);
  const h = response.headers;
  const frame = url.pathname === "/frame.html";
  const ws = url.origin.replace(/^http/, "ws");
  const csp = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; " +
    "img-src 'self' blob:; font-src 'self'; connect-src 'self' blob: " + ws + "; " +
    "frame-src 'self'; worker-src 'self'; manifest-src 'self'; object-src 'none'; base-uri 'self'; " +
    "form-action 'none'; frame-ancestors 'none'; require-trusted-types-for 'script'; trusted-types flutter-js flutter-engine nushi";
  h.set("Content-Security-Policy", frame ? "sandbox allow-scripts; default-src * data: blob: 'unsafe-inline' 'unsafe-eval'; frame-ancestors 'self'" : csp);
  h.set("X-Frame-Options", frame ? "SAMEORIGIN" : "DENY");
  h.set("Permissions-Policy", "camera=" + (frame ? "()" : "(self)") + ", microphone=(), geolocation=(), payment=(), usb=()");
  h.set("Referrer-Policy", "no-referrer");
  h.set("X-Content-Type-Options", "nosniff");
  h.set("Cross-Origin-Opener-Policy", "same-origin");
  h.set("Cross-Origin-Resource-Policy", url.pathname === "/assets/assets/mermaid/mermaid.min.js" ? "cross-origin" : "same-origin");
  h.set("Strict-Transport-Security", "max-age=31536000");
  h.delete("Access-Control-Allow-Origin");
  const immutable = /[.-][0-9a-f]{16,}[./]/.test(url.pathname) || /^\/assets\/fonts\/fallback\/.+\.woff2$/.test(url.pathname);
  const cache = asset.ok && immutable ? "public, max-age=31536000, immutable" : "no-store";
  h.set("Cache-Control", cache + ", no-transform");
  return response;
}
