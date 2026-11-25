# Dope — distribution portal (local reconstruction)

Static recreation of the `xkeyapi.onrender.com` distribution page, rebranded to
**Dope** with the original dark/monochrome `lp-*` design. No backend is required:
everything runs in the browser and persists in `localStorage`.

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

## Making it public

The repo is public, so GitHub Pages is the fastest route:

1. **One manual step first:** GitHub → repository **Settings → Pages → Build and
   deployment → Source: GitHub Actions**. Until this is set once, the deploy job
   fails with `Get Pages site failed ... Not Found` even with `enablement: true`.
2. Push any change under `website/`. `.github/workflows/deploy-site.yml` uploads
   the folder and deploys it automatically.
3. The site becomes `https://<username>.github.io/discord/`.

Any other static host works too (Cloudflare Pages, Netlify): set the build
command to none and the output directory to `website`.

Locally:

```bash
cd website
python -m http.server 8000
```

Then open `http://localhost:8000`.

## Issuing a key for someone else

Use the admin script (works on any machine with Python 3):

```bash
python tools/make_key.py 7          # key valid for 7 days
python tools/make_key.py 30 --count 5
python tools/make_key.py --check X-20261202-A70GQF34-DC91
```

Send the resulting `X-…` string to the other person. They paste it into the
app. The app binds it to the first iPhone that activates it; another iPhone
gets `revoked`. The website's "Generar key" button does the same thing but
limits it to one key per 24 hours per browser.

## Note

The IPA link and signing manifests point to the original public distribution.
The license state is local to the browser; it is not a real online licence API.
