import struct
import sys

paths = [
    r"C:/Users/User/Desktop/ASSETS/assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D.bin",
    r"Discord/Discord/Patches/asset_avatar_base.raw",
]

for path in paths:
    data = open(path, "rb").read()
    print("==", path.split("/")[-1], len(data))
    for name in (b"bone_Head", b"bone_Hips", b"bone_Neck", b"bone_Root", b"bone_Hips_Dummy"):
        needle = struct.pack("<i", len(name)) + name
        hits = []
        start = 0
        while True:
            index = data.find(needle, start)
            if index < 0:
                break
            hits.append(index)
            start = index + 1
        print(f"   {name.decode():16s} len-prefixed at {hits}")
