"""Build the exact option set shipped by the dope 7.0 injector.

Every payload is the byte-for-byte file that Payload-2/InjectorApp.app
downloads from https://dp2.shardweb.app/... . The packages write files in
place; the injector never renames a file or edits fileinfo.

Run:  python tools/build_dope_catalog.py
"""

import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_avatar_3105 import OUT, build_payload, open_package, seal  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PAYLOADS = os.path.join(HERE, "dope_payloads")

ASSET = "Data/Raw/ios/gameassetbundles/avatar/assetindexer.tdn~2F53YNFWXQZyPdFl8HWBBwtXk~3D"
TEXTURE = "Data/Raw/ios/optionalavatarres/gameassetbundles/"

# (package name, payload file, destination, display name)
# Titles and subtitles are taken verbatim from the dope 7.0 screenshots.
ENTRIES = [
    # HS mode
    ("dope_hs_pescoco", "hs1", ASSET, "hs pescoço"),
    ("dope_hs_alto", "hs2", ASSET, "hs alto"),
    ("dope_hs_peito", "hs3_noantenna", ASSET, "hs peito"),
    # HS + ANTENA mode
    ("dope_hs_alto_antena", "hs2_antena", ASSET, "hs alto + antena"),
    ("dope_hs_pescoco_antena", "hs1_antena", ASSET, "hs pescoço + antena"),
    ("dope_hs_barriga_antena", "hs3", ASSET, "hs barriga + antena"),
    ("dope_antena_mao", "antenahand", ASSET, "antena na mão"),
    # Partidas
    ("dope_painel", "aim_Assembly-CSharp-patch_bytes", "Documents/Assembly-CSharp-patch.bytes", "painel",
     [("aim_config_bin", "Documents/config.bin"),
      ("aim_localConfig_json", "Documents/localConfig.json")]),
    ("dope_aimbot_esp", "aim2_Assembly-CSharp-patch_bytes", "Documents/Assembly-CSharp-patch.bytes", "aimbot e esp",
     [("aim2_config_bin", "Documents/config.bin"),
      ("aim2_localConfig_json", "Documents/localConfig.json")]),
    ("dope_fps", "fps_com_dts_freefireth_plist", "Library/Preferences/com.dts.freefireth.plist", "120/144 fps"),
    # Texturas
    ("texture_sielzada", "sielzada", TEXTURE + "optionalab_avatar_62.o~2FELJ0~2BswGVk~2F~2BDPzjlpxie6x~2FA~3D", "textura sielzada"),
    ("texture_mordecai", "mordecai", TEXTURE + "optionalab_avatar_66.1GZrX1l5Sm~2FgqXYqB7dDyULWdn4~3D", "textura mordecai"),
    ("texture_aranha", "spider", TEXTURE + "optionalab_avatar_66.1GZrX1l5Sm~2FgqXYqB7dDyULWdn4~3D", "textura homem-aranha"),
    ("texture_alienx", "alienx", TEXTURE + "optionalab_avatar_66.1GZrX1l5Sm~2FgqXYqB7dDyULWdn4~3D", "textura alien-x"),
]


def main():
    for entry in ENTRIES:
        name, payload, destination, display = entry[:4]
        extras = entry[4] if len(entry) > 4 else []
        files = {}
        rules = []
        primary_source = name + ".raw"
        raw = open(os.path.join(PAYLOADS, payload), "rb").read()
        files[primary_source] = raw
        rules.append((primary_source, destination))
        for index, (extra_payload, extra_destination) in enumerate(extras, start=1):
            source = f"{name}_{index}.raw"
            files[source] = open(os.path.join(PAYLOADS, extra_payload), "rb").read()
            rules.append((source, extra_destination))

        body = build_payload(
            display,
            files,
            rules,
            meta={"rawLength": len(raw), "compressed": False},
        )
        out = os.path.join(OUT, name + ".3105")
        with open(out, "wb") as handle:
            handle.write(seal(body))
        _, decoded = open_package(open(out, "rb").read())
        if decoded != files:
            raise SystemExit(f"{out}: round-trip failed")
        print(f"{name:24s} {display:24s} {len(raw):8d} B  {hashlib.sha256(raw).hexdigest()[:12]}")


if __name__ == "__main__":
    main()
