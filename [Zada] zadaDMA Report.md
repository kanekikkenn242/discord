# [Zada] zadaDMA — X 5.2.0 / Proxy 3.0 / 3105 full teardown

> Static analysis only. No device execution.
> Artifacts: `X-v5.2.0-b124.ipa`, `Proxy 3.0.ipa`, `3105/` source snapshot, six bundled `.3105` packages, `ff-offsets.json`, `ff-dump.md`, and the 12 supplied UI screenshots (X 0.2.0 build, iPhone15,7 / iOS 27.0.1).
> Date: 2026-11-19.

---

## 0. Bottom line

`zadaDMA` is the Free Fire-focused fork of **3105**, packaged under the X identity. It is **not** a memory cheat and does **not** inject code into Free Fire. It is a **file replacer with a sandbox-access stack**:

1. Decrypt and validate a `.3105` package (AES-256-GCM, PBKDF2-HMAC-SHA256, 120,000 iterations).
2. Resolve the Free Fire data container.
3. Write the package's replacement bytes over Unity asset files (`assetindexer.tdn`, `cache_res.<hash>.gz`, plus the `.raw.tmp` siblings).
4. Keep an exact byte backup of every original so a toggle-off restores the pre-patch state.

Access to the container has two backends:

| iOS | Backend | Mechanism |
|---|---|---|
| 17.0–18.7.1 | `kexploit_opa334` (`kfd`) + container query | Kernel base via weak `kfd_init()`, then MCM/`container_query` lease |
| 26.x–27.x | Developer Mode + Remote Pairing + LocalDevVPN | On-device pairable-host, RPPairing file, pair-verify, TLS-PSK, RSD, House Arrest, AFC |

The current tree has a hard cut-over: `escape_sandbox_bad_query()` no longer runs the raw `container_query` sequence (it crashed iOS 27 by passing a C string where an XPC object was expected). It now routes through `ContainerAccess`, the guarded MCM lease. On iOS 27, `MotorBridge.bootstrap` reports failure and the patch path goes MCM → Airlift.

The gameplay effect is **on-disk asset modification**, not runtime memory writing:

- Avatar packages enlarge the **Head, Spine1 and Neck** bone-local scales on both male and female rigs (up to 10× head).
- `aimneck_90` changes two serialized floats from `1.0` to `211.0`.
- Cache packages enlarge the **male and female head capsules**, disable the **larger female `bone_LeftHand` capsule**, and convert six torso hit helpers from `ColliderType 2` to `1`.

`ff-offsets.json` is a **separate IL2CPP memory map**. None of the six bundled packages use it. It is not version-stamped (`"version": "importado"`, `"updated_at": null`) and must not be treated as verified for a current Free Fire build.

`Proxy 3.0.ipa` is **not recoverable**. Its bytes were destroyed by a text/UTF-8 transcoding pass; only filenames and the outer `Payload/InjectorApp.app/` tree survive. No behavioral claims are possible.

---

## 1. Artifact inventory

| Artifact | Size | SHA-256 | State |
|---|---:|---|---|
| `X-v5.2.0-b124.ipa` | 38,720,948 | `b27c2f33aed16d3ed2e1ed388bea3f1d5b851732a91450480a0229701a9fdef6` | Valid, analysed |
| `Proxy 3.0.ipa` | 92,009,977 | `5c824856f7d0850b0b178025dd136ad4963168f22f404f331e73b244e682485c` | Corrupted, unrecoverable |
| `3105/` | source tree | — | 3105 v2.0 SwiftUI source snapshot |
| `ff-offsets.json` | 2,299 | — | 64 IL2CPP offsets, unstamped |
| `ff-dump.md` | 3,930 | — | Human-readable copy of the same offsets |
| Screenshots (12) | — | — | X 0.2.0 GUI reference |

`Payload/zadaDMA.app` in the repo is **resources-only** — no `zadaDMA` executable. `project.yml` builds the app from the Swift sources and links the Rust/Motor libraries. Do not treat the checked-in Payload as an installable app.

Bundled packages, all in `Payload/zadaDMA.app/` (the X IPA itself ships **no** `.3105` files; it downloads products from the catalogue):

| Package | Bytes | SHA-256 | Meta name |
|---|---:|---|---|
| `aimbot_drag.3105` | 81,221 | `418f5924fd1cda1c3c8b95bafef49b45fdb366490fffb9708a85c5fad457848e` | Aim Cuello |
| `aimdrag_neck.3105` | 81,226 | `fd9d259b1b0d1d851860f2af9087be9cbbc9d6d0121ed40721755f4ca679b488` | Aim Cuello + Antena |
| `aimneck_90.3105` | 18,795 | `3f491994fcbc3f3df68515f6e2e2d9ef5c7984234ec4a28ae1321dd7f79ab91d` | Aim Drag Neck |
| `aimneck_cache.3105` | 101,718 | `32ba4435ed34e235566d99ef5c0f966eab6c15af84835bc929de967dfc9984d3` | Aim Neck |
| `aimneck_torso_cache.3105` | 101,722 | `2d2d6c22a5b12724efa409ada24df14811816e576e23d9a4e56ef5b47d041cd0` | Aim Neck + Torso |
| `aimtorso_cache.3105` | 101,747 | `93ebe50a70948ac371086fbb5de6709a0743c023bb6ec7f7a72cd16a9ec6c79b` | Aim Torso |

---

## 2. X 5.2.0 (build 124)

### 2.1 Bundle and binary

| Field | Value |
|---|---|
| `CFBundleName` / display | `X` |
| `CFBundleIdentifier` | `com.apple.mobile.MobileHouseArrest` |
| Version / build | `5.2.0` / `124` |
| Executable | `X`, 15,980,120 bytes, arm64 `MH_EXECUTE` |
| `MinimumOSVersion` | `16.0` |
| SDK | `iphoneos26.5` |
| `UIDeviceFamily` | `[1, 2]` — iPhone **and** iPad |
| Background modes | `audio` |
| URL scheme | `threeoneosfive` (`CFBundleURLName` `com.yangjiii.3105.patch-import`) |
| Bonjour services | `_remotepairing-pairable-host._tcp`, `_aircardprobe._tcp` |
| Query schemes | `freefire`, `freefiremax`, Google OAuth callback, `localdevvpn` |
| Code signature | none in bundle — requires re-signing |

The bundle identifier is spoofed as Apple's House Arrest service. The likely purpose is to inherit House Arrest-style container semantics and entitlements; that is an inference from the identifier and the AFC/House Arrest code, not an Apple-documented behaviour.

`Assets.car` is 33.3 MB. Three WAVs (`activar`, `desactivar`, `Welcome`) are the only sounds.

### 2.2 What is actually in the IPA

X is not a small aim tool. Its 820 localization keys per language (en/es/pt) cover the full 3105 feature set plus Free Fire:

- **Free Fire catalogue**: `ff.cat.aimbot`, `ff.cat.combo`, `ff.cat.holograma`, `ff.cat.mod_skin`, `ff.cat.others`; products `Aim Body`, `Aim Chest`, `Aim Drag`, `Aim File`, `Aim Head`, `Aim Magic`, `Aim Neck`, `Aungs White`, `Blue Location`, `Chams + Purple Holo`, `Chams No Color`, `Mod Skin Gojo`, `White Gun`, `Red Touch`, `Unlock FPS 144`, character/weapon holograms, turquoise weapon hologram.
- **Device management**: kernel exploit panel, sandbox token, MobileGestalt editor (`gestalt.*`), PosterBoard wallpaper lab (`.tendies`), cleaner, file browser, app-data browser, patch projects.
- **Licensing**: key activation, VIP status, UDID, notices, music.
- **Pairing**: `settings.pair_on_this_iphone`, `settings.pairing_pin`, `settings.import_pairing`, `settings.open_localdevvpn`, `settings.export_pairing`, `settings.delete_pairing`.
- **Anti-tamper**: `security.blocked.debugger`, `security.blocked.integrity`, `security.blocked.simulator`.

Credits embedded in the localization: `bnxyung7`, `filzaslop`, `forcequit`, `pocket_poster`, `sandbox_escape`, `seo`, `yangjiii`.

AppIntents exposed to Siri/Shortcuts: `ActivarProductoIntent`, `DesactivarProductoIntent`, `AbrirFreeFireIntent`, `AbrirFreeFireMaxIntent`.

The current zadaDMA UI implements only the aim subset of this catalogue. That is the main functional gap between the shipped X and the repo.

The X IPA contains **no `.3105` payloads**: `Payload/X.app` is just the binary, `Assets.car`, localizations, AppIntents, and three WAVs. Products are fetched from `/api/products/files/<slug>` at runtime and validated as `.3105` before install. The six packages in this report are the zadaDMA bundle, which pre-loads the same format for offline use. This is why X can change its catalogue without an IPA update, and why the local package hashes are not part of the X IPA hash.

### 2.3 Licence backend

Base URL: `https://xkeyapi.onrender.com/api`

| Endpoint | Purpose |
|---|---|
| `/api/version/check` | Forced update / remote kill switch |
| `/api/notifications/` | Notification inbox |
| `/api/notifications/active` | Active announcements |
| `/api/products/catalog` | Product catalogue (slugs, filenames, permissions) |
| `/api/products/files/<slug>` | Product payload download |
| `/api/music`, `/api/music/files/` | Music catalogue and files |
| `/udid/web` | UDID-bound licence web page |

State machine: `empty → activating → active`, with terminal/failure branches `expired`, `blocked`, `paused`, `noPermission`, `notActivated`, `refused`, `unavailable`, `bad_slug`, `banned`, `not_found`.

Server-side operator powers: block a key, pause a key, block a device, block an IPA version (`blocked.ipa.*`), issue a UDID-keyed web page. This is a real remote kill switch, not telemetry. The app is useless for patching once the licence is refused.

### 2.4 Exploit routing

- **iOS 17–18**: `kexploit_wrapper.m` calls the weakly linked `kfd_init()`; success returns a kernel base, cached in `_cached_kbase`. `kexploit_kbase()` feeds the container-query path. `kfd` is `kexploit_opa334`.
- **iOS 26–27**: `worse_query` / `bad_query` is the intended sandbox escape, but the current implementation is guarded: the legacy entry point delegates to `ContainerAccess`'s MCM lease. The raw `container_query` sequence is kept only as a compatibility symbol.
- **A18/M4 special-casing** is present in strings (`[+] Running on A18/M4 device`).
- The app auto-runs the kernel exploit on launch in the background and offers a manual "Run Kernel Exploit" panel. It warns that the device may freeze for 10–30 s.
- The app does not support SideStore / AltStore / 3uTools / LiveContainer as installation routes and needs an enterprise certificate. This is a signing/entitlement requirement, not a technical limitation.

---

## 3. Proxy 3.0.ipa — verdict: unrecoverable

- 92,009,977 bytes, SHA-256 `5c824856f7d0850b0b178025dd136ad4963168f22f404f331e73b244e682485c`.
- **21,041,416** occurrences of `EF BF BD` (UTF-8 replacement character). That is roughly 21 million destroyed bytes, not a few bad filenames.
- 378,337 CR and 378,337 LF bytes; the line-ending count is symmetric, consistent with a CRLF conversion pass.
- 21 local `PK\x03\x04` headers, 21 `PK\x01\x02` markers, one `PK\x05\x06` at offset 92,009,955 — but no usable central directory. The ZIP tooling sees a ghost archive.
- Original was ~50.3 MB; the 92 MB size is the inflation caused by replacement characters plus CRLF doubling.

What survives is a filename tree under `Payload/InjectorApp.app/`:

```
Payload/InjectorApp.app/
  InjectorApp            (binary, contents destroyed)
  Info.plist             (text survives partially)
  PkgInfo
  AppIcon*.png
  Banner1.gif … Banner9.gif
  TreeBanner.gif
  bkebe.gif
  eyesbanner.gif
  cryingbanner.gif
```

**No executable analysis is possible.** The binary's bytes are gone; static disassembly would be fiction. The only defensible statements are the app name (`InjectorApp`), the banner asset names, and the fact that it was packaged as an IPA. Do not reuse any prior "Proxy" behavioral claim unless it came from a clean copy.

The corruption pattern is diagnostic: a binary file passed through a text pipeline that decoded it as ANSI/Windows-1252 and re-encoded as UTF-8, with newline normalization. The original bytes cannot be inverted because many distinct byte values map to the same `U+FFFD`.

---

## 4. 3105 v2.0 — the upstream app

`3105/` is a SwiftUI source snapshot, not an IPA. README: version 2.0, iOS 17.0–18.7.1 (kernel exploit), 26.0–26.6.1 (pairing), 27 Developer Beta 1–4 (`24A5355q`, `24A5370h`, `24A5380h`, `24A5390f`).

Feature surface:

- Multi-source repository marketplace with For You / New feeds.
- Installed library with update indicators and type badges (patch, wallpaper, dialer theme, feature).
- Portable `.3105` patches with multiple target bundles/App Groups, user inputs (text/switch/choice), optional password, and original-file restore.
- `.3105pass` dialer themes, `.tendies` PosterBoard wallpapers.
- Files workspace: app data, App Groups, hidden files, tabs, favourites, plist editor, ZIP import/export.
- Cleaner (Library/Caches + tmp only) and installable 3105 features.
- iOS 27 extras: Lock Screen Footnote, Supervised mode.

Design system (`views/DesignSystem.swift`):

| Token | Value |
|---|---|
| Accent (light) | `UIColor(0.85, 0.42, 0.20, 1)` ≈ `#D96B33` |
| Accent (dark) | `UIColor(1.00, 0.64, 0.42, 1)` ≈ `#FFA36B` |
| Page background | `.systemBackground` |
| Console background | `.secondarySystemBackground` |
| Page inset | 16 pt |
| Content card radius | 20 pt continuous |
| Content card inset/padding | 16 pt / 16 pt |
| Row icon | 17 pt in 28 pt frame |
| File row | 17 pt icon in 30 pt frame, 60 pt height |
| App icon | 32 pt |

Screenshot mapping:

| Image | View(s) |
|---|---|
| `docs/images/home-2.0.png` | `RepositoryHomeView` — marketplace home, featured/For You cards, source chips |
| `docs/images/sources-2.0.png` | `RepositorySourcesView` + `RepositoryMarketplaceView` |
| `docs/images/patches.png` | `PatchProjectsView`, `PatchProjectEditorView`, `FolderPatchSelectionView` |
| `docs/images/installed-2.0.png` | Installed library inside `PatchProjectsView` (`installed.kind.*` badges) |
| `docs/images/cleaner.png` | `CleanerView` — scan, selection, clean result |
| `docs/images/app-icon.png` | `AppLogo` / app icon |

3105 is the parent codebase. X 5.2.0 and zadaDMA keep its patch engine and views but swap the product identity and add the Free Fire/pairing paths.

---

## 5. `.3105` v1 container format

Authoritative implementation: `Motor/PatchPackageCodec.m`. `Patches/PatchPackage.swift` documents a different schema and does **not** match the six bundled files.

### 5.1 Header

Little-endian throughout:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | magic `3105` |
| 4 | 4 | `u32` version = `1` |
| 8 | 16 | PBKDF2 salt |
| 24 | 4 | `u32` iterations = `120000` |
| 28 | 4 | `u32` wrapped-key length = `32` |
| 32 | 32 | wrapped content key (AES-256-GCM) |
| 64 | 12 | wrap nonce |
| 76 | 16 | wrap tag |
| 92 | 12 | payload nonce |
| 104 | 16 | payload tag |
| 120 | 8 | `u64` ciphertext length |
| 128 | n | ciphertext |

Total header = 128 bytes. Ciphertext length is exactly `package_size − 128`; `aimbot_drag.3105` is 81,221 bytes → 81,093 bytes of GCM ciphertext. Because the decoded JSON in the working directory was re-serialized with formatting, its on-disk length is slightly larger than the plaintext; compare decrypted bytes, not file sizes.

Crypto:

1. `KEK = PBKDF2-HMAC-SHA256(password, salt, 120000, 32)`.
2. `content_key = AES-256-GCM-open(KEK, wrap_nonce, wrapped_key, wrap_tag)`.
3. `plaintext = AES-256-GCM-open(content_key, payload_nonce, ciphertext, payload_tag)`.

All six packages decrypt with the shared password **`shared-server-secret`**. The password is not per-package and is embedded in the client, so the container is obfuscation plus integrity, not a secret.

### 5.2 Payload JSON

```json
{
  "files":   { "<name>": "<base64 bytes>" },
  "rules":   [ { "src": "<file key>", "dst": "<path relative to container>" } ],
  "digests": { "<file key>": "<sha256 hex>" },
  "meta":    { "name": "...", "rawLength": 63083, "compressed": true }
}
```

`files` values are base64, so the string length is ~4/3 of the real byte count. For example `mod_asset.raw` is a 62,188-character base64 string = **46,640 bytes**.

`meta.compressed` and `meta.rawLength` are advisory; the rule path and the actual gzip stream decide behaviour.

### 5.3 Decoded catalogue

| Package | Payload | Actual bytes | SHA-256 of payload |
|---|---|---:|---|
| `aimbot_drag` | `mod_asset.tdn` | 13,783 (gzip) | `461120cc…a91ae59` |
| | `mod_asset.raw` | 46,640 | `3783ba4a…68d1d9bb` |
| `aimdrag_neck` | `mod_asset.tdn` | 13,782 (gzip) | `ef02ccda…39028b6` |
| | `mod_asset.raw` | 46,640 | `1bbb8189…39e72d0` |
| `aimneck_90` | `mod_asset.tdn` | 13,778 (gzip) | `5584d053…d7e27e` |
| `aimneck_cache` | `cache_res_mod.bin` | 12,742 (gzip) | `a2b68872…b36263` |
| | `cache_res_raw.bin` | 63,083 | `69461600…ce5dbaa` |
| `aimneck_torso_cache` | `cache_res_mod.bin` | 12,741 (gzip) | `fb246f74…d5e2559` |
| | `cache_res_raw.bin` | 63,083 | `d91a6560…400170d` |
| `aimtorso_cache` | `cache_res_mod.bin` | 12,763 (gzip) | `d1eb05e1…28f33bd` |
| | `cache_res_raw.bin` | 63,083 | `009f2dde…0c46b526` |

The full hashes are in the decoded JSON in `%TEMP%\opencode\ipaanalysis\decoded3105\`; the truncated forms above are for quick cross-checking.

### 5.4 Rule targets

Avatar packages:

```
Data/Raw/ios/gameassetbundles/avatar/assetindexer.tdn~2F53YNFWXQZyPdFl8HWBBwtXk~3D
Data/Raw/ios/gameassetbundles/avatar/assetindexer.tdn~2F53YNFWXQZyPdFl8HWBBwtXk~3D.raw.tmp
```

`~2F` = `/`, `~3D` = `=`; the leaf is the URL-escaped Base64 SHA-1 of the gzip. Free Fire names downloaded bundles this way, so the leaf changes with every game build. Avatar packages hard-code the current leaf; the cache packages use the `{gz}` placeholder and resolve it at install time (Section 8.2).

Cache packages:

```
Data/Raw/ios/gameassetbundles/cache_res.{gz}
Data/Raw/ios/gameassetbundles/cache_res.{gz}.raw.tmp
```

---

## 6. Avatar patch semantics — `assetindexer.tdn` / `.raw`

### 6.1 File relationship

- `.tdn` is the download/index file; it is gzip. Decompressed size = **46,640 bytes**.
- `.raw` is the sibling decompressed payload; size = **46,640 bytes**.
- The base (unmodded) raw SHA-256 is `e29b31619db60ad098bb150833b5f9ee7cf8751f12ea33cf442c017a91aa5915`.
- `aimbot_drag` and `aimdrag_neck` replace both the `.tdn` and the `.raw.tmp`; `aimneck_90` replaces only the `.tdn`.

### 6.2 Bone local-scale groups

Each group is three little-endian `float32` values (X, Y, Z) in Unity's `m_LocalScale`.

| Rig | Bone | Raw offset |
|---|---|---:|
| Male | Head | `0x6F50` |
| Male | Spine1 | `0x7020` |
| Male | Neck | `0x7658` |
| Female | Head | `0xA454` |
| Female | Spine1 | `0xA494` |
| Female | Neck | `0xAA88` |

### 6.3 Confirmed scale table

| Package | Head | Spine1 | Neck | Applied to |
|---|---:|---:|---:|---|
| `aimbot_drag` | 3.0× | 2.0× | 5.0× | male + female |
| `aimdrag_neck` | 10.0× | 5.0× | 5.0× | male + female |

`aimneck_90` does not follow this table; it is a two-float edit at other serialized slots (6.4).

The base Neck value is `1.000000119…` (`0x3F800001`), not exactly `1.0`. Any diff tool that compares against `1.0` will miss one byte per component.

### 6.4 `aimneck_90`

Only two floats change, at the same relative slot in the male and female blocks:

| Raw offset | Before | After | Modified byte ranges |
|---:|---:|---:|---|
| `0x6AFC` | `1.0` (`00 00 80 3F`) | `211.0` (`00 00 53 43`) | `0x6AFE–0x6AFF` |
| `0xA040` | `1.0` | `211.0` | `0xA042–0xA043` |

That is 4 bytes in 2 ranges. The patched field's semantic name is not resolved from the serialized type tree. What is certain: the rest of the 46,640-byte asset is byte-identical to the base, and the edit is not one of the six scale vectors. This is the cleanest demonstration that the package is a byte-level asset edit, not code.

### 6.5 Diff footprint

`aimbot_drag` and `aimdrag_neck` each differ from the base raw in **42 bytes across 18 ranges** — exactly the six scale vectors (male/female × Head/Spine1/Neck) where at least one byte changes. The `.tdn` is the gzip of that raw, so its compressed size differs slightly (13,783 vs 13,782 bytes) while decompressing to the same 46,640.

Net effect: the game reads larger local scales for the head/neck chain, so the rendered and hit-test geometry associated with those bones covers more space. It is a static asset change; it persists until the original bytes are restored or the game re-downloads the bundle.

---

## 7. Cache patch semantics — `cache_res`

### 7.1 UnityFS container

The cache payloads are Unity asset bundles:

| Property | Value |
|---|---|
| Signature | `UnityFS` |
| Unity version | `2018.4.12f1` |
| Vanilla size | 63,056 bytes |
| Vanilla flags | `0x243` |
| Modded flags | `0x40` (uncompressed / block info at end) |
| Modded size | 63,083 bytes |
| Rebuild | UnityPy, `packer="none"` |

The mods are uncompressed bundles; the vanilla game ships an encrypted/compressed variant. The game accepts the uncompressed rebuild, which is why the patch works without touching the loader.

### 7.2 Head capsules

Both head colliders grow by the same deltas:

- radius: **+0.030941**
- height: **+0.022509**
- center.x: **+0.005**

| Rig | Field | Vanilla | Modded |
|---|---|---:|---:|
| Male `bone_Head` | radius | 0.059058815 | 0.089999817 |
| | height | 0.12749058 | 0.149999574 |
| | center.x | -0.045245036 | -0.040245038 |
| Female `bone_Head` | radius | 0.059153982 | 0.090094984 |
| | height | 0.130384237 | 0.15289323 |
| | center.x | -0.040775388 | -0.03577539 |

This is the actual "bigger head hitbox" change. It is a `CapsuleCollider` geometry edit, not a bone scale edit.

### 7.3 Female left-hand capsule

The female `bone_LeftHand` carries more than one capsule. The **larger** one (`radius 0.028295275`, `height 0.068755388`) is set `m_Enabled = false` and its floats are zeroed in:

- `aimneck_cache`
- `aimneck_torso_cache`

`aimtorso_cache` leaves it enabled.

This is the opposite of an earlier draft claim ("shrink/enable"). The package **disables** the larger female left-hand capsule, so that capsule no longer contributes a hit volume near the head/neck.

### 7.4 Torso hit helpers

Torso variants rewrite `HitDetectColliderHelper.ColliderType` from **2 → 1** on exactly six helpers:

| Rig | Helpers |
|---|---|
| Male | `bone_Spine1`, `bone_Spine`, `bone_Hips_Dummy` |
| Female | `bone_Spine1`, `bone_Spine`, `bone_Hips` |

`aimneck_cache` does not change helper types. The combined `aimneck_torso_cache` does both the neck and torso edits.

### 7.5 Net effect table

| Package | Head capsules | Female left hand | Torso helper types |
|---|---|---|---|
| `aimneck_cache` | enlarged | larger capsule disabled | unchanged |
| `aimtorso_cache` | unchanged | unchanged | 2 → 1 (6) |
| `aimneck_torso_cache` | enlarged | larger capsule disabled | 2 → 1 (6) |

---

## 8. Install pipeline

### 8.1 Container resolution

`DevicePatchService` asks `ContainerAccess` for the Free Fire data container by bundle ID:

- Primary: MCM (`MobileContainerManager`) class-2 lease, loaded via `dlopen`/`dlsym` (`container_query_create`, `container_query_get_single_result`, `container_copy_sandbox_token`, `container_object_sandbox_extension_activate`, `consume_extension`).
- Fallback: filesystem/metadata scan when MCM denies the lease (`Resolve the game container by metadata scan when MCM denies the class-2 lease`).
- `/var` and `/private/var` are normalized so a backup captured through one route is not mistaken for a stale install.
- The target is `Documents/Data/Raw/...` when present; the bare `Data/Raw/...` and app-bundle copies are also considered.

`MotorBridge.installedFreeFireBundleIDs()` enumerates the Free Fire/Free Fire MAX bundle IDs. `MotorBridge.applyPatchFile(_:bundleIDs:)` runs the whole transaction off the main thread, with a background-audio keep-alive and a trace pump so the UI can show each step.

### 8.2 `{gz}` resolution

`cache_res` is versioned by the gzip SHA-1. `PatchTransaction` reads `cache_res.fileinfo` (from the container or via Airlift) and parses the line:

```
key, rawSHA1B64, rawSize, 0, gzSHA1B64, gzSize, True, 0
```

`{gz}` becomes the URL-escaped Base64 of the **gzip** SHA-1:

- `+` → `~2B`
- `/` → `~2F`
- `=` → `~3D`

If the manifest is unavailable, it probes known leaves and skips any that cannot be read back, so a stale entry is never written into a path that cannot be restored.

The avatar leaf `assetindexer.tdn~2F53YNFWXQZyPdFl8HWBBwtXk~3D` is the same encoding, hard-coded.

### 8.3 Transaction and rollback

`PatchTransaction` enforces, in order:

1. Source blob exists and its SHA-256 equals `digests[src]`; mismatch aborts before any write.
2. Destination is inside the container; path traversal is rejected.
3. Target must already exist — the patcher never creates a missing file, because it could not be restored.
4. The exact original is read and stored before the first write.
5. Writes are recorded in a plan; a failure rolls back earlier writes.
6. A read-back mismatch triggers rollback and reports "written but did not match".

Backups live in:

```
<Application Support>/ThreeOneOSFive/originals/<sha256(normalized path)>.bin
<Application Support>/ThreeOneOSFive/originals/<sha256(normalized path)>.json
```

Metadata: `path`, `bundleID`, `group`, `existed`, `size`, `sha256`, `createdAt`.

Grouping is by destination stem. `cache_res.<hash>.gz` and `cache_res.<hash>.gz.raw.tmp` share one group, so neck, torso and combined packages capture the same original once; toggling one card off does not capture an already-modded file as "original". A JSONL ledger (`ThreeOneOSFive/ledger.jsonl`) records each transaction.

The UI's toggle-off path calls `restorePatchWithFallback`; if restoration fails, the card stays on and the log says so. That is the correct failure direction for a cheat: never leave the user thinking the original is back when it is not.

### 8.4 Airlift fallback

When MCM cannot write, `AirliftBridge` uses the Rust `airlift` core:

1. **Stage** — build a StreamingZip archive (symlink + payload) and a `Books.plist`; write through AFC and `streaming_zip_conduit`.
2. **AirTraffic sync** — trigger FileComplete messages via `com.apple.atc` (Grappa token).
3. **Finish** — read back a canary, verify the bytes, clean up, restore the Books state.

The write path is: pair-verify → TLS-PSK tunnel → RSD → House Arrest (`vend_container` / `vend_documents`) → AFC write. Candidate paths are tried in order: `Documents/...`, bare `Data/Raw/...`, `Library/...`, `Library/Caches/...`.

This is Apple's own sync/ATC machinery being driven as a file transport. It is powerful but stateful; a failed cleanup can leave a relocated file present in AFC. The code has explicit recovery and canary checks for that reason.

---

## 9. Pairing and tunnel (`zdma_pairing`)

### 9.1 On-device pairable host

`zdma_pairing_host_accept`:

- binds `0.0.0.0:<dynamic port>` (not `49152`; the port is chosen at runtime);
- generates an uppercase UUID identifier;
- advertises `_remotepairing-pairable-host._tcp` with TXT records `identifier`, `authTag`, `flags`, `ver`, `minVer`;
- shows a **6-digit PIN** and posts a local notification;
- writes an `RPPairing` property list.

`allows_pinless_pairing = false`. The advertised model is `Mac17,7` (the conventional RPPairing host model). `PairingController` persists to `Documents/rppairing.plist` and a v2 `Documents/rppairing.ready` marker, validates the uppercase identifier, uses `hostName = "zadaDMA"`, and keeps the pairing alive with `BGContinuedProcessingTask` on iOS 26+.

The flow is a **self-pairing loop**: the app advertises the pairable endpoint and also runs the pair-verify client against the local device. The PIN is entered in iOS Developer Mode (`Pairing needs an authorized session`, `Open Settings > Privacy & Security > Developer Mode to pair`, `Enter PIN %@ in Developer Mode`). The resulting pairing file is what authorizes the RSD/AFC session.

### 9.2 Pair-verify and tunnel

`zdma_tunnel_write_file`:

1. Parses a comma-separated endpoint list; loopback and utun addresses are preferred.
2. TCP connect timeout **3 s**; pair-verify handshake **8 s**; verification **12 s**.
3. Pair-verify using the RPPairing file and the peer `altIRK`; only an advertisement whose `authTag` validates is contacted.
4. TLS-PSK tunnel.
5. RSD handshake.
6. House Arrest `vend_container` / `vend_documents`.
7. AFC write to the resolved path.

A direct Wi-Fi address is reset by `remoted`; the working route is loopback/utun (`10.7.*`, `127.0.0.1`). The error text tells the user to install/restart **LocalDevVPN**, which provides the loopback route the app expects. `NSBonjourServices` and the `localdevvpn` query scheme in `Info.plist` are there for this path. zadaDMA does **not** create the VPN itself; `SettingsView` opens the App Store search for LocalDevVPN and the app expects the user to connect it before applying or restoring a patch.

This is why iOS 27 support is not a kernel exploit: it is Apple's Developer Mode remote-pairing stack, driven from the device against itself, with a VPN route to make the loopback endpoint reachable.

---

## 10. GUI design — screenshots to spec

The supplied screenshots are the **X 0.2.0** build (settings shows `v0.2.0`; the bundle in the repo still says `5.2.0/124`). They are the design reference for the zadaDMA rebuild. The visual language is a dark, orange-accented card UI with a custom capsule tab bar.

### 10.1 Tokens

| Token | Value | Use |
|---|---|---|
| `appBackground` | RGB(0.06, 0.06, 0.08) `#0F0F14` | page |
| `appCard` | RGB(0.12, 0.12, 0.14) `#1F1F24` | cards, fields |
| `appSecondary` | RGB(0.18, 0.18, 0.20) `#2E2E33` | segmented control track, secondary rows |
| `appOrange` | RGB(1.0, 0.478, 0.0) `#FF7A00` | primary action, selected state, icon |
| `appGreen` | RGB(0.2, 0.8, 0.4) `#33CC66` | supported/active |
| `appRed` | RGB(0.9, 0.3, 0.3) `#E64D4D` | blocked/unsupported |
| Text primary | `.white` | titles/values |
| Text secondary | `.gray` (`#8E8E93`) | captions |
| Card radius | 16 pt (onboarding rows 12, sheet 20) | |
| Button radius | 14 pt | |
| Page inset | 16 pt | |
| Card padding | 16 pt | |
| Vertical rhythm | 18 pt between cards, 12–14 pt inside | |
| App tile | 52×52, radius 15, `X` 26 pt heavy | header |
| Splash ring | 120 pt, 4 pt stroke, arc 0→0.8 over 2 s | launch |
| Tab bar | capsule, 16 pt side inset, 12 pt vertical padding, 10 pt labels | shell |

### 10.2 Screen map

**1. Splash (`SplashView.swift`)**

Black page. Centered 120 pt ring with orange progress arc and 50 pt heavy `X`. Below: `X`, device model, iOS version. Bottom stack:

- Card: `Want to listen to music?` with `No` (dark) and `Yes` (orange) buttons.
- Row: upload icon, `Install profile`, subtext `So we recognize this iPhone`, chevron.
- Footer: spinner + `Loading`.

Animation: arc to 0.8 over 2 s, dismiss after 2.5 s. The music prompt is a modal card, not a system alert.

**2. Onboarding (`OnboardingView.swift`, 5 steps)**

Top: five capsule segments, filled orange up to the current step; `Step N of 5`.

| Step | Layout | Copy |
|---|---|---|
| 1 Welcome | orange rounded-square X icon, page dots | `Welcome to X`, `Developed by bnxyung7` |
| 2 Language | icon, three rows with subtitle + checkmark | `Choose your language`, `You can change this later in Settings.`, Español / English / Português, `Next`, `Select a language to continue.` |
| 3 Initial setup | icon, appearance segmented control, two game cards | `Initial setup`, `Choose the theme and which game the list shows. Both stay changeable later in Settings and on your profile.`, `System / Light / Dark`, `Free Fire` (orange, flame) / `Free Fire MAX` (crown) |
| 4 Supported iOS versions | icon, four rows with chevron and build count, device line | `Supported iOS versions`, `iOS 17`, `iOS 18`, `iOS 26`, `iOS 27`, `N exact builds`, `This device: iOS 27.0.1 (24A446)`, `X allows only the exact build IDs listed in Settings.` |
| 5 Certificate requirements | shield icon, three bullets | `Certificate requirements`, green: works with enterprise certs incl. eSign; red: does not work with SideStore/AltStore/3uTools/LiveContainer; gray: use a supported certificate before continuing. |

Bottom bar: `Back` (dark, half width) and `Next`/`Finish` (orange, half width).

**3. Home (`HomeView.swift`)**

Header: 52 pt orange `X` tile, `X`, `Your iPhone, ready.`, `Free Fire` green badge, two circular icon buttons at top right (screenshot: gift/box + gear; source has only the gear), settings sheet on gear.

`Device status` card:

| Row | Value |
|---|---|
| Hardware model | `iPhone15,7` |
| iOS Version | `27.0.1 (24A446)` |
| Exploit compatibility | `Supported` (green) |

Below, the source adds a `Pairing & Tunnel` card with shield icon, `Connected` / `Not connected`, status text, and a `Settings` button; it is not visible in the screenshot crop. Footer: `v0.2.0`.

**4. Settings (`Views/SettingsView.swift`)**

Form of dark cards:

- Version card: `X`, `v0.2.0`, signing/UDID line.
- `Language`: segmented Español / English / Português.
- `Appearance`: segmented System / Light / Dark.
- `Device`: Hardware model, iOS Version.
- `Pairing & Tunnel`: runtime connection (`Not connected`), pairing status (`No pairing file`), explanation, `Start Pairing` / `Stop Pairing`, PIN display, `Open LocalDevVPN`, `Import pairing file`.
- `Verified versions`: `Exploit compatibility` + `Supported`; rows iOS 17 / 18 / 26 / 27 with build counts; expandable iOS 27 build list; footer `Only the exact builds listed above are verified for the exploit. iOS is still recognized; pairing and tunnel status are separate.`
- `Social media`: Discord support/announcements, Telegram, GitHub.
- `Done` in the nav bar.

**5. Profile (`ProfileView.swift`)**

- Membership card: lock/shield icon, `No membership`, `Activate your key to use X`, `Activate key` row with chevron.
- `Game`: `Free Fire` (orange flame card) / `Free Fire MAX` (crown card).
- `Notices`: `Everything the panel published`, unread count.
- `Music`: toggle, `You can turn it off on this iPhone`.

**6. Support (`SupportView.swift`)**

- `Support Center`, `Discord announcements and help`.
- `Discord support` / `Direct help`.
- `Discord announcements` / `Announcements and downloads`.
- `Check status` / `Compare the applied changes with the files on this iPhone`.

**7. Activate membership sheet**

`Activate membership`, key field with `Enter your access key`, orange `Activate key` button, `Close`. Presented as a medium detent sheet over Profile.

**8. Game screen (`FreeFireView.swift`, not in the supplied screenshots)**

- Header card: game name, `Ready to load`, live count, time left.
- Category chips: `Aimbot`, `Holograma`, `Skin`.
- Sub-tabs: `Aimbot Cache` / `Aimbot Avatar`.
- Cards: `AIM NECK` / `AIM NECK + ANTENNA` (internal keys `AIM DRAG` / `AIM PECHO`), each with loaded/not-loaded status, `SAFE` badge, orange toggle.
- Log console: monospaced, auto-scroll, `-` when empty.

### 10.3 Screenshot/source discrepancies to fix

These are real and should be resolved before calling the GUI "done":

1. **iOS 27 onboarding row.** The screenshot has four rows; `OnboardingView.supportedStep` iterates only `["iOS 17","iOS 18","iOS 26"]`. `VerifiedVersions` already has the iOS 27 data, so add the row (and the expandable list) to onboarding.
2. **Tab bar.** The screenshot has three tabs (Home / Profile / Support); the source has four (Home / Game / Profile / Support) with a prominent center Game button. Pick one. For a Free Fire tool, the four-tab layout is the better product; the three-tab screenshot is the 0.2.0 shell where Game is reached from Home.
3. **Certificate copy.** Shipped X says SideStore / AltStore / 3uTools / LiveContainer. The repo says SideStore / AltStore / **TrollStore** / other. Use the shipped copy unless TrollStore is intentional.
4. **Version branding.** UI says `0.2.0`; `Payload/zadaDMA.app/Info.plist` says `zadaDMA 5.2.0 (124)`. Pick one source of truth and surface it in Settings (`CFBundleShortVersionString` + `CFBundleVersion`), not a hard-coded string.
5. **Home header buttons.** Screenshot has two circular actions; source has one gear. Add the notifications/support action or remove it from the design.
6. **"AIM PECHO 70%".** No `70%` string exists in the IPA localization, the `.3105` metadata, or the current source. The visible card is `AIM NECK + ANTENNA` (`aim_chest`) and the payload is `aimneck_torso_cache` / `aimtorso_cache`. If "70%" is a catalogue label, it is server-supplied and not part of the local package.
7. **Hologram / Skin cards.** They reference `hologram` and `skin` packages that are not in `Payload/zadaDMA.app`. Either ship them or hide the cards behind a `Bundle.main.path` check (the toggle already fails gracefully with "patch-i nuk është në këtë build").
8. **`aim_drag` label mismatch.** Internal feature key is `AIM DRAG`, but the English localization value is `AIM NECK`; Spanish `AIM CUELLO`, Portuguese `AIM PESCOÇO`. The card title and the feature key should be separate constants, not the same string.
9. **`UIDeviceFamily`.** Corrected to `[1,2]`; if the product is iPhone-only, change the plist, not the report.

### 10.4 Rebuild order

1. Freeze the design tokens (`Theme.swift`) and build a component catalogue: `Card`, `SectionHeader`, `SettingRow`, `StatusPill`, `Segmented`, `PrimaryButton`, `SecondaryButton`, `GameCard`, `PatchCard`, `LogConsole`, `TabBar`.
2. Shell: `ContentView` → `SplashView` → `OnboardingView` → `MainTabView` (4 tabs) + `SettingsView` sheet.
3. Screens in screenshot order: Splash, Welcome, Language, Initial Setup, Supported Versions, Certificate, Home, Settings, Profile, Support, Activation.
4. Wire state via `AppState` (`language`, `appearance`, `selectedGame`, `isActivated`, `licenseKey`, `deviceModel`, `deviceiOS`, four feature booleans, `patchLog`).
5. Wire the game screen last: category/sub-tab state, `MotorBridge` apply/restore, log trace, and the shared `cache_res` re-apply rule.
6. Add a UI test pass for the exact screenshot strings and a dark/light snapshot for Settings.

---

## 11. Free Fire offsets — `ff-offsets.json`

### 11.1 What they are

64 IL2CPP field offsets imported through a Discord bot (`c!addos`). The file has no game build stamp:

```json
{ "game": "ff", "version": "importado", "updated_at": null }
```

Treat them as a **memory-tool map**, not as part of the `.3105` patcher. The patcher edits serialized Unity objects (Transform `m_LocalScale`, `CapsuleCollider` radius/height/center, `MonoBehaviour.m_Enabled`, `ColliderType`). The offsets are for resolving live managed objects (Player, Avatar, bones, camera, magnet) in a runtime cheat.

### 11.2 Grouped map

| Group | Field | Offset |
|---|---|---:|
| **IL2CPP primitives** | `managed_native_pointer` | `0x10` |
| | `managed_string_length` | `0x10` |
| | `managed_string_data` | `0x14` |
| | `transform_node_transform` | `0x10` |
| **Game / match** | `game_current_game` | `0x8` |
| | `game_match` | `0x90` |
| | `match_entities` | `0x128` |
| | `match_local_player` | `0xD8` |
| **Player** | `player_data_pool` | `0x70` |
| | `player_cached_transform` | `0x58` |
| | `player_avatar_manager` | `0x770` |
| | `player_follow_camera` | `0x690` |
| | `player_head` | `0x6A0` |
| | `player_legit_source` | `0x708` |
| | `player_legit_destination` | `0x6A8` |
| | `player_nick_name` | `0x490` |
| | `player_original_nick_name` | `0x498` |
| | `player_team` | `0x430` |
| **Avatar** | `avatar_instance` | `0x138` |
| | `avatar_is_visible` | `0x101` |
| | `attributes_array` | `0x10` |
| | `attributes_count` | `0x18` |
| | `attributes_value` | `0x18` |
| **Camera / magnet** | `camera_managed_camera` | `0x30` |
| | `magnet_main_camera_transform` | `0x3E8` |
| | `magnet_colliders` | `0xB58` |
| | `magnet_is_female` | `0xC14` |
| | `magnet_is_firing` | `0x848` |
| | `magnet_shadow_state` | `0x24A8` |
| **Bones** | `bone_head` | `0x6A0` |
| | `bone_neck` | `0x6B0` |
| | `bone_hip` | `0x6A8` |
| | `bone_root` | `0x6C8` |
| | `bone_right_hand` | `0x698` |
| | `bone_left_hand` | `0x6F8` |
| | `bone_right_shoulder` | `0x710` |
| | `bone_left_shoulder` | `0x708` |
| | `bone_right_elbow` | `0x728` |
| | `bone_left_elbow` | `0x730` |
| | `bone_right_wrist` | `0x718` |
| | `bone_left_wrist` | `0x720` |
| | `bone_right_ankle` | `0x6E0` |
| | `bone_left_ankle` | `0x6D8` |
| | `bone_right_foot` | `0x6F0` |
| | `bone_left_foot` | `0x6E8` |
| | `bone_unidentified_04` | `0x6B8` |
| | `bone_unidentified_05` | `0x6C0` |
| | `bone_unidentified_07` | `0x6D0` |
| | `bone_unidentified_19` | `0x9E8` |
| | `bone_unidentified_20` | `0x9F0` |
| | `bone_unidentified_21` | `0x9F8` |
| | `bone_unidentified_22` | `0xA00` |
| | `bone_unidentified_23` | `0xA08` |
| | `bone_unidentified_24` | `0xA10` |
| | `bone_unidentified_25` | `0xA18` |
| | `bone_unidentified_26` | `0x2138` |
| | `bone_unidentified_27` | `0x2140` |
| | `bone_unidentified_28` | `0x2148` |
| | `bone_unidentified_29` | `0x2150` |
| | `bone_unidentified_30` | `0x2158` |
| | `bone_unidentified_31` | `0x2160` |
| | `bone_unidentified_32` | `0x2168` |
| | `bone_unidentified_33` | `0x2170` |
| | `bone_unidentified_34` | `0x2178` |

### 11.3 How to use them honestly

- The bone offsets (`0x6A0` head, `0x6B0` neck, `0x6F8` left hand, etc.) are the managed-side counterparts of the asset objects edited by the `.3105` packages. That conceptual overlap is why both toolchains live in the same folder — but the numeric offsets are **not** used by the patcher.
- Without a build stamp and a matching `libil2cpp`/global-metadata dump, these values are unverified. A Free Fire update will move them. Do not ship them in a UI as "supported" without a version check.
- If the goal is a memory cheat, the offsets need a resolver (module base + field offset, object chain from `match_local_player`/`player_avatar_manager`), not a static JSON. If the goal is the file patcher, the offsets are irrelevant.

---

## 12. Corrections to the earlier report

| Claim | Correction |
|---|---|
| `UIDeviceFamily = 1` (iPhone only) | `[1, 2]` — iPhone and iPad. |
| Cache mods shrink/enable capsules | They **enlarge** both head capsules and **disable** the larger female `bone_LeftHand` capsule. |
| `Patches/PatchPackage.swift` describes the package format | It describes a different schema; `Motor/PatchPackageCodec.m` is authoritative and matches the six bundled files. |
| `.3105` packages are just zip/JSON | They are AES-256-GCM wrapped with a PBKDF2-derived KEK and a per-package content key. |
| `ZADA_SUMMARY.md` / `FINAL_STATUS.md` / `BUILD_FIXES_SUMMARY.md` describe the build | Stale: wrong `gitPush`, port `49152`, `zdma_afc_*`. The source is authoritative. |
| App version is 5.2.0 everywhere | UI reports `0.2.0`; bundle reports `zadaDMA 5.2.0 (124)`; X IPA is `X 5.2.0 (124)`. |
| Proxy 3.0 can be analysed | Bytes are destroyed; only the file tree survives. |
| "AIM PECHO 70%" is in the app | No `70%` string in the IPA/localization/packages; the card is `AIM NECK + ANTENNA`. |
| `AIM DRAG` / `AIM PECHO` are visible labels | They are internal feature keys; the visible English labels resolve to `AIM NECK` / `AIM NECK + ANTENNA`. |

---

## 13. Risk and bottom line

This is a **hostile, remote-controlled cheat stack**, not a neutral mod manager:

- It spoofs an Apple bundle identifier and drives House Arrest/AFC through a self-pairing tunnel.
- It binds UDID/licence state to `xkeyapi.onrender.com` and gives the operator a remote kill switch over the app and the device's patched state.
- It modifies game assets specifically to alter hit detection — a bannable offense in Free Fire, independent of the iOS exploit.
- It requires an enterprise certificate and actively rejects store-style sideloaders; certificate revocation is an operational risk.
- `Proxy 3.0.ipa` is unrecoverable and should not be run even if a clean copy appears.

If the goal is defensive analysis, the useful artifacts are: the `.3105` codec, the transaction/rollback design, the MCM/Airlift routing, and the pairing state machine. If the goal is a clean rebuild, use 3105 as the UI/engine reference and keep the Free Fire patch set behind an explicit, user-visible restore ledger.

---

### Appendix A — exact decoded package internals

```
aimbot_drag.3105
  files:   mod_asset.tdn  (gzip, 13,783 B)  sha256 461120ccd12cbc6d8db991f0efee44c1145aea0902d381af428a97052a91ae59
           mod_asset.raw  (46,640 B)        sha256 3783ba4ab2c3a3e14941f1d8cab6b348ba9e0bfc192ae637fa35a05168d1d9bb
  rules:   Data/Raw/ios/gameassetbundles/avatar/assetindexer.tdn~2F53YNFWXQZyPdFl8HWBBwtXk~3D
           ...raw.tmp
  meta:    Aim Cuello

aimdrag_neck.3105
  files:   mod_asset.tdn  (gzip, 13,782 B)  sha256 ef02ccda80201d53c4712902f5c6956c75bf72a3cc24ea7cd5f7ff2c939028b6
           mod_asset.raw  (46,640 B)        sha256 1bbb81897523ffabbed00f475a32bbe9229597b725caca6356bff92c739e72d0
  rules:   same two paths
  meta:    Aim Cuello + Antena

aimneck_90.3105
  files:   mod_asset.tdn  (gzip, 13,778 B)  sha256 5584d0539fde4d4fb730ea6baec8a515c412d78144fc2f3c4092006b7fd7e27e
  rules:   .tdn only
  meta:    Aim Drag Neck

aimneck_cache.3105
  files:   cache_res_mod.bin (gzip, 12,742 B) sha256 a2b688725ba98b2353571f49abc6ae8e5ec13a5e3aa203ae6fcce5b5e7b36263
           cache_res_raw.bin (63,083 B)       sha256 694616009ff1b8a0cd288092aa699b373c1484246c0757dfc87120665ce5dbaa
  rules:   Data/Raw/ios/gameassetbundles/cache_res.{gz}
           Data/Raw/ios/gameassetbundles/cache_res.{gz}.raw.tmp
  meta:    Aim Neck (rawLength 63,083, compressed true)

aimneck_torso_cache.3105
  files:   cache_res_mod.bin (gzip, 12,741 B) sha256 fb246f7453f0cfb9320a6cd446862361232ac13a884771651bb6513d4e5d2559
           cache_res_raw.bin (63,083 B)       sha256 d91a65601c3936f2727ee9aa082671aec44b335543b55ad5bcd5e9818400170d
  meta:    Aim Neck + Torso

aimtorso_cache.3105
  files:   cache_res_mod.bin (gzip, 12,763 B) sha256 d1eb05e1056fbeceab4ca5367d9574c1e920a872ea7c8f222f2711da028f33bd
           cache_res_raw.bin (63,083 B)       sha256 009f2dde484c9ea424fe3ad6cc12417efa18a74385c46fd6f735390b0c46b526
  meta:    Aim Torso
```

### Appendix B — source-of-truth files

| Question | File |
|---|---|
| `.3105` format | `Motor/PatchPackageCodec.m` |
| Install/restore | `Motor/PatchTransaction.m` |
| Container resolution | `Motor/ContainerAccess.m`, `Motor/DevicePatchService.m` |
| Airlift/ATC | `Airlift/AirliftBridge.m`, `Motor/airlift/rust-core/src/exploit.rs` |
| Pairing/tunnel | `Motor/zdma_pairing/src/lib.rs`, `Motor/IdeviceBridge.m`, `zadaDMA/Services/PairingController.swift` |
| Feature state | `zadaDMA/AppState.swift` |
| Game cards | `zadaDMA/FreeFireView.swift` |
| GUI tokens | `zadaDMA/Theme.swift`, `3105/ThreeOneOSFive/views/DesignSystem.swift` |
| Version checks | `zadaDMA/VerifiedVersions.swift` |
| Offsets | `ff-offsets.json`, `ff-dump.md` |
| X bundle identity | `Payload/X.app/Info.plist` (extracted) |

---

*End of report.*
