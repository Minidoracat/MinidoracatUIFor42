# -*- coding: utf-8 -*-
"""UIFor42 專屬的檢查：scripts/verify_mod.py 第 19 項會呼叫；單獨跑 `python scripts/verify_local.py`。
2026-11-26 verify_mod.py 換成家族模板時，從舊副本原樣搬來（門檻與掃描範圍不變）：

 12. UI 貼圖（皮膚＋圖示）與圖表匯入相容性 — gen_ui_textures.verify_image 逐張驗、scripts/test_icon_import.py；
                           缺 Pillow 列 SKIP（hook 的 uv run 環境沒有 Pillow，`uv run --with pillow` 才會跑）
 13. Lua 煙霧測試         — 跑 scripts/smoke_harness.lua；publish_workshop.py 只跑 verify_mod.py，這是發布路徑上唯一的煙霧測試
"""
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

passed, failed, skipped = [], [], []

# 豁免清單與 verify_mod.py 共用：scripts/verify_ignore.txt，每行一個子字串樣式（# 開頭為註解）。
IGNORE_PATTERNS = []
_ign = os.path.join(os.path.dirname(os.path.abspath(__file__)), "verify_ignore.txt")
if os.path.isfile(_ign):
    with open(_ign, encoding="utf-8") as _fh:
        for _line in _fh:
            _line = _line.strip()
            if _line and not _line.startswith("#"):
                IGNORE_PATTERNS.append(_line)


def ok(label):
    passed.append(label)
    print(f"  PASS  {label}")


def fail(label, details=None):
    if not details:  # 說失敗卻沒附細節（例：子程序結束碼非零但沒輸出）也是失敗；空清單走下面會記成 PASS
        failed.append(label)
        print(f"  FAIL  {label}")
        return
    kept = [d for d in details if not any(p in d for p in IGNORE_PATTERNS)]
    waived = [d for d in details if any(p in d for p in IGNORE_PATTERNS)]
    for d in waived:
        print(f"  WAIVE {label}: {d}（verify_ignore.txt 豁免）")
    if not kept:
        if waived:
            ok(f"{label}（{len(waived)} 筆豁免）")
        else:
            ok(label)
        return
    failed.append(label)
    print(f"  FAIL  {label}")
    for d in kept:
        print(f"        {d}")


def skip(label, why):
    skipped.append(label)
    print(f"  SKIP  {label} — {why}")


def find_media():
    hits = []
    mod_root = os.path.join(REPO, "MOD")
    if os.path.isdir(mod_root):
        for folder in os.listdir(mod_root):
            p = os.path.join(mod_root, folder, "Contents", "mods")
            if not os.path.isdir(p):
                continue
            for inner in os.listdir(p):
                media = os.path.join(p, inner, "42", "media")
                if os.path.isdir(media):
                    hits.append(media)
    return hits


MEDIA_DIRS = find_media()
if not MEDIA_DIRS:
    print("找不到 MOD/*/Contents/mods/*/42/media，中止")
    sys.exit(2)

# ---- 12. UI 貼圖（皮膚＋圖示）----
# 42/media/ui/MinidoracatUI/ 的 OUTPUT_NAMES（皮膚＋幾何圖示＋art 圖示＋彩色吉祥物＋彩色工具列圖示）逐張過
# gen_ui_textures.verify_image。共同項：尺寸／IHDR（8-bit RGBA、無多餘 chunk）；彩色資產以外純白 RGB。
# 彩色資產（rev 13 Dock 把手吉祥物、rev 21 通知紀錄鈴鐺）另驗：64x64／1px 透明邊／含非白色彩。
# 皮膚另驗：committed alpha＝rounded_patch_alpha 重算幾何（ROUNDED_PATCHES 全部半徑 3／6／10／20）／
# 照 NinePatchTexture.java:262-298 反解析切線＝(r,4,r)、上圓下直 (r,r+4,0)／拉伸區逐列相同／
# 對稱／角透明／中心實心或透空／有 AA／半徑 6 參考 alpha 表逐像素比對。圖示另驗：32x32／1px 透明邊／鏡射對稱／
# 手算探針像素（該實心的實心、該透空的透空）／著墨比例區間／有 AA 過渡。
# Lua 測試全用 stub、從不讀 PNG，貼圖壞了只會靜默退回直角或不畫圖示——這是唯一擋住
# 壞資產上 Workshop 的閘門。缺 Pillow 列 SKIP。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from gen_ui_textures import OUTPUT_NAMES as _TEX_NAMES, verify_image as _verify_texture
except ImportError as _e:   # Pillow 沒裝（gen_ui_textures 頂層 import PIL）
    skip("UI 貼圖（皮膚＋圖示）", f"無法載入 gen_ui_textures（{_e}）")
    skip("圖表匯入相容性", f"無法載入 gen_ui_textures（{_e}）")
else:
    from pathlib import Path as _Path
    _tex_problems = []
    _tex_count = 0
    for _m in MEDIA_DIRS:
        _tex_dir = _Path(_m) / "ui" / "MinidoracatUI"
        if not _tex_dir.is_dir():
            _tex_problems.append(f"貼圖目錄不存在: {os.path.relpath(_tex_dir, REPO)}"
                                 "（框架核心資產整包缺失，跑 python -B scripts/gen_ui_textures.py）")
            continue
        for _name in _TEX_NAMES:
            _p = _tex_dir / _name
            if not _p.is_file():
                _tex_problems.append(f"缺檔: {os.path.relpath(_p, REPO)}")
                continue
            try:
                _verify_texture(_p)
                _tex_count += 1
            except Exception as _ae:   # AssertionError／PIL 解碼錯誤（UnidentifiedImageError/OSError）都算壞
                _tex_problems.append(f"{os.path.relpath(_p, REPO)}: {type(_ae).__name__}: {_ae}")
    if _tex_count == 0 and not _tex_problems:
        fail("UI 貼圖（皮膚＋圖示）", ["MEDIA_DIRS 掃不到任何 ui/MinidoracatUI 貼圖——框架不可無資產發版"])
    else:
        fail("UI 貼圖（皮膚＋圖示，gen_ui_textures.verify_image）", _tex_problems) if _tex_problems \
            else ok(f"UI 貼圖（皮膚＋圖示，{_tex_count} 張過 verify_image）")
    _import_check = subprocess.run(
        [sys.executable, "scripts/test_icon_import.py"], capture_output=True, cwd=REPO)
    if _import_check.returncode:
        fail("圖表匯入相容性", [(_import_check.stdout + _import_check.stderr).decode("utf-8", errors="replace")])
    else:
        ok("圖表匯入相容性（舊圖表預設排列＋導覽／車輛圖示重建）")

# ---- 13. Lua 煙霧測試 ----
# scripts/smoke_harness.lua：假 PZ 全域驅動真 V1.lua 跑情境（facade 半初始化／
# NinePatch 三態／theme 隔離／fits 邊界／Icons 取用與退回）。靜態掃描抓不到「改簽章漏改呼叫點」「刪
# scroll 補償」「快取重試」這類要執行才炸的回歸——雙閘門缺一不可，缺 lua 列 SKIP
# 而非 PASS（SKIP＝該防線沒跑到）。
_lua_bin = shutil.which("lua")
if not _lua_bin:
    skip("Lua 煙霧測試（smoke_harness.lua）", "PATH 沒有 lua")
else:
    _r = subprocess.run([_lua_bin, "scripts/smoke_harness.lua"], capture_output=True, cwd=REPO)
    _lines = [l for l in (_r.stdout or b"").decode("utf-8", "replace").splitlines() if l.strip()]
    _err_tail = (_r.stderr or b"").decode("utf-8", "replace").splitlines()[-3:]
    if _r.returncode != 0:
        fail("Lua 煙霧測試（smoke_harness.lua）", (_lines[-3:] or []) + _err_tail)
    elif _lines and _lines[0].startswith("SKIP"):
        skip("Lua 煙霧測試（smoke_harness.lua）", _lines[0])
    else:
        fail("Lua 煙霧測試（smoke_harness.lua）", ["無輸出"]) if not _lines \
            else ok(f"Lua 煙霧測試（{_lines[-1]}）")

sys.exit(1 if failed else 0)
