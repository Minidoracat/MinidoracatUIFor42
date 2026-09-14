# -*- coding: utf-8 -*-
"""把 AI 生成的圖示表（黑底白剪影、等分格）切成 32×32 純白可染色 PNG（mui_art_*.png）。

用法：
  python scripts/import_icon_sheet.py <sheet.png> [--grid 4x4] [--keys house,skull,...]
  python scripts/import_icon_sheet.py <single.png> --keys cow      # 單格重生（整張只有一個圖）

流程（每格）：亮度→alpha（黑底＝透明、白＝實心；灰階＝AA）→ 去掉低於門檻的雜訊 →
依 alpha bbox 裁切 → 等比縮到 28px 內 → 置中貼進 32×32（四邊至少 1px 透明邊）→
RGB 一律寫 255（verify 要求純白）。輸出直接落框架貼圖目錄；之後跑
`python scripts/gen_ui_textures.py` 印 16px ASCII 預覽、`python scripts/verify_mod.py` 把關。

預設 key 順序為原始 scripts/icons/sheet.png 的 13 格；其他圖表以 --keys 指定，尾端空格忽略。
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_ui_textures import ART_ICON_NAMES, ICON_SIZE, default_output_dir  # noqa: E402

DEFAULT_KEYS = (
    "house", "skull", "pawprint", "steeringwheel",
    "chicken", "cow", "pig", "sheep", "deer", "rabbit", "raccoon", "rodent", "turkey",
)
VALID_KEYS = {name[len("mui_art_"):-len(".png")] for name in ART_ICON_NAMES}
INNER = ICON_SIZE - 4      # 內容最大邊長 28：四邊留 ≥2px（verify 只要求 1px，多留給 AA 暈）
NOISE = 24                 # 亮度低於此值視為背景（AI 黑底常有 3-10 的雜訊）


def cell_to_alpha(cell: Image.Image) -> Image.Image:
    """黑底白圖 → L 模式 alpha（含 AA），並去背景雜訊。"""
    lum = cell.convert("L")
    return lum.point(lambda v: 0 if v < NOISE else min(255, int((v - NOISE) * 255 / (255 - NOISE))))


def fit_icon(alpha: Image.Image) -> Image.Image:
    bbox = alpha.getbbox()
    if not bbox:
        raise SystemExit("空格：這格沒有任何白色內容")
    content = alpha.crop(bbox)
    w, h = content.size
    scale = INNER / float(max(w, h))
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    content = content.resize((nw, nh), Image.LANCZOS)
    out = Image.new("L", (ICON_SIZE, ICON_SIZE), 0)
    out.paste(content, ((ICON_SIZE - nw) // 2, (ICON_SIZE - nh) // 2))
    white = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (255, 255, 255, 0))
    white.putalpha(out)
    return white


def main() -> None:
    parser = argparse.ArgumentParser(description="Slice an AI icon sheet into mui_art_*.png.")
    parser.add_argument("sheet", type=Path)
    parser.add_argument("--grid", default="4x4", help="欄x列（單張圖用 1x1）")
    parser.add_argument("--keys", help="逗號分隔 key 順序（預設原始 sheet.png 的 13 格）")
    parser.add_argument("--out", type=Path, help="輸出目錄（預設框架貼圖目錄）")
    args = parser.parse_args()

    cols, rows = (int(v) for v in args.grid.lower().split("x"))
    keys = args.keys.split(",") if args.keys else DEFAULT_KEYS
    unknown = sorted(set(keys) - VALID_KEYS)
    if unknown:
        raise SystemExit(f"未知 key（不在 ART_ICON_NAMES）：{unknown}")
    if len(keys) > cols * rows:
        raise SystemExit(f"key 數 {len(keys)} 超過格數 {cols * rows}")

    out_dir = (args.out or default_output_dir()).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    with Image.open(args.sheet) as sheet:
        sheet = sheet.convert("RGB")
        cw, ch = sheet.width / cols, sheet.height / rows
        for index, key in enumerate(keys):
            c, r = index % cols, index // cols
            # 內縮 4%：AI 表格常帶細格線或格緣殘白，切掉邊緣避免被當內容
            inset_x, inset_y = cw * 0.04, ch * 0.04
            box = (round(c * cw + inset_x), round(r * ch + inset_y),
                   round((c + 1) * cw - inset_x), round((r + 1) * ch - inset_y))
            icon = fit_icon(cell_to_alpha(sheet.crop(box)))
            target = out_dir / f"mui_art_{key}.png"
            icon.save(target, format="PNG")
            ink = sum(1 for v in icon.getchannel("A").tobytes() if v > 0) / float(ICON_SIZE * ICON_SIZE)
            print(f"{target.name}: ink={ink:.3f}")
    print("done；接著跑 python scripts/gen_ui_textures.py 看 16px 預覽、python scripts/verify_mod.py 把關")


if __name__ == "__main__":
    main()
