"""Build a Baji Keisuke (Tokyo Revengers) themed Avatar-66 bundle.

No Baji payload exists on dope's server, so the Alien-X UV maps are recoloured:
black hair + red headband, pale face, dark navy Toman-style uniform.
Run:  python tools/build_baji_texture.py
"""

import io
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
import UnityPy  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
PAYLOADS = os.path.join(HERE, "dope_payloads")
TEMP = os.path.join(os.environ.get("TEMP", "."), "opencode", "baji_src")


def load_ref(name):
    return Image.open(os.path.join(GEN, name)).convert("RGBA")


def save_rgba(array, path):
    Image.fromarray(np.clip(array, 0, 255).astype(np.uint8), "RGBA").save(path)


def build_head():
    a = np.array(load_ref("ref_head.png")).astype(np.float32)
    rgb = a[:, :, :3]
    lum = rgb.mean(axis=2)
    h, w = rgb.shape[:2]

    # Pale skin, preserving the original shading.
    skin = (lum > 105) & (rgb[:, :, 0] > rgb[:, :, 2] * 0.95)
    pale = np.stack([lum * 0.50 + 238 * 0.50,
                     lum * 0.46 + 234 * 0.54,
                     lum * 0.44 + 232 * 0.56], axis=2)
    rgb[skin] = pale[skin]

    # Baji is clean-shaven: fade the original beard into pale skin.
    shave = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shave).ellipse((118, 190, 396, 372), fill=255)
    shave = np.array(shave.filter(ImageFilter.GaussianBlur(14))).astype(np.float32) / 255.0
    rgb = rgb * (1 - shave[:, :, None]) + pale * shave[:, :, None]

    # Red headband across the forehead, with a soft edge.
    band = Image.new("L", (w, h), 0)
    ImageDraw.Draw(band).polygon(
        [(112, 92), (400, 92), (404, 132), (108, 134)], fill=255
    )
    band = np.array(band.filter(ImageFilter.GaussianBlur(4))).astype(np.float32) / 255.0
    cloth = np.stack([lum * 0.18 + 150, lum * 0.08 + 18, lum * 0.08 + 26], axis=2)
    rgb = rgb * (1 - band[:, :, None]) + cloth * band[:, :, None]

    # Keep the eyes but deepen them towards black/brown.
    yy, xx = np.ogrid[:h, :w]
    for cx, cy in ((88, 470), (424, 470)):
        eye = (np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) < 33) & (lum < 180)
        base = lum[eye]
        rgb[eye] = np.stack([base * 0.45, base * 0.32, base * 0.30], axis=1)

    a[:, :, :3] = rgb
    path = os.path.join(GEN, "baji_head.png")
    save_rgba(a, path)
    return path


def build_hair():
    a = np.array(load_ref("ref_hair.png")).astype(np.float32)
    rgb = a[:, :, :3]
    lum = rgb.mean(axis=2)
    h, w = rgb.shape[:2]
    yy, xx = np.ogrid[:h, :w]
    dark = (yy < h * 0.58) & (lum < 160)
    jet = np.stack([lum * 0.32 + 12, lum * 0.30 + 14, lum * 0.30 + 22], axis=2)
    rgb[dark] = jet[dark]
    a[:, :, :3] = rgb
    path = os.path.join(GEN, "baji_hair.png")
    save_rgba(a, path)
    return path


def build_body():
    a = np.array(load_ref("ref_body.png")).astype(np.float32)
    rgb = a[:, :, :3]
    lum = rgb.mean(axis=2)

    # The whole body UV becomes the dark navy uniform (sleeves, trousers,
    # gloves) with the original shading kept as fabric folds.
    uniform = np.stack([lum * 0.16 + 14,
                        lum * 0.16 + 20,
                        lum * 0.20 + 42], axis=2)
    rgb = rgb * 0.12 + uniform * 0.88

    # Red accents where the original had red artwork (tattoo / stripes).
    red = (rgb[:, :, 0] > rgb[:, :, 1] * 1.35) & (rgb[:, :, 0] > 55)
    rgb[red] = np.stack([rgb[red][:, 0] * 0.6 + 110,
                         rgb[red][:, 1] * 0.25,
                         rgb[red][:, 2] * 0.25], axis=1)
    a[:, :, :3] = rgb
    path = os.path.join(GEN, "baji_body.png")
    save_rgba(a, path)
    return path


def main():
    head, hair, body = build_head(), build_hair(), build_body()
    os.makedirs(TEMP, exist_ok=True)

    src = os.path.join(PAYLOADS, "alienx")
    dst = os.path.join(PAYLOADS, "baji")
    raw = open(src, "rb").read()
    i = 12
    for _ in range(2):
        i = raw.index(b"\x00", i) + 1
    declared = struct.unpack(">q", raw[i:i + 8])[0]
    staged = os.path.join(TEMP, "alienx.bundle")
    open(staged, "wb").write(raw[:declared])

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

    outdir = os.path.join(TEMP, "baji_out")
    os.makedirs(outdir, exist_ok=True)
    env.save(pack="original", out_path=outdir)
    produced = [os.path.join(outdir, n) for n in os.listdir(outdir)
                if os.path.isfile(os.path.join(outdir, n))]
    if len(produced) != 1:
        raise SystemExit(f"expected one output bundle, got {produced}")
    open(dst, "wb").write(open(produced[0], "rb").read())
    print("recoloured:", ", ".join(changed))
    print("bundle:", dst, os.path.getsize(dst), "B")

    check = UnityPy.load(dst)
    names = [getattr(o.read(), "m_Name", "") for o in check.objects
             if o.type.name == "AssetBundle"]
    print("internal bundle name:", names)


if __name__ == "__main__":
    main()
