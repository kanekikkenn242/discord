"""Build a Kaneki-themed avatar bundle from dope's Alien-X avatar bundle.

The image generator was unavailable, so the UV maps are recoloured directly:
layout and alpha stay byte-compatible with the game's model, only the palette
changes (pale skin, white hair, black mask, red eyes).
Run:  python tools/build_kaneki_texture.py
"""

import io
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
import UnityPy  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
PAYLOADS = os.path.join(HERE, "dope_payloads")
TEMP = os.path.join(os.environ.get("TEMP", "."), "opencode", "kaneki_src")


def load_ref(name):
    return Image.open(os.path.join(GEN, name)).convert("RGBA")


def save_rgba(array, path):
    Image.fromarray(np.clip(array, 0, 255).astype(np.uint8), "RGBA").save(path)


def build_head():
    img = load_ref("ref_head.png")
    a = np.array(img).astype(np.float32)
    rgb = a[:, :, :3]
    lum = rgb.mean(axis=2)

    # Skin: pale, slightly cool, keep the original shading.
    skin = (lum > 105) & (rgb[:, :, 0] > rgb[:, :, 2] * 0.95)
    pale = np.stack([lum * 0.55 + 246 * 0.45,
                     lum * 0.50 + 242 * 0.50,
                     lum * 0.48 + 240 * 0.52], axis=2)
    rgb[skin] = pale[skin]

    # Black fabric mask over the beard / lower face, feathered at the edges.
    h, w = rgb.shape[:2]
    mask_layer = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask_layer)
    draw.polygon([(150, 243), (362, 243), (370, 296), (330, 345),
                  (256, 356), (182, 345), (146, 296)], fill=255)
    mask_layer = mask_layer.filter(ImageFilter.GaussianBlur(4))
    ma = np.array(mask_layer).astype(np.float32) / 255.0
    fabric = np.stack([lum * 0.10 + 14, lum * 0.10 + 14, lum * 0.10 + 18], axis=2)
    rgb = rgb * (1 - ma[:, :, None]) + fabric * ma[:, :, None]

    # Eyes at the bottom of this UV: recolour the dark iris to red while
    # keeping its original shape and the black pupil.
    yy, xx = np.ogrid[:h, :w]
    for cx, cy in ((88, 470), (424, 470)):
        dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        iris = (dist < 32) & (lum < 175)
        base = lum[iris]
        rgb[iris] = np.stack([base * 0.95 + 40,
                              base * 0.10,
                              base * 0.14], axis=1)

    a[:, :, :3] = rgb
    path = os.path.join(GEN, "kaneki_head.png")
    save_rgba(a, path)
    return path


def build_hair():
    img = load_ref("ref_hair.png")
    a = np.array(img).astype(np.float32)
    rgb = a[:, :, :3]
    lum = rgb.mean(axis=2)
    h, w = rgb.shape[:2]
    yy, xx = np.ogrid[:h, :w]
    hair_zone = yy < h * 0.55
    dark = lum < 145
    recolor = hair_zone & dark
    silver = np.stack([lum * 0.35 + 216,
                       lum * 0.35 + 220,
                       lum * 0.35 + 228], axis=2)
    rgb[recolor] = silver[recolor]
    a[:, :, :3] = rgb
    path = os.path.join(GEN, "kaneki_hair.png")
    save_rgba(a, path)
    return path


def build_body():
    img = load_ref("ref_body.png")
    a = np.array(img).astype(np.float32)
    rgb = a[:, :, :3]
    lum = rgb.mean(axis=2)

    skin = (lum > 95) & (rgb[:, :, 0] > rgb[:, :, 2] * 0.92)
    pale = np.stack([lum * 0.48 + 234 * 0.52,
                     lum * 0.44 + 232 * 0.56,
                     lum * 0.42 + 230 * 0.58], axis=2)
    rgb[skin] = pale[skin]
    # Keep the existing red tattoo but push it towards a deeper crimson.
    red = (rgb[:, :, 0] > rgb[:, :, 1] * 1.35) & (rgb[:, :, 0] > 70)
    rgb[red] = np.stack([rgb[red][:, 0] * 0.8 + 90,
                         rgb[red][:, 1] * 0.35,
                         rgb[red][:, 2] * 0.35], axis=1)
    a[:, :, :3] = rgb
    path = os.path.join(GEN, "kaneki_body.png")
    save_rgba(a, path)
    return path


def main():
    os.makedirs(GEN, exist_ok=True)
    head, hair, body = build_head(), build_hair(), build_body()

    os.makedirs(TEMP, exist_ok=True)
    src = os.path.join(PAYLOADS, "alienx")
    dst = os.path.join(PAYLOADS, "kaneki")
    with open(src, "rb") as handle:
        raw = handle.read()

    # UnityPy needs the real (declared) bundle length; dope pads the payload.
    import struct
    i = 12
    for _ in range(2):
        i = raw.index(b"\x00", i) + 1
    declared = struct.unpack(">q", raw[i:i + 8])[0]
    staged = os.path.join(TEMP, "alienx.bundle")
    with open(staged, "wb") as handle:
        handle.write(raw[:declared])

    replacements = {
        "Male_Head_Sc_DJmale_Awakening_D": head,
        "Male_Hairroot_Sc_Djmale_Awakening_D": hair,
        "Male_Sc_Djmale_Awakening_headphone_D": hair,
        "male_body_cos_desert_d": body,
    }
    env = UnityPy.load(staged)
    changed = []
    for obj in env.objects:
        if obj.type.name != "Texture2D":
            continue
        data = obj.read()
        name = getattr(data, "m_Name", "")
        if name in replacements:
            image = Image.open(replacements[name]).convert("RGBA")
            image = image.resize((data.m_Width, data.m_Height), Image.LANCZOS)
            data.set_image(image)
            data.save()
            changed.append(name)
    if not changed:
        raise SystemExit("no textures matched — aborting")
    outdir = os.path.join(TEMP, "kaneki_out")
    os.makedirs(outdir, exist_ok=True)
    env.save(pack="original", out_path=outdir)
    produced = [os.path.join(outdir, n) for n in os.listdir(outdir)
                if os.path.isfile(os.path.join(outdir, n))]
    if len(produced) != 1:
        raise SystemExit(f"expected one output bundle, got {produced}")
    with open(produced[0], "rb") as srcf, open(dst, "wb") as dstf:
        dstf.write(srcf.read())
    print("recoloured:", ", ".join(changed))
    print("bundle:", dst, os.path.getsize(dst), "B")

    check = UnityPy.load(dst)
    names = [getattr(o.read(), "m_Name", "") for o in check.objects
             if o.type.name == "AssetBundle"]
    print("internal bundle name:", names)


if __name__ == "__main__":
    main()
