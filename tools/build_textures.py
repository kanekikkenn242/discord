"""Package the four texture payloads used by the working dope injector.

The injector downloads these from https://dp2.shardweb.app/txt/<name>/<file>
and overwrites the optionalavatarres bundle in place:

    Documents/contentcache/Optional/ios/optionalavatarres/gameassetbundles/

`texture_*` sources are written verbatim by PatchService (writesInPlace), so
there is no rename and no fileinfo edit, exactly like the injector.

Run:  python tools/build_textures.py
"""

import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_avatar_3105 import OUT, build_payload, open_package, seal  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE_DIR = os.path.join(os.environ.get("TEMP", "."), "opencode", "dope_txt")
BUNDLE = "Data/Raw/ios/optionalavatarres/gameassetbundles/"

VARIANTS = [
    (
        "texture_sielzada",
        "sielzada",
        BUNDLE + "optionalab_avatar_62.o~2FELJ0~2BswGVk~2F~2BDPzjlpxie6x~2FA~3D",
    ),
    (
        "texture_mordecai",
        "mordecai",
        BUNDLE + "optionalab_avatar_66.1GZrX1l5Sm~2FgqXYqB7dDyULWdn4~3D",
    ),
    (
        "texture_aranha",
        "spider",
        BUNDLE + "optionalab_avatar_66.1GZrX1l5Sm~2FgqXYqB7dDyULWdn4~3D",
    ),
    (
        "texture_alienx",
        "alienx",
        BUNDLE + "optionalab_avatar_66.1GZrX1l5Sm~2FgqXYqB7dDyULWdn4~3D",
    ),
]


def main():
    for name, folder, destination in VARIANTS:
        source = name + ".raw"
        raw = open(os.path.join(SOURCE_DIR, folder), "rb").read()
        if not raw.startswith(b"UnityFS"):
            raise SystemExit(f"{name}: not a UnityFS bundle")

        payload = build_payload(
            name,
            {source: raw},
            [(source, destination)],
            meta={"rawLength": len(raw), "compressed": False},
        )
        out = os.path.join(OUT, name + ".3105")
        with open(out, "wb") as handle:
            handle.write(seal(payload))

        _, decoded = open_package(open(out, "rb").read())
        if decoded != {source: raw}:
            raise SystemExit(f"{out}: round-trip failed")
        print(
            f"{out}: {os.path.getsize(out)} B, raw={len(raw)}, "
            f"sha256={hashlib.sha256(raw).hexdigest()[:16]}"
        )


if __name__ == "__main__":
    main()
