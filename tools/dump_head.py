import binascii

path = r"C:/Users/User/Desktop/ASSETS/assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D.bin"
data = open(path, "rb").read()
for start in range(0, 240, 16):
    chunk = data[start:start + 16]
    print(f"{start:4d}  {binascii.hexlify(chunk).decode('latin1'):32s}  {chunk}")
