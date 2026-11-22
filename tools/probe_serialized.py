import binascii
import struct

PATHS = [
    (r"Discord/Discord/Patches/asset_avatar_base.raw", 128),
    (r"C:/Users/User/Desktop/ASSETS/assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D.bin", 128),
]

for path, start in PATHS:
    data = open(path, "rb").read()
    payload = data[start:]
    print("==", path.split("/")[-1], "file", len(data), "payload", len(payload))
    meta, fsize, ver, doff = struct.unpack_from(">IIII", payload, 0)
    print(f"   metadataSize={meta} fileSize={fsize} version={ver} dataOffset={doff}")
    print("   header hex", binascii.hexlify(payload[:32]).decode())
    meta_start = fsize - meta
    print(f"   metadata at {meta_start}")
    print("   meta head hex", binascii.hexlify(payload[meta_start:meta_start + 64]).decode())
    print("   meta head asc", payload[meta_start:meta_start + 64])
    print("   tail hex", binascii.hexlify(payload[-96:]).decode())
    print("   tail asc", payload[-96:])
