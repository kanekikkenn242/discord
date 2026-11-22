"""Build aimneck_hs.3105 from the avatar bundle this device actually loads.

The reference aimneck asset differs from the vanilla rigs only in bone names:

    male   umaBones[0]             bone_Head  -> bone_Neck
    female umaBones[0]             bone_Head  -> bone_Neck
    male   bone_Hips_Dummy         -> bone_Head
    female bone_Left_Spine_*       -> bone_Head (+ scale)

The game looks a bone up by its serialized name, so moving the name onto a
torso bone is what turns body hits into headshots; renaming the head alone
leaves no `bone_Head` behind at all.

Names of different lengths shift the payload and the serialized object table,
which cannot be expressed as a same-size byte edit. The rig does however carry
a nine-byte pelvis bone (`bone_Hips`) in each rig, and `bone_Neck` is nine
bytes too, so the decoys here are:

    bone_Head -> bone_Neck   (head bone stops being the head)
    bone_Hips -> bone_Head   (pelvis becomes the head volume, centre mass)

Same lengths, same file size (46,096 B on this build), so the package applies
and restores as a plain byte edit.
"""

import gzip
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_avatar_3105 import (  # noqa: E402
    LEAF,
    OUT,
    SRC,
    build_payload,
    gz,
    open_package,
    seal,
)

NAME = "aimneck_hs"
DISPLAY = "HS KOKA"
DEVICE_PATH = os.path.join(SRC, "asset_avatar_device.raw")
DEVICE_SIZE = 46096
DEVICE_SHA256_PREFIX = "26dcf2e2c7a44ea7"

# Length-prefixed name slots: (start of the i32 length, current name).
HEAD = b"bone_Head"
NECK = b"bone_Neck"
HIPS = b"bone_Hips"

HEAD_SLOTS = (28508, 41544)
HIPS_SLOTS = (31092, 43844)

AVATAR_RULES = [
    ("mod_asset.tdn", LEAF),
    ("mod_asset.raw", LEAF + ".raw.tmp"),
]


def device_bytes():
    data = open(DEVICE_PATH, "rb").read()
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != DEVICE_SIZE or not digest.startswith(DEVICE_SHA256_PREFIX):
        raise SystemExit(f"device asset changed: {len(data)} bytes, sha256 {digest}")
    return data


def rename(raw, slot, expected, replacement):
    if len(expected) != len(replacement) or len(expected) != 9:
        raise SystemExit("replacement must keep the nine-byte name length")
    stored = struct.unpack_from("<i", raw, slot)[0]
    text = bytes(raw[slot + 4:slot + 4 + stored])
    if text != expected:
        raise SystemExit(f"slot {slot} holds {text!r}, expected {expected!r}")
    raw[slot + 4:slot + 4 + len(replacement)] = replacement


def build_raw(base):
    raw = bytearray(base)
    for slot in HEAD_SLOTS:
        rename(raw, slot, HEAD, NECK)
    for slot in HIPS_SLOTS:
        rename(raw, slot, HIPS, HEAD)
    return bytes(raw)


def verify(raw, base):
    if len(raw) != len(base):
        raise SystemExit("patched asset changed size")
    for slot in HEAD_SLOTS:
        assert bytes(raw[slot + 4:slot + 13]) == NECK, slot
    for slot in HIPS_SLOTS:
        assert bytes(raw[slot + 4:slot + 13]) == HEAD, slot
    changed = sum(1 for a, b in zip(base, raw) if a != b)
    assert changed == 12, changed
    return changed


def main():
    base = device_bytes()
    raw = build_raw(base)
    changed = verify(raw, base)
    print(f"{NAME}: {changed} byte(s) differ, size {len(raw)}")

    files = {"mod_asset.tdn": gz(raw), "mod_asset.raw": raw}
    payload = build_payload(DISPLAY, files, AVATAR_RULES)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, NAME + ".3105")
    with open(path, "wb") as handle:
        handle.write(seal(payload))

    root, decoded = open_package(open(path, "rb").read())
    assert decoded == files, "payload round-trip mismatch"
    assert gzip.decompress(decoded["mod_asset.tdn"]) == raw, "gzip mismatch"
    print(
        f"{path}: {os.path.getsize(path)} B, "
        f"raw sha256 {hashlib.sha256(raw).hexdigest()[:16]}, "
        f"rules {len(root['rules'])}"
    )


if __name__ == "__main__":
    main()
