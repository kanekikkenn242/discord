import re

PATHS = [
    r"Discord/Discord/Patches/asset_avatar_base.raw",
    r"C:/Users/User/Desktop/ASSETS/assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D.bin",
    r"C:/Users/User/Desktop/ASSETS/assetindexer.A7HkEH0xXRB6iX0xJ3D3c2SJMNw~3D",
]

for path in PATHS:
    data = open(path, "rb").read()
    heads = [m.start() for m in re.finditer(b"bone_Head", data)]
    necks = [m.start() for m in re.finditer(b"bone_Neck", data)]
    names = sorted({m.group(0).decode() for m in re.finditer(rb"bone_[A-Za-z0-9_]{1,24}", data)})
    print(path.split("/")[-1], len(data), "heads", heads, "necks", necks, "distinct names", len(names))
    nine = [n for n in names if len(n) == 9]
    print("   9-byte names:", nine)
