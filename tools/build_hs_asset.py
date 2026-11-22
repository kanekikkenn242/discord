"""Build aimneck_hs.3105 — the avatar asset with the head/neck names swapped.

The reference aimneck asset (2018.4.11f1, seen in Desktop/ASSETS) differs from
the vanilla BaseBone rigs only in bone names:

    male   umaBones[0]  bone_Head        -> bone_Neck
    female umaBones[0]  bone_Head        -> bone_Neck

Both strings are nine bytes, so the serialized offsets stay identical and the
existing anchored byte-diff engine can apply and restore the change.

The reference also moves the `bone_Head` name onto torso helper bones
(male Hips_Dummy, female Left_Spine_Backpack / Left_Spine_Weapon + scale 1.5).
Those names have different lengths (15/22/21 -> 9), which shift the payload and
the serialized object table, so they cannot be expressed as a same-size byte
edit; they are intentionally not written by this builder.
"""

import gzip
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_avatar_3105 import (  # noqa: E402
    BASE_PATH,
    HEADER_SIZE,
    LEAF,
    OUT,
    base_bytes,
    build_payload,
    gz,
    open_package,
    seal,
)

NAME = "aimneck_hs"
DISPLAY = "HS KOKA"
HEAD = b"bone_Head"
NECK = b"bone_Neck"

AVATAR_RULES = [
    ("mod_asset.tdn", LEAF),
    ("mod_asset.raw", LEAF + ".raw.tmp"),
]


class Reader:
    """Minimal reader for the UMAMeshAsset MonoBehaviour payload."""

    def __init__(self, data, offset=0):
        self.data = data
        self.o = offset

    def i32(self):
        value, = struct.unpack_from("<i", self.data, self.o)
        self.o += 4
        return value

    def i64(self):
        value, = struct.unpack_from("<q", self.data, self.o)
        self.o += 8
        return value

    def align(self):
        self.o = (self.o + 3) // 4 * 4

    def string(self):
        start = self.o
        length = self.i32()
        text = self.data[self.o:self.o + length]
        self.o += length
        self.align()
        return start, text


def payload_start(raw, marker):
    """The m_Name field sits 32 bytes into the MonoBehaviour payload."""
    position = raw.find(marker)
    if position < 0:
        raise SystemExit(f"{marker.decode()} not found")
    return position - 32


def bone_name_slots(raw, start, label):
    """Offsets of every bone name stored in the rig's umaBones table."""
    reader = Reader(raw, start)
    reader.i32()
    reader.i64()
    reader.o += 1
    reader.align()
    reader.i32()
    reader.i64()
    reader.string()
    reader.string()
    if reader.i32() != 0 or reader.i32() != 0:
        raise SystemExit(f"{label}: unexpected animated-bone tables")

    bind_poses = reader.i32()
    reader.o += bind_poses * 64
    for _ in range(12):
        if reader.i32() != 0:
            raise SystemExit(f"{label}: unexpected mesh array")

    bone_count = reader.i32()
    slots = []
    for index in range(bone_count):
        reader.o += 12 + 16 + 12  # position, rotation, scale
        start_of_string, text = reader.string()
        reader.i32()
        reader.i32()
        slots.append((index, start_of_string, text))
    return slots


def build_raw(base):
    raw = bytearray(base)
    changed = 0
    for marker in (b"BaseBoneMale_Mesh", b"BaseBoneFemale_Mesh"):
        start = payload_start(base, marker)
        slots = bone_name_slots(base, start, marker.decode())
        index, string_start, text = slots[0]
        if index != 0 or text != HEAD:
            raise SystemExit(f"{marker.decode()}: bone 0 is {text!r}, expected {HEAD!r}")
        # 4-byte length prefix, then the nine name bytes.
        raw[string_start + 4:string_start + 4 + len(HEAD)] = NECK
        changed += len(HEAD)
    return bytes(raw), changed


def verify(raw):
    for marker in (b"BaseBoneMale_Mesh", b"BaseBoneFemale_Mesh"):
        start = payload_start(raw, marker)
        slots = bone_name_slots(raw, start, marker.decode())
        assert slots[0][1] and slots[0][2] == NECK, slots[0]
        assert [name for _, _, name in slots].count(HEAD) == 0, marker
        assert [name for _, _, name in slots].count(NECK) == 2, marker


def main():
    base = base_bytes()
    raw, changed = build_raw(base)
    if len(raw) != len(base):
        raise SystemExit("patched asset changed size")
    verify(raw)

    diff = sum(1 for a, b in zip(base, raw) if a != b)
    print(f"{NAME}: {changed} byte(s) edited, {diff} byte(s) differ, size {len(raw)}")

    files = {"mod_asset.tdn": gz(raw), "mod_asset.raw": raw}
    payload = build_payload(DISPLAY, files, AVATAR_RULES)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, NAME + ".3105")
    with open(path, "wb") as handle:
        handle.write(seal(payload))

    root, decoded = open_package(open(path, "rb").read())
    assert decoded == files, "payload round-trip mismatch"
    assert gzip.decompress(decoded["mod_asset.tdn"]) == raw, "gzip mismatch"
    assert len(decoded["mod_asset.raw"]) == HEADER_SIZE * 0 + len(base)
    print(
        f"{path}: {os.path.getsize(path)} B, "
        f"raw sha256 {hashlib.sha256(raw).hexdigest()[:16]}, "
        f"rules {len(root['rules'])}"
    )


if __name__ == "__main__":
    main()
