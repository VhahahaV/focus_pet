#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUT_ROOT = ROOT / "external_generated_packs"
PET_PACK_ZIP_DIR = ROOT / "dist/local/PetPacks"
DOWNLOADS = Path.home() / "Downloads"
LUO_SRC = ROOT / "external_assets/IXiaoHei/src/org/taibai/hellohei/img"
UNIKEN_ZIP = ROOT / "dist/local/UNIkeNLocal.zip"


@dataclass(frozen=True)
class AnimationMapping:
    action: str
    source_group: str
    folder: str
    fps: float
    loop: bool
    note: str


@dataclass(frozen=True)
class AudioMapping:
    action: str
    source_file: str
    volume: float


@dataclass(frozen=True)
class SourceActionMapping:
    action_id: str
    title: str
    source_group: str
    folder: str
    fps: float
    loop: bool
    audio_file: str | None = None
    volume: float = 0.55


def clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def load_json_from_zip(archive: zipfile.ZipFile, name: str) -> dict:
    data = archive.read(name)
    for encoding in ("utf-8", "utf-8-sig", "gb18030"):
        try:
            return json.loads(data.decode(encoding))
        except UnicodeDecodeError:
            continue
    raise ValueError(f"Could not decode JSON: {name}")


def split_frame_stem(stem: str) -> tuple[str, int]:
    prefix, sep, suffix = stem.rpartition("_")
    if sep and suffix.isdigit():
        return prefix, int(suffix)
    return stem, 0


def action_group_entries(archive: zipfile.ZipFile, source_root: str, group: str) -> list[tuple[int, str]]:
    prefix = f"{source_root}/action/"
    result: list[tuple[int, str]] = []
    for name in archive.namelist():
        if not name.startswith(prefix) or not name.lower().endswith(".png"):
            continue
        stem = Path(name).stem
        parsed_group, frame_index = split_frame_stem(stem)
        if parsed_group == group:
            result.append((frame_index, name))
    return sorted(result)


def copy_zip_png_group(archive: zipfile.ZipFile, source_root: str, group: str, destination: Path) -> int:
    entries = action_group_entries(archive, source_root, group)
    if not entries:
        raise ValueError(f"No action frames for group {group!r}")
    destination.mkdir(parents=True, exist_ok=True)
    for output_index, (_, name) in enumerate(entries):
        with archive.open(name) as file:
            Image.open(file).convert("RGBA").save(destination / f"{output_index:03d}.png")
    return len(entries)


def copy_zip_png(archive: zipfile.ZipFile, name: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with archive.open(name) as file:
        Image.open(file).convert("RGBA").save(destination)


def copy_zip_binary_case_insensitive(
    archive: zipfile.ZipFile,
    source_root: str,
    source_file: str,
    destination: Path,
) -> None:
    expected = f"{source_root}/note/{source_file}"
    match = next((name for name in archive.namelist() if name.lower() == expected.lower()), None)
    if match is None:
        raise ValueError(f"No audio file for {source_file!r}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(archive.read(match))


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def animation_manifest(mappings: Iterable[AnimationMapping], frame_counts: dict[str, int]) -> dict:
    return {
        mapping.action: {
            "folder": mapping.folder,
            "fps": mapping.fps,
            "loop": mapping.loop,
            "frameCount": frame_counts[mapping.folder],
        }
        for mapping in mappings
    }


def source_action_manifest(mappings: Iterable[SourceActionMapping], frame_counts: dict[str, int]) -> list[dict]:
    result = []
    for mapping in mappings:
        item = {
            "id": mapping.action_id,
            "title": mapping.title,
            "folder": mapping.folder,
            "fps": mapping.fps,
            "loop": mapping.loop,
            "frameCount": frame_counts[mapping.folder],
        }
        if mapping.audio_file:
            item["audio"] = {
                "file": f"audio/{Path(mapping.audio_file).name.lower()}",
                "volume": mapping.volume,
            }
        result.append(item)
    return result


def fps_from_frame_refresh(value: object, default: float = 8) -> float:
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return default
    if seconds <= 0:
        return default
    return min(12, max(1, round(1 / seconds, 2)))


def source_actions_from_act_conf(
    act_conf: dict,
    idle_source_action_ids: list[str],
    source_audio: dict[str, tuple[str, float]] | None = None,
) -> list[SourceActionMapping]:
    audio = source_audio or {}
    result = []
    for action_id, conf in act_conf.items():
        if not isinstance(conf, dict):
            continue
        source_group = conf.get("images")
        if not isinstance(source_group, str) or not source_group:
            continue
        audio_file, volume = audio.get(action_id, (None, 0.55))
        result.append(SourceActionMapping(
            action_id=action_id,
            title=action_id,
            source_group=source_group,
            folder=source_group,
            fps=fps_from_frame_refresh(conf.get("frame_refresh")),
            loop=action_id in idle_source_action_ids or bool(conf.get("need_move")),
            audio_file=audio_file,
            volume=volume,
        ))
    return result


def build_zip_pack(
    zip_path: Path,
    source_root: str,
    destination: Path,
    manifest_base: dict,
    preview_candidates: list[str],
    mappings: list[AnimationMapping],
    audio_mappings: list[AudioMapping] | None = None,
    source_actions: list[SourceActionMapping] | None = None,
    idle_source_action_ids: list[str] | None = None,
    notes: str = "",
) -> None:
    clean_dir(destination)
    copied_groups: dict[str, int] = {}
    with zipfile.ZipFile(zip_path) as archive:
        for candidate in preview_candidates:
            full_name = f"{source_root}/{candidate}"
            if full_name in archive.namelist():
                copy_zip_png(archive, full_name, destination / "preview.png")
                break

        source_actions = source_actions or []
        all_frame_mappings = [(mapping.source_group, mapping.folder) for mapping in mappings]
        all_frame_mappings += [(mapping.source_group, mapping.folder) for mapping in source_actions]
        for source_group, folder in all_frame_mappings:
            if folder in copied_groups:
                continue
            copied_groups[folder] = copy_zip_png_group(
                archive,
                source_root,
                source_group,
                destination / folder,
            )

        audio_targets: dict[str, str] = {}
        for mapping in audio_mappings or []:
            audio_targets[mapping.source_file] = f"audio/{Path(mapping.source_file).name.lower()}"
        for mapping in source_actions:
            if mapping.audio_file:
                audio_targets[mapping.audio_file] = f"audio/{Path(mapping.audio_file).name.lower()}"
        for source_file, target in audio_targets.items():
            copy_zip_binary_case_insensitive(archive, source_root, source_file, destination / target)

        audio_manifest = {}
        for mapping in audio_mappings or []:
            target = f"audio/{Path(mapping.source_file).name.lower()}"
            audio_manifest[mapping.action] = {"file": target, "volume": mapping.volume}

        manifest = {
            **manifest_base,
            "animations": animation_manifest(mappings, copied_groups),
        }
        if source_actions:
            manifest["sourceActions"] = source_action_manifest(source_actions, copied_groups)
        if idle_source_action_ids:
            manifest["idleSourceActionIDs"] = idle_source_action_ids
        if audio_manifest:
            manifest["audio"] = audio_manifest
        write_json(destination / "pet.json", manifest)

        if notes:
            (destination / "RESOURCE_NOTES.md").write_text(notes, encoding="utf-8")


def copy_legacy_zip_pack(
    archive: zipfile.ZipFile,
    source_root: str,
    destination: Path,
    mappings: list[AnimationMapping],
) -> dict[str, int]:
    copied_groups: dict[str, int] = {}
    for mapping in mappings:
        if mapping.folder in copied_groups:
            continue
        copied_groups[mapping.folder] = copy_zip_png_group(
            archive,
            source_root,
            mapping.source_group,
            destination / mapping.folder,
        )
    return copied_groups


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


def archive_pack_directory(pack_dir: Path, archive_path: Path) -> None:
    if archive_path.exists():
        archive_path.unlink()
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(pack_dir.rglob("*")):
            if path.name == ".DS_Store" or path.name.startswith("._"):
                continue
            archive.write(path, path.relative_to(pack_dir.parent))


def export_individual_pack_archives() -> None:
    clean_dir(PET_PACK_ZIP_DIR)
    for pack_dir in sorted(OUT_ROOT.iterdir()):
        if not pack_dir.is_dir() or not (pack_dir / "pet.json").exists():
            continue
        archive_pack_directory(pack_dir, PET_PACK_ZIP_DIR / f"{pack_dir.name}.zip")

    if UNIKEN_ZIP.exists():
        shutil.copy2(UNIKEN_ZIP, PET_PACK_ZIP_DIR / UNIKEN_ZIP.name)
    else:
        print(f"[WARN] UNIkeN pack zip not found, skipped: {UNIKEN_ZIP}")


def build_luo_xiaohei_pack() -> None:
    destination = OUT_ROOT / "LuoXiaoHeiLocal"
    clean_dir(destination)
    if not LUO_SRC.exists():
        raise SystemExit(f"Source not found: {LUO_SRC}")

    if (LUO_SRC / "icon.png").exists():
        copy_png(LUO_SRC / "icon.png", destination / "preview.png")
    for source_name, target_name in [
        ("emotion increasing animation.png", "emotion_increasing.png"),
        ("smiling clouds.png", "smiling_clouds.png"),
        ("foods/egg.png", "egg.png"),
        ("foods/milk.png", "milk.png"),
        ("bath/soap.png", "soap.png"),
    ]:
        source = LUO_SRC / source_name
        if source.exists():
            copy_png(source, destination / "props" / target_name)

    mappings = [
        AnimationMapping("idle", "shake-head-txt.gif", "idle", 8, True, "原项目主动画；作为默认陪伴和专注低打扰状态。"),
        AnimationMapping("focusStart", "shake-head-txt.gif", "idle", 8, True, "进入工作时保持原主动画。"),
        AnimationMapping("focusStable", "shake-head-txt.gif", "idle", 8, True, "稳定专注时保持原主动画。"),
        AnimationMapping("breath", "shake-head-txt.gif", "idle", 8, True, "呼吸类低频状态复用原主动画。"),
        AnimationMapping("blink", "licking the claw.gif", "grooming", 8, False, "原项目洗澡/清洁动作；用作专注中的低频舔爪彩蛋。"),
        AnimationMapping("stretch", "licking the claw.gif", "grooming", 8, False, "没有伸懒腰素材，使用清洁动作表达小休整。"),
        AnimationMapping("sleep", "bye.gif", "away", 6, True, "原项目退出动画；当前用作暂离/离开姿态。"),
        AnimationMapping("wake", "play heixiu.gif", "play_heixiu", 8, False, "唤醒时使用玩小黑咻的互动动作。"),
        AnimationMapping("distractedLook", "shake-head-txt.gif", "idle", 8, True, "摇头主动画可表达走神观察。"),
        AnimationMapping("nudgeGentle", "play heixiu.gif", "play_heixiu", 8, False, "温和提醒时用轻互动动作。"),
        AnimationMapping("nudgeStrong", "eat-watermelon-txt.gif", "eat_watermelon", 8, False, "强提醒用更有存在感的吃西瓜文字动作。"),
        AnimationMapping("breakRelax", "playing guitar.gif", "guitar", 8, True, "原项目随机吉他动作；最适合休息陪伴。"),
        AnimationMapping("breakEnd", "eat drumstick.gif", "eat_drumstick", 8, False, "休息结束用喂食/恢复能量的动作。"),
        AnimationMapping("welcomeBack", "play heixiu.gif", "play_heixiu", 8, False, "回到电脑时使用轻互动欢迎。"),
        AnimationMapping("mouseSummon", "play heixiu.gif", "play_heixiu", 8, False, "召回到鼠标附近时使用轻互动动作。"),
    ]
    source_actions = [
        SourceActionMapping("shake-head-txt", "shake-head-txt", "shake-head-txt.gif", "idle", 8, True),
        SourceActionMapping("licking the claw", "licking the claw", "licking the claw.gif", "grooming", 8, False),
        SourceActionMapping("bye", "bye", "bye.gif", "away", 6, True),
        SourceActionMapping("play heixiu", "play heixiu", "play heixiu.gif", "play_heixiu", 8, False),
        SourceActionMapping("eat-watermelon-txt", "eat-watermelon-txt", "eat-watermelon-txt.gif", "eat_watermelon", 8, False),
        SourceActionMapping("playing guitar", "playing guitar", "playing guitar.gif", "guitar", 8, True),
        SourceActionMapping("eat drumstick", "eat drumstick", "eat drumstick.gif", "eat_drumstick", 8, False),
    ]

    copied_groups: dict[str, int] = {}
    for mapping in mappings:
        if mapping.folder in copied_groups:
            continue
        copied_groups[mapping.folder] = export_gif_frames(LUO_SRC / mapping.source_group, destination / mapping.folder)

    write_json(
        destination / "pet.json",
        {
            "schemaVersion": 1,
            "id": "luo_xiaohei_local",
            "name": "罗小黑",
            "author": "jiang-taibai / local asset",
            "style": "anime_gif",
            "license": "unknown · Third-party IP resource. Local testing only. Do not bundle or redistribute without permission.",
            "distribution": "localOnly",
            "defaultSize": {"width": 128, "height": 128},
            "anchor": {"x": 0.5, "y": 1.0},
            "animations": animation_manifest(mappings, copied_groups),
            "sourceActions": source_action_manifest(source_actions, copied_groups),
            "idleSourceActionIDs": [action.action_id for action in source_actions],
        },
    )
    (destination / "RESOURCE_NOTES.md").write_text(
        """# Luo Xiaohei Local Pack Notes

Generated from the local checkout at `external_assets/IXiaoHei`.

The upstream project uses `shake-head-txt.gif` as its main continuous desktop
pet animation, `playing guitar.gif` as the only random click action,
`eat drumstick.gif` for food, `licking the claw.gif` for bath/cleaning, and
`bye.gif` for exit. The Focus Pet mapping now follows those source semantics:
default/focus uses the main shake-head loop; break uses guitar; ambient stretch
uses grooming; food/recovery uses drumstick; away uses bye.

The upstream static mood and item images are preserved under `props/` for future
interaction work, but they are not mapped to `PetAction` because they are UI
overlays or inventory items rather than desktop pet body animations.

This is a third-party IP resource and should stay local-only unless rights are
confirmed.
""",
        encoding="utf-8",
    )


def build_xiaodai_pack() -> None:
    mappings = [
        AnimationMapping("idle", "stand", "idle", 8, True, "普通站立，作为默认待机。"),
        AnimationMapping("focusStart", "focus", "focus", 8, True, "原包专注动作，用户进入工作时使用。"),
        AnimationMapping("focusStable", "focus", "focus", 8, True, "稳定工作时持续陪伴。"),
        AnimationMapping("breath", "focus", "focus", 8, True, "专注 ambient 呼吸复用 focus。"),
        AnimationMapping("blink", "stand", "idle", 8, True, "眨眼类 ambient 复用站立。"),
        AnimationMapping("sleep", "sleep", "sleep", 4, True, "趴睡，用户暂离/锁屏。"),
        AnimationMapping("wake", "sleepy", "sleepy", 8, False, "打瞌睡/醒转过渡。"),
        AnimationMapping("stretch", "sleepy", "sleepy", 8, False, "长时间专注后的伸展/打哈欠提醒。"),
        AnimationMapping("distractedLook", "disturbed", "disturbed", 8, True, "被打扰状态，用于娱乐或频繁切换。"),
        AnimationMapping("nudgeGentle", "patpat2", "nudge_gentle", 8, False, "轻拍/撒娇，作为温和提醒。"),
        AnimationMapping("nudgeStrong", "playball", "nudge_strong", 10, False, "玩球动作更醒目，作为强提醒。"),
        AnimationMapping("breakRelax", "onfloor", "break_relax", 8, True, "趴地/翻身，适合休息。"),
        AnimationMapping("breakEnd", "hy1end", "break_end", 8, False, "活跃动作收尾，提醒休息结束。"),
        AnimationMapping("welcomeBack", "feed", "welcome_back", 8, False, "喂食爱心，用作欢迎回来。"),
        AnimationMapping("dragged", "drag", "dragged", 10, True, "拖拽姿态。"),
        AnimationMapping("landing", "fall", "landing", 10, False, "落下/落地动作。"),
        AnimationMapping("run", "rightwalk", "run", 10, True, "横向移动。"),
        AnimationMapping("screenTransfer", "edge", "screen_transfer", 8, False, "贴边/藏边，用于切屏。"),
        AnimationMapping("mouseSummon", "playball", "mouse_summon", 10, False, "召回鼠标附近时用玩球动作。"),
    ]
    idle_source_action_ids = [
        "default",
        "focus",
        "sleepy",
        "patpat1",
        "patpat2",
        "hy1",
        "hy1end",
        "playball",
        "disturbed",
        "sleep",
        "onfloor",
    ]
    with zipfile.ZipFile(DOWNLOADS / "小呆.zip") as archive:
        act_conf = load_json_from_zip(archive, "小呆/act_conf.json")
    source_actions = source_actions_from_act_conf(act_conf, idle_source_action_ids)
    build_zip_pack(
        DOWNLOADS / "小呆.zip",
        "小呆",
        OUT_ROOT / "XiaoDaiLocal",
        {
            "schemaVersion": 1,
            "id": "xiaodai_local",
            "name": "小呆",
            "author": "栎曦_Nuo",
            "style": "original_2d_catgirl",
            "license": "unknown · User supplied local pet pack. Local testing only unless redistribution rights are confirmed.",
            "distribution": "localOnly",
            "defaultSize": {"width": 172, "height": 172},
            "anchor": {"x": 0.5, "y": 1.0},
        },
        ["info/xd.png", "info/cgg.png"],
        mappings,
        source_actions=source_actions,
        idle_source_action_ids=idle_source_action_ids,
        notes="""# XiaoDai Local Pack Notes

Generated from `/Users/vhahahav/Downloads/小呆.zip`.

Source behavior highlights:
- `focus` is the explicit work/focus animation and is mapped to Focus Pet's
  focus actions.
- `stand` is neutral idle.
- `sleep` is true away/sleep; `sleepy` is used for wake/stretch transitions.
- `disturbed`, `patpat2`, and `playball` form the distracted/gentle/strong
  reminder ladder.
- `onfloor`, `drag`, `fall`, `rightwalk`, and `edge` preserve desktop-specific
  rest, drag, landing, movement, and edge behavior.

No audio files are present in the supplied zip.
""",
    )


def build_pixel_cat_pack() -> None:
    mappings = [
        AnimationMapping("idle", "stand", "idle", 5, True, "箱子猫默认待机。"),
        AnimationMapping("focusStart", "work", "work", 8, True, "原包工作动作，用户开始工作时使用。"),
        AnimationMapping("focusStable", "work", "work", 8, True, "稳定工作状态。"),
        AnimationMapping("breath", "work", "work", 8, True, "专注 ambient 复用工作动作。"),
        AnimationMapping("blink", "stand", "idle", 5, True, "眨眼类 ambient 复用待机。"),
        AnimationMapping("sleep", "sleep", "sleep", 2, True, "打盹，用户暂离。"),
        AnimationMapping("wake", "chibi", "happy", 6, False, "醒来/返回时使用 happy chibi。"),
        AnimationMapping("stretch", "chibi", "happy", 6, False, "伸展位没有专门素材，使用 happy chibi。"),
        AnimationMapping("distractedLook", "hide", "distracted_look", 5, True, "躲猫猫/窥视，作为走神观察。"),
        AnimationMapping("nudgeGentle", "touch", "nudge_gentle", 5, False, "被摸/轻触反馈，用作温和提醒。"),
        AnimationMapping("nudgeStrong", "ybfist", "nudge_strong", 10, False, "摇摆拳法，作为强提醒。"),
        AnimationMapping("breakRelax", "ccpkq", "break_relax", 5, True, "蹭蹭/箱子状态，适合休息陪伴。"),
        AnimationMapping("breakEnd", "dance", "break_end", 5, False, "跳舞庆祝休息结束。"),
        AnimationMapping("welcomeBack", "chibi", "welcome_back", 6, False, "happy chibi 欢迎回来。"),
        AnimationMapping("dragged", "drag", "dragged", 10, True, "拖拽姿态。"),
        AnimationMapping("landing", "onfloor", "landing", 5, False, "亮相/落地。"),
        AnimationMapping("run", "rightwalk", "run", 12, True, "横向移动。"),
        AnimationMapping("screenTransfer", "rightwalk", "run", 12, True, "切屏时复用横向移动。"),
        AnimationMapping("mouseSummon", "feed_1", "mouse_summon", 5, False, "靠近/召回时用喂食互动。"),
    ]
    audio_mappings = [
        AudioMapping("focusStart", "work.wav", 0.32),
        AudioMapping("sleep", "snore.wav", 0.22),
        AudioMapping("distractedLook", "hide.wav", 0.28),
        AudioMapping("nudgeGentle", "cc.wav", 0.34),
        AudioMapping("nudgeStrong", "crazy.wav", 0.34),
        AudioMapping("breakRelax", "happy.wav", 0.26),
        AudioMapping("breakEnd", "nyannyannyan.wav", 0.30),
        AudioMapping("welcomeBack", "chibi.WAV", 0.30),
        AudioMapping("dragged", "cc.wav", 0.30),
        AudioMapping("landing", "onfloor.wav", 0.30),
        AudioMapping("mouseSummon", "feed1.wav", 0.30),
    ]
    idle_source_action_ids = [
        "default",
        "work",
        "sleep",
        "patpat",
        "happy",
        "cc",
        "dance",
        "hide",
        "yb",
        "faint",
        "onfloor",
    ]
    source_audio = {
        "sleep": ("snore.wav", 0.22),
        "patpat": ("cc.wav", 0.30),
        "feed_1": ("feed1.wav", 0.30),
        "feed_2": ("feed2.wav", 0.30),
        "feed_3": ("feed3.wav", 0.30),
        "happy": ("chibi.WAV", 0.30),
        "cc": ("cc.wav", 0.30),
        "dance": ("nyannyannyan.wav", 0.30),
        "hide": ("hide.wav", 0.28),
        "yb": ("crazy.wav", 0.34),
        "faint": ("faint.wav", 0.28),
        "work": ("work.wav", 0.32),
        "drag": ("cc.wav", 0.30),
        "onfloor": ("onfloor.wav", 0.30),
    }
    with zipfile.ZipFile(DOWNLOADS / "像素猫meme.zip") as archive:
        act_conf = load_json_from_zip(archive, "像素猫meme/act_conf.json")
    source_actions = source_actions_from_act_conf(act_conf, idle_source_action_ids, source_audio)
    build_zip_pack(
        DOWNLOADS / "像素猫meme.zip",
        "像素猫meme",
        OUT_ROOT / "PixelCatMemeLocal",
        {
            "schemaVersion": 1,
            "id": "pixel_cat_meme_local",
            "name": "像素猫meme",
            "author": "代号皮克嗖儿",
            "style": "pixel_cat_meme",
            "license": "unknown · User supplied local pet pack. Local testing only unless redistribution rights are confirmed.",
            "distribution": "localOnly",
            "defaultSize": {"width": 150, "height": 150},
            "anchor": {"x": 0.5, "y": 1.0},
        },
        ["info/pikesouCatmeme.png", "info/cover.png"],
        mappings,
        audio_mappings=audio_mappings,
        source_actions=source_actions,
        idle_source_action_ids=idle_source_action_ids,
        notes="""# Pixel Cat Meme Local Pack Notes

Generated from `/Users/vhahahav/Downloads/像素猫meme.zip`.

Source behavior highlights:
- `work` explicitly says "working" and is mapped to Focus Pet's work/focus
  actions.
- `stand`, `hide`, `touch`, `ybfist`, `ccpkq`, `dance`, `drag`, `onfloor`,
  `rightwalk`, and `feed_1` cover idle, distracted look, gentle nudge, strong
  nudge, break, break end, drag, landing, movement, and mouse summon.
- The source note file references `chibi.wav`, while the archive stores
  `chibi.WAV`; generation normalizes copied audio paths to lowercase.
- Long ambient focus actions intentionally do not play audio, while discrete
  transitions and nudges do.
""",
    )


def main() -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    build_xiaodai_pack()
    build_pixel_cat_pack()
    build_luo_xiaohei_pack()
    export_individual_pack_archives()
    print(f"[OK] Generated local pet packs under {OUT_ROOT}")
    print(f"[OK] Exported individual pet pack zips under {PET_PACK_ZIP_DIR}")


if __name__ == "__main__":
    main()
