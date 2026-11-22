"""Minimal UnityFS reader: header, blocksInfo, blocks, serialized object table."""

import binascii
import os
import struct
import sys

from UnityPy.helpers import CompressionHelper


def read_cstr(buf, pos):
    end = buf.index(b"\0", pos)
    return buf[pos:end].decode("utf8", "replace"), end + 1


def parse(path):
    data = open(path, "rb").read()
    pos = 0
    magic = data[:8]
    pos = 8
    version = struct.unpack_from(">I", data, pos)[0]
    pos += 4
    unity_version, pos = read_cstr(data, pos)
    unity_revision, pos = read_cstr(data, pos)
    size = struct.unpack_from(">q", data, pos)[0]
    pos += 8
    ci_size = struct.unpack_from(">I", data, pos)[0]
    pos += 4
    ui_size = struct.unpack_from(">I", data, pos)[0]
    pos += 4
    flags = struct.unpack_from(">I", data, pos)[0]
    pos += 4
    pos = (pos + 15) // 16 * 16

    print(f"== {os.path.basename(path)} ({len(data)} B)")
    print(f"   magic={magic} version={version} unity={unity_version} {unity_revision}")
    print(f"   size={size} blocksInfo {ci_size}/{ui_size} flags=0x{flags:08x}")
    print(f"   compressed={flags & 0x3F} encrypted={bool(flags & 0x40)} at_end={bool(flags & 0x80)}")

    info_start = pos
    if flags & 0x80:
        info_start = len(data) - ci_size
    block_info_raw = data[info_start:info_start + ci_size]
    block_info = CompressionHelper.decompress(block_info_raw, flags & 0x3F, ui_size)
    print(f"   blocksInfo at {info_start}, first bytes {binascii.hexlify(block_info[:32]).decode()}")

    hash16 = block_info[:16]
    count = struct.unpack_from(">i", block_info, 16)[0]
    print(f"   blocksInfo hash {binascii.hexlify(hash16).decode()} blocks={count}")
    if not (0 < count < 64):
        print("   !! implausible block count — blocksInfo is encrypted")
        return

    entries = []
    off = 20
    for _ in range(count):
        u, c, f = struct.unpack_from(">IIH", block_info, off)
        off += 10
        entries.append((u, c, f))
        print(f"     block u={u} c={c} flags=0x{f:04x}")

    data_start = info_start + ci_size
    data_start = (data_start + 15) // 16 * 16
    print(f"   data at {data_start}")

    payload = bytearray()
    cursor = data_start
    for u, c, f in entries:
        chunk = data[cursor:cursor + c]
        cursor += c
        payload += CompressionHelper.decompress(chunk, f & 0x3F, u)
    print(f"   payload {len(payload)} B, head {binascii.hexlify(payload[:32]).decode()}")
    open(path + ".serialized.bin", "wb").write(bytes(payload))
    return bytes(payload)


def serialized_header(payload, label):
    if len(payload) < 20:
        return
    meta_size, file_size, ver, data_off = struct.unpack_from(">IIII", payload, 0)
    print(f"   [{label}] metadata={meta_size} fileSize={file_size} version={ver} dataOffset={data_off}")
    if ver >= 22:
        data_off = struct.unpack_from(">I", payload, 20)[0] - meta_size + 48  # rough
    return meta_size, file_size, ver, data_off


if __name__ == "__main__":
    for p in sys.argv[1:]:
        payload = parse(p)
        if payload:
            write = p + ".serialized.bin"
            print(f"   serialized saved -> {os.path.basename(write)}")
            serialized_header(payload, "big-endian?")
            serialized_header(struct.unpack("<IIII", payload[:16]) and payload, "le") if False else None
