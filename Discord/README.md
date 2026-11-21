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

Requirements: Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen),
or no Mac at all: `.github/workflows/build.yml` builds an unsigned IPA on a
`macos-15` runner and ad-hoc signs it with `Discord.entitlements`, so the App
Group survives packaging.

Two signing routes, pick one:

- **Free (iOS 26.0–27.3):** normal bundle id + App Group, installed with
  SideStore / AltStore / Impactor. Uses `worse_query`, no certificate to buy.
- **Paid / enterprise (iOS ≤26):** bundle id `com.apple.mobile.MobileHouseArrest`
  kept intact, uses the MCM / House Arrest identity.

3uTools and LiveContainer guests are not supported: they drop the entitlements
both routes need.

Install route matters because the engine addresses MobileContainerManager with
the identity `com.apple.mobile.MobileHouseArrest`. That identifier must survive
signing:

| Route | Identity kept | Notes |
|---|---|---|
| Xcode + enterprise/in-house cert (wildcard profile) | yes | the supported route |
| eSign / Feather / GBox with a shared enterprise cert | usually | check the profile is a wildcard (`*`) app id |
| eSign / SideStore / AltStore / Sideloadly with a personal Apple ID | no | the portal cannot register a `com.apple.*` app id, so the signer rewrites it and MCM returns `signed as … , MCM identity … required` |
| TrollStore | yes | only iOS 14.0–16.6.1, 16.7 RC, 17.0; not 18/26/27 |

### Free route: App Group (`worse_query`), iOS 26.0–27.3

A personal Apple ID cannot keep the `com.apple.mobile.MobileHouseArrest`
identity, but it does not have to. `worse_query` (forcequitOS, November 2026)
is a userland MobileContainerManager escape with no kernel component: any app
holding an App Group entitlement replaces its group's `Library/Caches` with a
symlink to a foreign container and asks `containermanagerd` for that part. The
daemon resolves the symlink and mints a `com.apple.app-sandbox.read-write`
extension for the target without checking that it is still inside the
container.

That is the third backend, after MCM/kernel and pairing:

1. Change `PRODUCT_BUNDLE_IDENTIFIER` to a normal id (anything not
   `com.apple.*`), e.g. `com.zada.discord`. `Info.plist` reads the same build
   setting, so one edit covers both identifiers.
2. Keep `Discord/Discord.entitlements`; it declares
   `group.com.zada.discord`. AltStore, SideStore and Impactor create the App
   Group under your free Apple ID automatically, Sideloadly cannot (a wildcard
   App ID carries no group).
3. Install with the free signing route and open a patch. The engine scans the
   data containers by inode, grants itself a token for each candidate, and
   stops at the one that reports `com.dts.freefireth` through its container
   metadata, its `com.apple.containermanager.identifier` xattr, or the game's
   own `Library/Preferences/<bundle id>.plist`. The match is cached in
   `UserDefaults`, so only the first scan is slow.

Limits: it reaches data containers only — `/var/containers/Bundle/Application`
stays out of reach, so a patch must live under `Documents/` rather than inside
the `.app`. The group swap is restored after every probe, and an interrupted
swap is recovered on the next launch. Verified by its author on iOS 26.0–26.7.2
and 27.0–27.2, still working on 27.2.1 and 27.3 beta 1; Apple has no advisory
for it. This route does **not** grant kernel read/write or root.

When the container lookup fails the patch error now ends with
`Container check: <MCM detail> [app id <bundle id>]`, which names the exact
identity the build was installed with.

```bash
cd Discord
xcodegen generate
open Discord.xcodeproj
```

Set your signing team, choose a physical arm64 device, and build. The
`AirliftFFI` xcframework is linked statically. `PRODUCT_BUNDLE_IDENTIFIER` is
`com.zada.discord` for the free App Group route; `Info.plist` reads the same
build setting, so there is one place to change. For the paid route set it back
to `com.apple.mobile.MobileHouseArrest`, which is what the MCM identity check
looks for.

The simulator builds for UI work. The kernel route is disabled there; the
`--simulate-access` launch argument makes `KernelExploit.hasSandboxAccess()`
report true for layout testing.

> This tree was authored on Windows, so the project has not been compiled by
> Xcode in this environment. The Swift code was written against the checked-in
> engine signatures and the C headers; run `xcodegen generate` and build on a
> Mac to catch any SDK-level mismatch.

## Packages

The three avatar products are checked in under `Discord/Patches/` and ship as
bundle resources, so their cards (`aimbot_drag`, `aimdrag_neck`, `aimneck_90`)
are ready right after install. The three cache products are not checked in and
will show `Package missing`; drop them into `Documents/Patches/` (Files/iTunes
file sharing) or import them with the Game tab's import button. The catalogue
resolves `Documents/Patches` first, then `Documents`, then the bundle.

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
