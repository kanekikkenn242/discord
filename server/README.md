# Dope UDID gateway

Server-side part of the X-style install profile. It generates an MDM profile with
a check-in URL, receives the iPhone UDID and binds the issued key to that UDID.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/udid/web?l=es&t=<token>` | returns the generated `.mobileconfig` |
| PUT | `/mdm/checkin?t=<token>` | iOS sends the UDID here |
| GET | `/api/udid?t=<token>` | website polls the registered UDID |
| POST | `/api/key` `{t}` | issues one 24h key bound to that UDID |
| GET | `/api/key?t=<token>` | returns the active key |

The key format matches `Discord/Discord/engine/LicenseGate.swift` exactly.

## Deploy (Cloudflare Workers)

```bash
cd server
npm install -g wrangler
wrangler login
wrangler kv namespace create DOPE     # paste the id into wrangler.toml
wrangler deploy
```

The worker URL becomes `https://dope-udid.<your-subdomain>.workers.dev`.

Then set that URL in `docs/config.js`:

```js
window.DOPE_API = "https://dope-udid.<your-subdomain>.workers.dev";
```

The site automatically switches from local-only keys to server-bound keys once
`DOPE_API` is set. The app's Profile → Install profile button must also be
pointed at the deployed `/udid/web` URL (see `ProfileView.swift`).

## Why a server is required

GitHub Pages is static: it can serve the `.mobileconfig`, but it cannot receive
the MDM check-in that carries the UDID. That is exactly what X does on
`xkeyapi.onrender.com`. This worker replaces that backend with your own.
