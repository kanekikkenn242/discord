"""Package the headshot assetindexer variants used by the working injector.

`Payload-2/InjectorApp.app` (signed as com.apple.mobile.MobileHouseArrest)
downloads these from dp2.shardweb.app and writes them over:

    Documents/contentcache/Compulsory/ios/gameassetbundles/avatar/
        assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D

It never renames the file and never edits `fileinfo`. These packages do the
same: the raw blob is written in place by PatchService (see writesInPlace).

Run:  python tools/build_proxy_hs.py
"""

import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_avatar_3105 import OUT, build_payload, open_package, seal  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DESTINATION = (
    "Data/Raw/ios/gameassetbundles/avatar/"
    "assetindexer.tdn~2F53YNFWXQZyPdFl8HWBBwtXk~3D"
)

VARIANTS = [
    ("proxy_hs1", "HS 1 (Proxy)"),
    ("proxy_hs2", "HS 2 (Proxy)"),
    ("proxy_hs3", "HS 3 (Proxy)"),
]


def main():
    for name, display in VARIANTS:
        source = name + ".raw"
        path = os.path.join(HERE, "proxy_hs", name.removeprefix("proxy_") + ".bin")
        raw = open(path, "rb").read()
        if len(raw) != 46096:
            raise SystemExit(f"{path}: unexpected size {len(raw)}")

        payload = build_payload(
            display,
            {source: raw},
            [(source, DESTINATION)],
            meta={"rawLength": len(raw), "compressed": False},
        )
        out = os.path.join(OUT, name + ".3105")
        with open(out, "wb") as handle:
            handle.write(seal(payload))

        root, decoded = open_package(open(out, "rb").read())
        if decoded != {source: raw}:
            raise SystemExit(f"{out}: round-trip failed")
        print(
            f"{out}: {os.path.getsize(out)} B, "
            f"sha256={hashlib.sha256(raw).hexdigest()[:16]}"
        )


if __name__ == "__main__":
    main()
