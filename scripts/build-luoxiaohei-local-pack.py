#!/usr/bin/env python3
from pathlib import Path
from PIL import Image
import json
import shutil

SRC = Path("external_assets/IXiaoHei/src/org/taibai/hellohei/img")
DST = Path("external_generated_packs/LuoXiaoHeiLocal")

MAPPING = {
    "licking the claw.gif": ("idle", "idle"),
    "shake-head-txt.gif": ("distractedLook", "distracted_look"),
    "eat-watermelon-txt.gif": ("nudgeStrong", "nudge_strong"),
    "bye.gif": ("welcomeBack", "welcome_back"),
    "play heixiu.gif": ("stretch", "stretch"),
    "playing guitar.gif": ("breakRelax", "break_relax"),
    "eat drumstick.gif": ("run", "run"),
}

LOOPING_ACTIONS = {
    "idle",
    "distractedLook",
    "breakRelax",
    "run",
    "stretch",
}


def clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def export_gif_frames(gif_path: Path, out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    image = Image.open(gif_path)
    frame_index = 0

    while True:
        image.convert("RGBA").save(out_dir / f"{frame_index:03d}.png")
        frame_index += 1
        try:
            image.seek(image.tell() + 1)
        except EOFError:
            break

    return frame_index


def copy_png(src_path: Path, dst_path: Path) -> None:
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    Image.open(src_path).convert("RGBA").save(dst_path)


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Source not found: {SRC}")

    clean_dir(DST)

    icon = SRC / "icon.png"
    if icon.exists():
        copy_png(icon, DST / "preview.png")

    animations = {}
    for filename, (action_key, folder) in MAPPING.items():
        src_file = SRC / filename
        if not src_file.exists():
            print(f"[WARN] Missing: {src_file}")
            continue

        out_dir = DST / folder
        frame_count = export_gif_frames(src_file, out_dir)
        animations[action_key] = {
            "folder": folder,
            "fps": 8,
            "loop": action_key in LOOPING_ACTIONS,
            "frameCount": frame_count,
            "renderer": "pngSequence",
        }

    manifest = {
        "schemaVersion": 1,
        "id": "luo_xiaohei_local",
        "name": "罗小黑",
        "source": "userImported",
        "distribution": "localOnly",
        "style": "anime_gif",
        "license": {
            "type": "unknown",
            "note": "Third-party IP resource. Local testing only. Do not bundle or redistribute without permission.",
        },
        "defaultSize": {"width": 128, "height": 128},
        "defaultScale": 1.0,
        "anchor": "dockAttached",
        "hitBox": {"x": 8, "y": 8, "width": 112, "height": 112},
        "animations": animations,
    }

    with open(DST / "pet.json", "w", encoding="utf-8") as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)

    (DST / "RESOURCE_NOTES.md").write_text(
        """# Luo Xiaohei Local Pack Notes

This pack is generated from a local checkout of `https://github.com/jiang-taibai/IXiaoHei.git`.

The inspected upstream checkout contains `README.md` but no license file. Treat
the resulting frames as local-only test assets. Do not bundle, redistribute, or
publish these images without confirming rights from the original IP owner and
asset author.

The generated manifest keeps one semantic action per distinct animation group.
Runtime-only states such as drag, landing, screen transfer, mouse summon, sleep,
breathing, and break end are resolved by Focus Pet fallback rules instead of
being duplicated in this manifest.
""",
        encoding="utf-8",
    )

    print(f"[OK] Generated pet pack at: {DST}")


if __name__ == "__main__":
    main()
