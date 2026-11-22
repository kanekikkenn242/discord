import binascii
import os

PATHS = [
    r"Discord/Discord/Patches/asset_avatar_base.raw",
    r"C:/Users/User/Desktop/ASSETS/assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D.bin",
    r"C:/Users/User/Desktop/ASSETS/assetindexer.A7HkEH0xXRB6iX0xJ3D3c2SJMNw~3D",
    r"C:/Users/User/Desktop/ASSETS/assetindexer.A7HkEH0xXRB6iX0xJ3D3c2SJMNw~3D",
]

for path in PATHS:
    if not os.path.exists(path):
        print("missing", path)
        continue
    data = open(path, "rb").read()
    print(os.path.basename(path), len(data))
    print("  head ", binascii.hexlify(data[:48]).decode())
    print("  ascii", data[:40])
