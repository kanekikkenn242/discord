"""Rebuild the cache_res aim-neck package with a capsule that reaches the neck.

The bundle carries 37 `HitDetectColliderHelper` objects:

    bone_Head        type 1 (HEAD)      x2
    bone_Spine1      type 2 (TORSO)     x2
    bone_Spine       type 2             x2
    bone_Hips        type 2             x1
    bone_Hips_Dummy  type 2             x1
    limbs            type 3             x26
    sniper capsule   type 13            x1

There is no `bone_Neck` helper, so a neck headshot cannot be a type flip: the
head capsule has to cover the neck volume. The stock package grows the head
capsule but keeps it centred on the skull (male centre.x = -0.0402,
height = 0.150), so a shot at the neck still misses the volume.

The capsule's local X axis points down the body, so the fix is to lengthen it
along -X and move the centre down. The edit is a same-size float write, which
keeps the UnityFS block table and object table valid.

Run:  python tools/build_neck_cache.py
"""

import gzip
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_avatar_3105 import OUT, build_payload, open_package, seal  # noqa: E402

SOURCE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Discord", "Discord", "Patches", "aimneck_cache.3105",
)
NAME = "aimneck_neck"
DISPLAY = "HS Qafa"

# The two bone_Head CapsuleCollider objects share this raw layout:
#   +44  m_Radius   float32
#   +48  m_Height   float32
#   +52  m_Direction int32
#   +56  m_Center.x float32
#   +60  m_Center.y float32
#   +64  m_Center.z float32
RADIUS_OFFSET = 44
HEIGHT_OFFSET = 48
CENTER_X_OFFSET = 56

# The stock capsule spans local X [-0.115, +0.035]. The neck sits at
# head-local x ≈ -0.24 (y ≈ 0.07–0.10), just below the skull. A 0.28 total
# height centred at -0.105 spans [-0.245, +0.035], so the neck falls inside the
# cylinder instead of only inside the end cap, and a 0.105 radius clears its
# offset from the capsule axis without swallowing the chest.
NECK_RADIUS = 0.105
NECK_HEIGHT = 0.280
NECK_CENTER_X = -0.105

RULES = [
    ("cache_res_mod.bin", "Data/Raw/ios/gameassetbundles/cache_res.{gz}"),
    ("cache_res_raw.bin", "Data/Raw/ios/gameassetbundles/cache_res.{gz}.raw.tmp"),
]


def head_capsule_offsets(raw):
    """Absolute offsets of the two bone_Head CapsuleCollider raw blocks."""
    import UnityPy

    path = os.path.join(
        os.environ.get("TEMP", "."), "opencode", "ffcache", "aimneck_cache_cache_res_raw.bin"
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(raw)

    env = UnityPy.load(path)
    objects = {obj.path_id: obj for obj in env.objects}

    def game_object_name(path_id):
        obj = objects.get(path_id)
        if obj is None:
            return None
        return obj.read_typetree().get("m_Name")

    offsets = []
    for obj in env.objects:
        if obj.type.name != "CapsuleCollider":
            continue
        tree = obj.read_typetree()
        name = game_object_name((tree.get("m_GameObject") or {}).get("m_PathID"))
        if name != "bone_Head":
            continue
        block = obj.get_raw_data()
        at = raw.find(block)
        if at < 0:
            raise SystemExit("head capsule block is not in the bundle")
        if raw.find(block, at + 1) >= 0:
            raise SystemExit("head capsule block is not unique")
        offsets.append(at)
    if len(offsets) != 2:
        raise SystemExit(f"expected 2 bone_Head capsules, found {len(offsets)}")
    return sorted(offsets)


def patch(raw):
    data = bytearray(raw)
    for at in head_capsule_offsets(raw):
        struct.pack_into("<f", data, at + RADIUS_OFFSET, NECK_RADIUS)
        struct.pack_into("<f", data, at + HEIGHT_OFFSET, NECK_HEIGHT)
        struct.pack_into("<f", data, at + CENTER_X_OFFSET, NECK_CENTER_X)
    return bytes(data)


def verify(raw):
    import UnityPy

    path = os.path.join(
        os.environ.get("TEMP", "."), "opencode", "ffcache", "aimneck_neck_verify.bin"
    )
    with open(path, "wb") as handle:
        handle.write(raw)
    env = UnityPy.load(path)
    objects = {obj.path_id: obj for obj in env.objects}
    seen = 0
    for obj in env.objects:
        if obj.type.name != "CapsuleCollider":
            continue
        tree = obj.read_typetree()
        go = objects.get((tree.get("m_GameObject") or {}).get("m_PathID"))
        if go is None or go.read_typetree().get("m_Name") != "bone_Head":
            continue
        radius = tree["m_Radius"]
        height = tree["m_Height"]
        center_x = tree["m_Center"]["x"]
        print(
            f"  bone_Head capsule: r={radius:.6f} h={height:.6f} "
            f"center.x={center_x:.6f}"
        )
        if abs(radius - NECK_RADIUS) > 1e-5:
            raise SystemExit("radius did not land")
        if abs(height - NECK_HEIGHT) > 1e-5:
            raise SystemExit("height did not land")
        if abs(center_x - NECK_CENTER_X) > 1e-5:
            raise SystemExit("center did not land")
        seen += 1
    if seen != 2:
        raise SystemExit(f"verified {seen} capsules, expected 2")


def main():
    root, files = open_package(open(SOURCE, "rb").read())
    raw = files["cache_res_raw.bin"]
    if len(raw) != 63083 or not raw.startswith(b"UnityFS"):
        raise SystemExit(f"unexpected cache_res raw: {len(raw)} B")

    patched = patch(raw)
    changed = sum(1 for a, b in zip(raw, patched) if a != b)
    print(f"{NAME}: {changed} byte(s) differ, {len(patched)} B")
    verify(patched)

    packed = {
        "cache_res_mod.bin": gzip.compress(patched, compresslevel=9, mtime=0),
        "cache_res_raw.bin": patched,
    }
    payload = build_payload(
        DISPLAY,
        packed,
        RULES,
        meta={"rawLength": len(patched), "compressed": True},
    )

    os.makedirs(OUT, exist_ok=True)
    destination = os.path.join(OUT, NAME + ".3105")
    with open(destination, "wb") as handle:
        handle.write(seal(payload))

    decoded_root, decoded = open_package(open(destination, "rb").read())
    if decoded != packed:
        raise SystemExit("payload round-trip mismatch")
    if gzip.decompress(decoded["cache_res_mod.bin"]) != patched:
        raise SystemExit("gzip round-trip mismatch")

    print(
        f"{destination}: {os.path.getsize(destination)} B\n"
        f"  raw   {len(patched)} B  sha1b64 {_b64(patched)}\n"
        f"  gzip  {len(packed['cache_res_mod.bin'])} B  sha1b64 {_b64(packed['cache_res_mod.bin'])}"
    )


def _b64(data):
    import base64

    return base64.b64encode(hashlib.sha1(data).digest()).decode()


if __name__ == "__main__":
    main()
