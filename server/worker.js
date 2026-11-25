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
const IDENTITY_UUID = "A1B2C3D4E5F60718293A4B5C6D7E8F90";
const IDENTITY_P12 = `\n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
tY7kBAjZC8XZcOPnZwICCAA=\n`;
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

function randomBase64(bytes = 16) {
  const a = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...a));
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
  <key>ConsentText</key>
  <dict>
    <key>default</key>
    <string>Dope — regjistron këtë iPhone dhe lidh çelësin me UDID-in e tij.</string>
  </dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadCertificateFileName</key>
      <string>dope-identity.p12</string>
      <key>PayloadContent</key>
      <data>${IDENTITY_P12}</data>
      <key>Password</key>
      <string>dope1234</string>
      <key>PayloadDescription</key>
      <string>Identiteti Dope per MDM.</string>
      <key>PayloadDisplayName</key>
      <string>Dope Identity</string>
      <key>PayloadIdentifier</key>
      <string>com.zada.dope.identity.${IDENTITY_UUID}</string>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>${IDENTITY_UUID}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    <dict>
      <key>PayloadContent</key>
      <dict>
        <key>IdentityCertificateUUID</key>
        <string>${IDENTITY_UUID}</string>
        <key>ServerURL</key>
        <string>${esc(serverURL)}</string>
        <key>URL</key>
        <string>${esc(serverURL)}</string>
        <key>Topic</key>
        <string>${esc(topic)}</string>
        <key>PushMagic</key>
        <string>${esc(randomToken(16))}</string>
        <key>UnlockToken</key>
        <data>${randomBase64(16)}</data>
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
      <key>URL</key>
      <string>https://kanekikkenn242.github.io/discord/</string>
      <key>Label</key>
      <string>Dope</string>
      <key>Precomposed</key>
      <false/>
      <key>FullScreen</key>
      <false/>
      <key>IsRemovable</key>
      <true/>
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
          "Content-Disposition": 'attachment; filename="Dope.mobileconfig"',
          "Cache-Control": "no-store, must-revalidate"
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
