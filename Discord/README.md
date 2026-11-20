# Discord

iOS rebuild of the zadaDMA / 3105 patch tool, branded **Discord**. The app is a
file patcher with a sandbox-access stack, not a memory cheat: it decrypts
`.3105` packages, writes their bytes over Free Fire's Unity assets, and keeps a
byte-exact original for every path so a toggle-off restores the pre-patch state.

## What is in the tree

```
Discord/
  project.yml                     XcodeGen project
  Discord/
    DiscordApp.swift              @main, launch phases, environment
    AppState.swift                language, appearance, game, activation, patch state
    PatchController.swift         apply/restore orchestration, slot conflict handling
    SoundPlayer.swift             splash / apply / restore cues
    Theme.swift                   tokens and shared controls
    Localization.swift            en / es / pt
    Info.plist                    Bonjour, URL scheme, .3105 document type
    Discord-Bridging-Header.h     airlift, MCM, kexploit, sandbox
    Views/
      SplashView.swift            ring splash + music prompt
      OnboardingView.swift        5 steps incl. iOS 27 build list
      HomeView.swift              device status, pairing, library
      GameView.swift              categories, cache/avatar tabs, toggles, log
      SettingsView.swift          pairing, exploit, verified versions, social
      ProfileView.swift           membership, game, notices, music
      SupportView.swift           support rows, live patch status
      Components.swift            patch card, log console, tab bar, ledger
    Resources/                    Welcome / activar / desactivar cues
    engine/                       existing patch engine (kept)
    exploit/                      MCM bridge, bad_query
    kexploit/                     kfd / kexploit_opa334, sandbox escape
  Vendor/AirliftFFI.xcframework   Rust pairing/AFC transport
```

## Screens

- **Splash** — orange progress ring, device model, music prompt, profile row.
- **Onboarding (5 steps)** — welcome, language, appearance + game, supported
  iOS builds (17 / 18 / 26 / 27), certificate requirements.
- **Home** — app header, selected game and backend pills, device status,
  pairing/tunnel card, package and original-backup counters.
- **Game** — the four-tab shell's centre tab: Aimbot / Hologram / Skin chips,
  Aimbot Cache / Aimbot Avatar segments, a live toggle per product, and the
  injection log. `AIM PECHO 70%` and `AIMBOT DRAG` are both here.
- **Profile** — membership card, local activation sheet, game selector,
  notices ledger, music toggle.
- **Support** — Discord/announcements links and a live loaded / not-loaded /
  unavailable patch summary.

Every `.3105` product is a toggle: the first enable captures a byte-exact
original, and turning the toggle off writes that original back. Only one
product per slot (avatar / cache) can be loaded at a time; enabling a second
one restores the first before the new bytes land.

## Build

Requirements: macOS with Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen),
and an enterprise certificate. SideStore / AltStore / 3uTools / LiveContainer
are not supported install routes — the app needs the entitlements those routes
do not provide.

```bash
cd Discord
xcodegen generate
open Discord.xcodeproj
```

Set your signing team, choose a physical arm64 device, and build. The
`AirliftFFI` xcframework is linked statically; the app bundle identifier is
`com.apple.mobile.MobileHouseArrest` to keep the House Arrest container
semantics the engine relies on. Change it only if your certificate cannot sign
that identifier, and keep the same value in `project.yml` and `Info.plist`.

The simulator builds for UI work. The kernel route is disabled there; the
`--simulate-access` launch argument makes `KernelExploit.hasSandboxAccess()`
report true for layout testing.

> This tree was authored on Windows, so the project has not been compiled by
> Xcode in this environment. The Swift code was written against the checked-in
> engine signatures and the C headers; run `xcodegen generate` and build on a
> Mac to catch any SDK-level mismatch.

## Packages

The six `.3105` products are not checked in, so a fresh install shows every
card as `Package missing` and the toggles stay disabled. Drop the packages into
the app's `Documents/Patches/` directory (visible through Files/iTunes file
sharing) or add them to the target as bundle resources under `Patches/`. The
catalogue resolves `Documents/Patches` first, then `Documents`, then the bundle.
The Game tab also has an import button for `.3105` files.

Catalogue mapping in `engine/FreeFireCatalog.swift`:

| Card | Package | Slot |
|---|---|---|
| AIMBOT DRAG | `aimbot_drag` | avatar |
| AIM NECK + ANTENNA | `aimdrag_neck` | avatar |
| AIM DRAG NECK | `aimneck_90` | avatar |
| AIM PECHO 70% | `aimneck_torso_cache` | cache |
| AIM NECK CACHE | `aimneck_cache` | cache |
| AIM TORSO | `aimtorso_cache` | cache |

`AIM PECHO 70%` is the panel label; the payload is `aimneck_torso_cache`
(head capsule enlargement plus six torso helpers). The `70%` string is not in
the package metadata.

## Access backends

`PatchRuntime.withFileSystem` tries, in order:

1. Local container through MCM (`ContainerStore` + `MCMActivateContainerPath`).
2. On-demand kernel exploit (`kexploit_opa334` → sandbox escape) when the build
   is in `ExploitSupportPolicy`.
3. Remote pairing: `AirliftTunnel` → pair-verify → TLS-PSK → RSD → House Arrest
   → AFC. Requires Developer Mode, a pairing file, and LocalDevVPN connected so
   the loopback endpoint is reachable.

The UI exposes all three: Settings → Kernel exploit, and Settings → Pairing &
Tunnel (start/stop, PIN, verify, import, LocalDevVPN, forget).

## Offsets

`../ff-offsets.json` and `../ff-dump.md` hold 64 IL2CPP field offsets imported
through `c!addos`. They are a memory-tool map, not part of this patcher; the
patcher edits serialized Unity objects (Transform local scale, CapsuleCollider
radius/height/center, `m_Enabled`, `ColliderType`). They are unstamped
(`"version": "importado"`) and must be re-derived per Free Fire build before
being trusted in a runtime tool.

## Analysis notes

- `Proxy 3.0.ipa` is unrecoverable: ~21 million `EF BF BD` replacement bytes and
  no usable ZIP central directory. Only the `Payload/InjectorApp.app/` filename
  tree survives.
- The six bundled packages decrypt with the shared password
  `shared-server-secret` (PBKDF2-HMAC-SHA256, 120,000 iterations, AES-256-GCM
  wrap + payload). Header is 128 bytes; magic `3105`; version 1.
- The restore ledger lives in `Application Support/Discord/ledger.jsonl`;
  originals live in `Application Support/Discord/originals/`.
