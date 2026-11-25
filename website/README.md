# Project X — distribution portal (local reconstruction)

Static recreation of the `xkeyapi.onrender.com` distribution page. No backend is
required: everything runs in the browser and persists in `localStorage`.

## What is here

- **Hero / Descargas** — version, build, certificate and the signed IPA link.
- **Firma** — ESign / KSign / Scarlet / GBox installation links.
- **Key Free 24h** — generates a key bound to this browser/device, one per 24 h.
- **Mi perfil** — name, key status, activation, expiry and device ID; revoke.

## Key format (matches the app)

Both this site and `Discord/Discord/engine/LicenseGate.swift` use the same key:

```
X-YYYYMMDD-PAYLOAD-CHECK
```

- `YYYYMMDD` — expiry date in UTC.
- `PAYLOAD` — 8 uppercase alphanumeric characters.
- `CHECK` — first 4 hex characters (uppercase) of
  `SHA256("zada-license-v1|YYYYMMDD|PAYLOAD")`.

The app also accepts legacy keys (`XXXX-XXXX-…`) for existing users.

## Hosting

Copy this folder to any static host (GitHub Pages, Cloudflare Pages, Netlify),
or serve locally:

```bash
cd website
python -m http.server 8000
```

Then open `http://localhost:8000`.

## Note

The IPA link and signing manifests point to the original public distribution.
The license state is local to the browser; it is not a real online licence API.
