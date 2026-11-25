/* Dope UDID gateway — Cloudflare Worker.
 *
 * GET  /udid/web?l=es&t=<token>   -> signed-style MDM mobileconfig with check-in URL
 * PUT  /mdm/checkin?t=<token>    -> receives the iPhone UDID, stores it in KV
 * GET  /api/udid?t=<token>       -> website polls the captured UDID
 * POST /api/key {t:<token>}      -> issues an X-style key bound to that UDID
 * GET  /api/key?t=<token>        -> returns the active key for that UDID
 *
 * Key format is identical to LicenseGate.swift:
 *   X-YYYYMMDD-PAYLOAD-CHECK
 *   CHECK = SHA256("zada-license-v1|YYYYMMDD|PAYLOAD")[:4].toUpperCase()
 */

const SALT = "zada-license-v1";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" }
  });
}

function xml(body, contentType = "text/xml") {
  return new Response(body, {
    headers: { ...CORS, "Content-Type": contentType }
  });
}

function randomToken(bytes = 16) {
  const a = crypto.getRandomValues(new Uint8Array(bytes));
  return Array.from(a).map(b => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, "0")).join("");
}

function yyyymmdd(date) {
  return date.toISOString().slice(0, 10).replace(/-/g, "");
}

async function makeKey(days) {
  const expiry = new Date(Date.now() + days * 86400000);
  const date = yyyymmdd(expiry);
  const payload = randomToken(8);
  const check = (await sha256(`${SALT}|${date}|${payload}`)).slice(0, 4).toUpperCase();
  return { key: `X-${date}-${payload}-${check}`, expiry: expiry.toISOString() };
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;"
  }[c]));
}

function mobileconfig(topic, serverURL, rootUUID, mdmUUID, clipUUID) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadContent</key>
      <dict>
        <key>ServerURL</key>
        <string>${esc(serverURL)}</string>
        <key>Topic</key>
        <string>${esc(topic)}</string>
        <key>PushMagic</key>
        <string>${esc(randomToken(16))}</string>
        <key>CheckInURL</key>
        <string>${esc(serverURL)}</string>
      </dict>
      <key>PayloadDescription</key>
      <string>Regjistron këtë iPhone te Dope.</string>
      <key>PayloadDisplayName</key>
      <string>Dope MDM</string>
      <key>PayloadIdentifier</key>
      <string>com.zada.dope.mdm.${mdmUUID}</string>
      <key>PayloadType</key>
      <string>com.apple.mdm</string>
      <key>PayloadUUID</key>
      <string>${mdmUUID}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    <dict>
      <key>PayloadContent</key>
      <dict>
        <key>URL</key>
        <string>https://kanekikkenn242.github.io/discord/</string>
        <key>Label</key>
        <string>Dope</string>
        <key>Precomposed</key>
        <false/>
      </dict>
      <key>PayloadDescription</key>
      <string>Shkurtesë për Dope.</string>
      <key>PayloadDisplayName</key>
      <string>Dope Web Clip</string>
      <key>PayloadIdentifier</key>
      <string>com.zada.dope.webclip.${clipUUID}</string>
      <key>PayloadType</key>
      <string>com.apple.webClip.managed</string>
      <key>PayloadUUID</key>
      <string>${clipUUID}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDescription</key>
  <string>Profili i instalimit Dope.</string>
  <key>PayloadDisplayName</key>
  <string>Dope iOS</string>
  <key>PayloadIdentifier</key>
  <string>com.zada.dope.install.${rootUUID}</string>
  <key>PayloadOrganization</key>
  <string>Dope</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>${rootUUID}</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
`;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    // 1) Profile generation: /udid/web?l=es&t=<token>
    if (path === "/udid/web") {
      const token = url.searchParams.get("t") || randomToken(12);
      const serverURL = `${url.origin}/mdm/checkin?t=${encodeURIComponent(token)}`;
      const topic = `com.apple.mgmt.dope.${token}`;
      const body = mobileconfig(topic, serverURL, randomToken(16), randomToken(16), randomToken(16));
      await env.DOPE.put(`token:${token}`, "pending");
      return new Response(body, {
        headers: {
          ...CORS,
          "Content-Type": "application/x-apple-aspen-config",
          "Content-Disposition": 'attachment; filename="Dope.mobileconfig"'
        }
      });
    }

    // 2) MDM check-in: iPhone sends its UDID here.
    if (path === "/mdm/checkin" && request.method === "PUT") {
      const token = url.searchParams.get("t") || "";
      const text = await request.text();
      const match = text.match(/<key>UDID<\/key>\s*<string>([^<]+)<\/string>/i);
      const udid = match ? match[1].trim() : "";
      if (token && udid) {
        await env.DOPE.put(`udid:${token}`, udid);
        await env.DOPE.put(`token:${token}`, "registered");
      }
      // MDM clients expect a plist response.
      return xml(`<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict></dict></plist>`);
    }

    // 3) Website polls for the registered UDID.
    if (path === "/api/udid") {
      const token = url.searchParams.get("t") || "";
      const udid = await env.DOPE.get(`udid:${token}`);
      const state = await env.DOPE.get(`token:${token}`);
      return json({ token, udid: udid || null, state: state || "unknown" });
    }

    // 4) Issue a key bound to the captured UDID.
    if (path === "/api/key" && request.method === "POST") {
      let body = {};
      try { body = await request.json(); } catch (e) {}
      const token = body.t || url.searchParams.get("t") || "";
      const udid = await env.DOPE.get(`udid:${token}`);
      if (!udid) return json({ error: "UDID belum terdaftar / iPhone belum install profil" }, 400);

      const existing = await env.DOPE.get(`key:${udid}`);
      if (existing) {
        const parsed = JSON.parse(existing);
        if (new Date(parsed.expiry) > new Date()) return json(parsed);
      }
      const issued = await makeKey(1);
      const result = { ...issued, udid: udid.slice(0, 4) + "…" + udid.slice(-4) };
      await env.DOPE.put(`key:${udid}`, JSON.stringify(result));
      await env.DOPE.put(`keytoken:${token}`, JSON.stringify(result));
      return json(result);
    }

    // 5) Return active key for a token (website/app status).
    if (path === "/api/key") {
      const token = url.searchParams.get("t") || "";
      const raw = await env.DOPE.get(`keytoken:${token}`);
      return json(raw ? JSON.parse(raw) : { key: null });
    }

    return json({ service: "Dope UDID gateway" });
  }
};
