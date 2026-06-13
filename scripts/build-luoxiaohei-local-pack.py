#!/usr/bin/env python3
from pathlib import Path
import runpy


def main() -> None:
    script = Path(__file__).with_name("build-local-pet-packs.py")
    namespace = runpy.run_path(str(script))
    namespace["OUT_ROOT"].mkdir(parents=True, exist_ok=True)
    namespace["build_luo_xiaohei_pack"]()
    print(f"[OK] Generated Luo Xiaohei local pack at: {namespace['OUT_ROOT'] / 'LuoXiaoHeiLocal'}")


if __name__ == "__main__":
    main()
