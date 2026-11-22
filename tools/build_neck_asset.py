"""Build an avatar-based neck headshot package.

The device does not accept the `cache_res` hotfix; only `assetindexer` patches
take effect. The hit classifier in `assetindexer` reads the serialized bone
name, so renaming the neck bone to the head bone makes a neck hit register as
a headshot. This is the same mechanism the old `HS KOKA` package used for the
hips (`bone_Hips` -> `bone_Head`), applied to `bone_Neck` instead.

The base is the 46,096 B hot-update build exported from this device, which is
the size of all five `assetindexer.*` files in the log. The package writes that
blob verbatim: diffing a bone-name rename is fragile because the edit is
inside the name, not in the float triple before it.

Run:  python tools/build_neck_asset.py
"""

import base64
import gzip
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_avatar_3105 import OUT, build_payload, open_package, seal  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(
    ROOT, "Discord", "Discord", "Patches", "asset_avatar_base_device.raw"
)
NAME = "aimneck_neck_asset"
DISPLAY = "HS Qafa (Asset)"
SOURCE = "asset_neck.raw"

OLD = b"bone_Neck"
NEW = b"bone_Head"
DESTINATION = (
    "Data/Raw/ios/gameassetbundles/avatar/"
    "assetindexer.tdn~2F53YNFWXQZyPdFl8HWBBwtXk~3D"
)
RULES = [
    (SOURCE, DESTINATION),
    (SOURCE + ".tmp", DESTINATION + ".raw.tmp"),
]


def patch(base):
    assert len(OLD) == len(NEW), "rename must be same length"
    count = base.count(OLD)
    if count != 2:
        raise SystemExit(f"expected 2 bone_Neck fields, found {count}")
    return base.replace(OLD, NEW)


def main():
    base = open(BASE, "rb").read()
    if len(base) != 46096:
        raise SystemExit(f"unexpected avatar base: {len(base)} B")
    raw = patch(base)

    # The engine writes `SOURCE` verbatim and skips `.tmp` rules whose exact
    # destination is absent, so only the single avatar rule is applied.
    packed = {SOURCE: raw}
    payload = build_payload(
        DISPLAY,
        packed,
        [(SOURCE, DESTINATION)],
        meta={"rawLength": len(raw), "compressed": False},
    )

    os.makedirs(OUT, exist_ok=True)
    destination = os.path.join(OUT, NAME + ".3105")
    with open(destination, "wb") as handle:
        handle.write(seal(payload))

    decoded_root, decoded = open_package(open(destination, "rb").read())
    if decoded != packed:
        raise SystemExit("payload round-trip mismatch")
    if decoded[SOURCE] != raw:
        raise SystemExit("asset round-trip mismatch")
    again = patch(base)
    if again != raw:
        raise SystemExit("rename is not idempotent")

    def b64(data):
        return base64.b64encode(hashlib.sha1(data).digest()).decode()

    print(
        f"{destination}: {os.path.getsize(destination)} B\n"
        f"  raw   {len(raw)} B  sha1b64 {b64(raw)}\n"
        f"  gzip  {len(gzip.compress(raw, compresslevel=9, mtime=0))} B\n"
        f"  bone_Neck {base.count(OLD)} -> {raw.count(OLD)}"
        f", bone_Head {base.count(NEW)} -> {raw.count(NEW)}"
    )


if __name__ == "__main__":
    main()
