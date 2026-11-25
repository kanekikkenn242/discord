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

Currently deployed at:

```text
https://dope-udid-zada-2026.dope-udid-zada.workers.dev
```

Account: `d0c2f350b62e547a739b440b238b8b25` (set `CLOUDFLARE_ACCOUNT_ID` before
running wrangler, otherwise KV creation fails with error 10000). KV namespace id:
`b44d0cde3fae4ef5842204a67397bccd`.

That URL is already set in `docs/config.js`.

The site automatically switches from local-only keys to server-bound keys once
`DOPE_API` is set. The app's Profile → Install profile button must also be
pointed at the deployed `/udid/web` URL (see `ProfileView.swift`).

## Why a server is required

GitHub Pages is static: it can serve the `.mobileconfig`, but it cannot receive
the MDM check-in that carries the UDID. That is exactly what X does on
`xkeyapi.onrender.com`. This worker replaces that backend with your own.
