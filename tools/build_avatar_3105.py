"""Build avatar-only .3105 packages (assetindexer.tdn + .raw.tmp).

The avatar asset is a 46,640-byte serialized Unity blob. The packages only
change three float32 local-scale vectors per rig (male/female x Head, Spine1,
Neck). Everything else stays byte-identical to the base asset.

Envelope format (matches Discord/Discord/engine/PatchPackage.swift):
  0    4   magic "3105"
  4    4   u32 version (1)
  8   16   PBKDF2 salt
  24   4   u32 PBKDF2 iterations
  28   4   u32 wrapped key length (32)
  32  32   AES-GCM wrapped content key (ciphertext)
  64  12   wrap nonce
  76  16   wrap tag
  92  12   payload nonce
  104 16   payload tag
  120  8   u64 ciphertext length
  128 ..   payload ciphertext
"""

import base64
import gzip
import hashlib
import json
import os
import secrets
import struct

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "patches", "src")
OUT = os.path.join(ROOT, "patches")

BASE_PATH = os.path.join(SRC, "asset_avatar_base.raw")
PASSWORD = "shared-server-secret"
ITERATIONS = 120_000
HEADER_SIZE = 128
LEAF = "Data/Raw/ios/gameassetbundles/avatar/assetindexer.tdn~2F53YNFWXQZyPdFl8HWBBwtXk~3D"

SCALE_OFFSETS = {
    "male": {"Head": 0x6F50, "Spine1": 0x7020, "Neck": 0x7658},
    "female": {"Head": 0xA454, "Spine1": 0xA494, "Neck": 0xAA88},
}

# name -> (display name, head, spine1, neck)
# Head and neck are relabelled to the same field at apply time, so the head
# volume has to cover the neck and the band around it (roughly 5 cm left,
# right and above). Both profiles therefore use a large head and neck scale.
SCALE_VARIANTS = {
    "aimbot_drag": ("Aim Cuello", 10.0, 5.0, 10.0),
    "aimdrag_neck": ("Aim Cuello + Antena", 25.0, 10.0, 25.0),
}

# aimneck_90: two unrelated serialized slots 1.0 -> 211.0
AIMNECK_90_FLOATS = {"name": "Aim Drag Neck", "offsets": (0x6AFC, 0xA040), "value": 211.0}


def base_bytes():
    data = open(BASE_PATH, "rb").read()
    digest = hashlib.sha256(data).hexdigest()
    expected = "e29b31619db60ad098bb150833b5f9ee7cf8751f12ea33cf442c017a91aa5915"
    if len(data) != 46640 or digest != expected:
        raise SystemExit(f"base asset changed: {len(data)} bytes, sha256 {digest}")
    return data


def raw_with_scales(base, head, spine1, neck):
    raw = bytearray(base)
    for rig, offsets in SCALE_OFFSETS.items():
        struct.pack_into("<fff", raw, offsets["Head"], head, head, head)
        struct.pack_into("<fff", raw, offsets["Spine1"], spine1, spine1, spine1)
        struct.pack_into("<fff", raw, offsets["Neck"], neck, neck, neck)
    return bytes(raw)


def raw_with_floats(base, offsets, value):
    raw = bytearray(base)
    for offset in offsets:
        struct.pack_into("<f", raw, offset, value)
    return bytes(raw)


def gz(data):
    return gzip.compress(data, compresslevel=9, mtime=0)


def aesgcm_seal(key, plaintext):
    nonce = secrets.token_bytes(12)
    blob = AESGCM(key).encrypt(nonce, plaintext, None)
    return nonce, blob[:-16], blob[-16:]


def seal(payload):
    salt = secrets.token_bytes(16)
    kek = hashlib.pbkdf2_hmac("sha256", PASSWORD.encode(), salt, ITERATIONS, 32)
    content_key = secrets.token_bytes(32)
    wrap_nonce, wrapped_key, wrap_tag = aesgcm_seal(kek, content_key)
    payload_nonce, ciphertext, payload_tag = aesgcm_seal(content_key, payload)

    header = bytearray(HEADER_SIZE)
    header[0:4] = b"3105"
    struct.pack_into("<I", header, 4, 1)
    header[8:24] = salt
    struct.pack_into("<I", header, 24, ITERATIONS)
    struct.pack_into("<I", header, 28, 32)
    header[32:64] = wrapped_key
    header[64:76] = wrap_nonce
    header[76:92] = wrap_tag
    header[92:104] = payload_nonce
    header[104:120] = payload_tag
    struct.pack_into("<Q", header, 120, len(ciphertext))
    return bytes(header) + ciphertext


def build_payload(meta_name, files, rules):
    digests = {name: hashlib.sha256(blob).hexdigest() for name, blob in files.items()}
    body = {
        "files": {name: base64.b64encode(blob).decode() for name, blob in files.items()},
        "rules": [{"src": src, "dst": dst} for src, dst in rules],
        "digests": digests,
        "meta": {"name": meta_name},
    }
    return json.dumps(body, ensure_ascii=False).encode()


# ---- independent reader, used only to verify what we just wrote ----------


def open_package(blob):
    assert blob[0:4] == b"3105", "bad magic"
    version, = struct.unpack_from("<I", blob, 4)
    assert version == 1, version
    salt = blob[8:24]
    iterations, = struct.unpack_from("<I", blob, 24)
    key_len, = struct.unpack_from("<I", blob, 28)
    assert key_len == 32
    wrapped = blob[32:64]
    wrap_nonce = blob[64:76]
    wrap_tag = blob[76:92]
    payload_nonce = blob[92:104]
    payload_tag = blob[104:120]
    length, = struct.unpack_from("<Q", blob, 120)
    cipher = blob[128:128 + length]
    assert len(blob) == HEADER_SIZE + length, "size mismatch"
    kek = hashlib.pbkdf2_hmac("sha256", PASSWORD.encode(), salt, iterations, 32)
    key = AESGCM(kek).decrypt(wrap_nonce, wrapped + wrap_tag, None)
    plain = AESGCM(key).decrypt(payload_nonce, cipher + payload_tag, None)
    root = json.loads(plain)
    files = {name: base64.b64decode(value) for name, value in root["files"].items()}
    for rule in root["rules"]:
        digest = root["digests"][rule["src"]]
        assert hashlib.sha256(files[rule["src"]]).hexdigest() == digest
    return root, files


def main():
    os.makedirs(SRC, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    base = base_bytes()

    avatar_rules = [
        ("mod_asset.tdn", LEAF),
        ("mod_asset.raw", LEAF + ".raw.tmp"),
    ]

    outputs = {}

    for name, (display, head, spine1, neck) in SCALE_VARIANTS.items():
        raw = raw_with_scales(base, head, spine1, neck)
        files = {"mod_asset.tdn": gz(raw), "mod_asset.raw": raw}
        outputs[name] = (display, files, avatar_rules, raw)

    raw = raw_with_floats(base, AIMNECK_90_FLOATS["offsets"], AIMNECK_90_FLOATS["value"])
    # The raw blob is part of every package: the hot-update tree stores the
    # asset uncompressed, so the engine needs the raw form to patch it in place.
    files = {"mod_asset.tdn": gz(raw), "mod_asset.raw": raw}
    outputs["aimneck_90"] = (
        AIMNECK_90_FLOATS["name"],
        files,
        avatar_rules,
        raw,
    )

    for name, (display, files, rules, raw) in outputs.items():
        payload = build_payload(display, files, rules)
        path = os.path.join(OUT, name + ".3105")
        with open(path, "wb") as handle:
            handle.write(seal(payload))

        root, decoded = open_package(open(path, "rb").read())
        assert decoded == files, f"{name}: payload round-trip mismatch"
        assert gzip.decompress(decoded["mod_asset.tdn"]) == raw, f"{name}: gzip mismatch"
        print(
            f"{name:14s} {os.path.getsize(path):6d} B  "
            f"raw {hashlib.sha256(raw).hexdigest()[:16]}  "
            f"tdn {len(decoded['mod_asset.tdn']):5d} B  "
            f"rules {len(root['rules'])}"
        )


if __name__ == "__main__":
    main()
