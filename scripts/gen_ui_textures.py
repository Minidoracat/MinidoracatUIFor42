"""程序化生成 UI 皮膚貼圖與圖示（皮膚規格沿用 NoticeBoard repo docs/UI_SKIN_TEXTURES.md §2-§4，
檔名前綴改 mui_）。

輸出到 42/media/ui/MinidoracatUI/，兩類資產：
  皮膚（7 張）：既有 4 張 17x17 NinePatchTexture、1 張 16x16 圓點，以及 rev 3
    專用的 2 張 25x25 pill 9-slice（10/4/10 cap，精確 20px 高）。
  圖示（20 張）：32x32 單色線性圖示，描邊 3px、端點與轉折一律圓頭、無漸層無陰影、
    外圍留 1px 透明邊；32px 原稿供 14-20px 顯示（16px 是乾淨的 2:1 降採樣）。

兩類都是全白 RGB、alpha 為形狀（8x8 覆蓋率 AA）、運行時頂點染色，一套資產服務所有主題。
純確定性計算（不用 ImageDraw，避免跨 Pillow 版本的柵格化差異），重跑產物逐位元組相同；
生成後自檢並印統計／皮膚 alpha 表／圖示 16px ASCII 預覽／md5。

用法：python -B scripts/gen_ui_textures.py [--out DIR]
改半徑／尺寸：同步改 CONTENT_SIZE／PILL_CONTENT_SIZE／PILL_CORNER、make_nine_patch
    與 make_pill_patch 的切線常數及對應參考表後重跑。
改圖示：改 icon_shapes() 的幾何與 ICON_SPECS 的探針座標後重跑（兩者互為交叉檢查）。
"""
from __future__ import annotations

import argparse
import hashlib
import math
import struct
from pathlib import Path

from PIL import Image


SUPERSAMPLE = 8
CONTENT_SIZE = 16
NINE_PATCH_SIZE = 17
PILL_CONTENT_SIZE = 24
PILL_NINE_PATCH_SIZE = 25
PILL_CORNER = 10
ICON_SIZE = 32
ICON_STROKE_HALF = 1.5  # 描邊半寬；總寬 3px＝32px 邊長的 9.4%，縮到 16px 顯示為 1.5px
WHITE = (255, 255, 255)
SKIN_NAMES = (
    "mui_round_fill.png",
    "mui_round_border.png",
    "mui_roundtop_fill.png",
    "mui_roundtop_border.png",
    "mui_pill_fill.png",
    "mui_pill_border.png",
    "mui_dot.png",
)
ICON_NAMES = (
    "mui_icon_sidebar.png",
    "mui_icon_folder.png",
    "mui_icon_document.png",
    "mui_icon_chevron_right.png",
    "mui_icon_chevron_down.png",
    "mui_icon_language.png",
    "mui_icon_reload.png",
    "mui_icon_reset_size.png",
    "mui_icon_search.png",
    "mui_icon_chevron_left.png",
    "mui_icon_layers.png",
    "mui_icon_pin.png",
    "mui_icon_globe.png",
    "mui_icon_sliders.png",
    "mui_icon_gauge.png",
    "mui_icon_lock.png",
    "mui_icon_unlock.png",
    "mui_icon_close.png",
    "mui_icon_locate.png",
    "mui_icon_copy.png",
)
# art 圖示：AI 生成剪影經 scripts/import_icon_sheet.py 轉成 32×32 純白 alpha PNG
# 後 commit；不由本檔幾何生成（generate_images 不覆寫、不刪，缺檔＝assert），verify 走
# assert_art_icon_content（尺寸／純白／1px 透明邊／著墨比例／有 AA 過渡），不比對幾何。
ART_ICON_NAMES = tuple(
    f"mui_art_{key}.png" for key in (
        "house", "skull", "pawprint", "steeringwheel",
        "chicken", "cow", "pig", "sheep", "deer", "rabbit", "raccoon", "rodent", "turkey",
        "wallet", "gift", "shop", "market",
        "auction", "mail", "users", "chart",
        "coins", "plug", "shieldCheck", "tag",
        "transactions", "clipboardCheck", "server", "settings",
    )
)
OUTPUT_NAMES = SKIN_NAMES + ICON_NAMES + ART_ICON_NAMES


def parse_alpha_table(text: str) -> tuple[tuple[int, ...], ...]:
    rows = tuple(tuple(int(value) for value in line.split()) for line in text.strip().splitlines())
    assert len(rows) == NINE_PATCH_SIZE
    assert all(len(row) == NINE_PATCH_SIZE for row in rows)
    return rows


ROUND_FILL_REFERENCE = parse_alpha_table(
    """
      0   0   0   0   0   0   0 255 255 255 255   0   0   0   0   0   0
      0   0   0   8 112 203 251 255 255 255 255 251 203 112   8   0   0
      0   0  24 211 255 255 255 255 255 255 255 255 255 255 211  24   0
      0   8 211 255 255 255 255 255 255 255 255 255 255 255 255 211   8
      0 112 255 255 255 255 255 255 255 255 255 255 255 255 255 255 112
      0 203 255 255 255 255 255 255 255 255 255 255 255 255 255 255 203
      0 251 255 255 255 255 255 255 255 255 255 255 255 255 255 255 251
    255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255
    255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255
    255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255
    255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255
      0 251 255 255 255 255 255 255 255 255 255 255 255 255 255 255 251
      0 203 255 255 255 255 255 255 255 255 255 255 255 255 255 255 203
      0 112 255 255 255 255 255 255 255 255 255 255 255 255 255 255 112
      0   8 211 255 255 255 255 255 255 255 255 255 255 255 255 211   8
      0   0  24 211 255 255 255 255 255 255 255 255 255 255 211  24   0
      0   0   0   8 112 203 251 255 255 255 255 251 203 112   8   0   0
    """
)


ROUND_BORDER_REFERENCE = parse_alpha_table(
    """
      0   0   0   0   0   0   0 255 255 255 255   0   0   0   0   0   0
      0   0   0   8 112 203 251 255 255 255 255 251 203 112   8   0   0
      0   0  24 211 179  60   8   0   0   0   0   8  60 179 211  24   0
      0   8 211 112   0   0   0   0   0   0   0   0   0   0 112 211   8
      0 112 179   0   0   0   0   0   0   0   0   0   0   0   0 179 112
      0 203  60   0   0   0   0   0   0   0   0   0   0   0   0  60 203
      0 251   8   0   0   0   0   0   0   0   0   0   0   0   0   8 251
    255 255   0   0   0   0   0   0   0   0   0   0   0   0   0   0 255
    255 255   0   0   0   0   0   0   0   0   0   0   0   0   0   0 255
    255 255   0   0   0   0   0   0   0   0   0   0   0   0   0   0 255
    255 255   0   0   0   0   0   0   0   0   0   0   0   0   0   0 255
      0 251   8   0   0   0   0   0   0   0   0   0   0   0   0   8 251
      0 203  60   0   0   0   0   0   0   0   0   0   0   0   0  60 203
      0 112 179   0   0   0   0   0   0   0   0   0   0   0   0 179 112
      0   8 211 112   0   0   0   0   0   0   0   0   0   0 112 211   8
      0   0  24 211 179  60   8   0   0   0   0   8  60 179 211  24   0
      0   0   0   8 112 203 251 255 255 255 255 251 203 112   8   0   0
    """
)


def point_in_rrect(
    px: float,
    py: float,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    radius: float,
    top_only: bool,
) -> bool:
    if not (x0 <= px < x1 and y0 <= py < y1):
        return False

    if px < x0 + radius and py < y0 + radius:
        cx, cy = x0 + radius, y0 + radius
    elif px >= x1 - radius and py < y0 + radius:
        cx, cy = x1 - radius, y0 + radius
    elif not top_only and px < x0 + radius and py >= y1 - radius:
        cx, cy = x0 + radius, y1 - radius
    elif not top_only and px >= x1 - radius and py >= y1 - radius:
        cx, cy = x1 - radius, y1 - radius
    else:
        return True

    return (px - cx) ** 2 + (py - cy) ** 2 <= radius**2


def rrect_coverage(
    x: int,
    y: int,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    radius: float,
    top_only: bool,
) -> float:
    covered = 0
    for j in range(SUPERSAMPLE):
        py = y + (j + 0.5) / SUPERSAMPLE
        for i in range(SUPERSAMPLE):
            px = x + (i + 0.5) / SUPERSAMPLE
            covered += point_in_rrect(px, py, x0, y0, x1, y1, radius, top_only)
    return covered / (SUPERSAMPLE * SUPERSAMPLE)


def circle_coverage(x: int, y: int, cx: float, cy: float, radius: float) -> float:
    covered = 0
    for j in range(SUPERSAMPLE):
        py = y + (j + 0.5) / SUPERSAMPLE
        for i in range(SUPERSAMPLE):
            px = x + (i + 0.5) / SUPERSAMPLE
            covered += (px - cx) ** 2 + (py - cy) ** 2 <= radius**2
    return covered / (SUPERSAMPLE * SUPERSAMPLE)


def coverage_alpha(coverage: float) -> int:
    return round(coverage * 255)


def image_from_alpha(alpha: list[list[int]]) -> Image.Image:
    height = len(alpha)
    width = len(alpha[0])
    assert all(len(row) == width for row in alpha)
    image = Image.new("RGBA", (width, height))
    image.putdata([WHITE + (value,) for row in alpha for value in row])
    return image


def make_nine_patch(border: bool, top_only: bool) -> Image.Image:
    alpha = [[0] * NINE_PATCH_SIZE for _ in range(NINE_PATCH_SIZE)]

    for cy in range(CONTENT_SIZE):
        for cx in range(CONTENT_SIZE):
            outer = rrect_coverage(cx, cy, 0, 0, 16, 16, 6, top_only)
            if border:
                inner_y1 = 16 if top_only else 15
                inner = rrect_coverage(cx, cy, 1, 1, 15, inner_y1, 5, top_only)
                coverage = max(0.0, outer - inner)
            else:
                coverage = outer
            alpha[cy + 1][cx + 1] = coverage_alpha(coverage)

    for x in range(7, 11):
        alpha[0][x] = 255
    vertical_marker_end = 17 if top_only else 11
    for y in range(7, vertical_marker_end):
        alpha[y][0] = 255

    return image_from_alpha(alpha)


def make_pill_patch(border: bool) -> Image.Image:
    alpha = [[0] * PILL_NINE_PATCH_SIZE for _ in range(PILL_NINE_PATCH_SIZE)]
    for cy in range(PILL_CONTENT_SIZE):
        for cx in range(PILL_CONTENT_SIZE):
            outer = rrect_coverage(cx, cy, 0, 0, PILL_CONTENT_SIZE, PILL_CONTENT_SIZE,
                                   PILL_CORNER, False)
            if border:
                inner = rrect_coverage(cx, cy, 1, 1, PILL_CONTENT_SIZE - 1,
                                       PILL_CONTENT_SIZE - 1, PILL_CORNER - 1, False)
                coverage = max(0.0, outer - inner)
            else:
                coverage = outer
            alpha[cy + 1][cx + 1] = coverage_alpha(coverage)

    for position in range(PILL_CORNER + 1, PILL_CORNER + 5):
        alpha[0][position] = 255
        alpha[position][0] = 255
    return image_from_alpha(alpha)


def make_dot() -> Image.Image:
    alpha = []
    for y in range(CONTENT_SIZE):
        row = []
        for x in range(CONTENT_SIZE):
            row.append(coverage_alpha(circle_coverage(x, y, 8, 8, 8)))
        alpha.append(row)
    return image_from_alpha(alpha)


# ============================================================
# 圖示幾何工具（回傳「點在形狀內」謂詞；覆蓋率沿用皮膚同一套 8x8 超取樣）
# ============================================================
# 為什麼不用 ImageDraw：柵格化細節跨 Pillow 版本會變，而本檔的契約是「重跑逐位元組
# 相同」。純浮點謂詞＋自家超取樣是唯一能同時保證確定性與抗鋸齒品質的做法。


def segment_distance_sq(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    if length_sq <= 0.0:
        return (px - ax) ** 2 + (py - ay) ** 2
    t = ((px - ax) * dx + (py - ay) * dy) / length_sq
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    return (px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2


def stroke_path(points, closed: bool = False, half: float = ICON_STROKE_HALF):
    """折線描邊：與任一段的距離 ≤ half 即命中——端點與轉折自然成為圓頭／圓角。"""
    segments = list(zip(points, points[1:]))
    if closed:
        segments.append((points[-1], points[0]))
    limit = half * half

    def inside(px: float, py: float) -> bool:
        for (ax, ay), (bx, by) in segments:
            if segment_distance_sq(px, py, ax, ay, bx, by) <= limit:
                return True
        return False

    return inside


def rrect_sdf(px: float, py: float, x0: float, y0: float, x1: float, y1: float,
              radius: float) -> float:
    """圓角矩形的有號距離（內負外正）；矩形的內距離也精確，描邊寬度因此處處均勻。"""
    qx = abs(px - (x0 + x1) / 2.0) - ((x1 - x0) / 2.0 - radius)
    qy = abs(py - (y0 + y1) / 2.0) - ((y1 - y0) / 2.0 - radius)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - radius


def rrect_fill(x0: float, y0: float, x1: float, y1: float, radius: float):
    def inside(px: float, py: float) -> bool:
        return rrect_sdf(px, py, x0, y0, x1, y1, radius) <= 0.0

    return inside


def rrect_outline(x0: float, y0: float, x1: float, y1: float, radius: float,
                  half: float = ICON_STROKE_HALF):
    def inside(px: float, py: float) -> bool:
        return abs(rrect_sdf(px, py, x0, y0, x1, y1, radius)) <= half

    return inside


def ring(cx: float, cy: float, radius: float, half: float = ICON_STROKE_HALF):
    def inside(px: float, py: float) -> bool:
        return abs(math.hypot(px - cx, py - cy) - radius) <= half

    return inside


def arc(cx: float, cy: float, radius: float, start_deg: float, end_deg: float,
        half: float = ICON_STROKE_HALF):
    """圓弧描邊（兩端圓頭）。角度採螢幕座標：0°＝正右，遞增為順時針（y 向下）。"""
    span = end_deg - start_deg
    caps = tuple(
        (cx + radius * math.cos(math.radians(angle)), cy + radius * math.sin(math.radians(angle)))
        for angle in (start_deg, end_deg)
    )
    limit = half * half

    def inside(px: float, py: float) -> bool:
        if abs(math.hypot(px - cx, py - cy) - radius) <= half:
            if (math.degrees(math.atan2(py - cy, px - cx)) - start_deg) % 360.0 <= span:
                return True
        for ax, ay in caps:
            if (px - ax) ** 2 + (py - ay) ** 2 <= limit:
                return True
        return False

    return inside


def ellipse_outline(cx: float, cy: float, a: float, b: float, half: float = ICON_STROKE_HALF):
    """橢圓描邊。距離取一階估計 F/|grad F|（本尺度誤差 <0.2px、AA 吃不出來），
    以免為了解析距離跑逐點牛頓疊代——那會讓「確定性」多背一組收斂條件。"""
    def inside(px: float, py: float) -> bool:
        dx, dy = px - cx, py - cy
        value = (dx / a) ** 2 + (dy / b) ** 2 - 1.0
        gradient = math.hypot(2.0 * dx / (a * a), 2.0 * dy / (b * b))
        if gradient <= 1e-9:  # 正中心；離環面極遠，直接判外
            return False
        return abs(value / gradient) <= half

    return inside


def polygon_fill(points):
    """凸多邊形填色（箭頭用）：對所有邊的外積同號即在內部，與頂點繞向無關。"""
    edges = tuple(zip(points, points[1:] + points[:1]))

    def inside(px: float, py: float) -> bool:
        positive = negative = False
        for (ax, ay), (bx, by) in edges:
            cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
            if cross > 0.0:
                positive = True
            elif cross < 0.0:
                negative = True
            if positive and negative:
                return False
        return True

    return inside


def icon_shapes() -> dict:
    """二十個圖示的幾何定義（座標＝32x32 貼圖像素，左上為原點，整數座標落在像素邊界）。

    共同語彙：主描邊 3px、端點與轉折圓頭、無漸層無陰影、內容全部落在 [1, 31] 之間
    （外圍 1px 透明邊，verify 會逐張確認——被裁到邊的圖示縮小後會黏在按鈕框上）。
    基本形刻意壓到最少：多數圖示 1-3 個，定位／座標複合語意最多 5 個；縮到 16px 仍須可辨。
    """
    return {
        # 面板框＋左欄實心：16px 下實心色塊比「框內再畫一條分隔線」清楚得多
        "mui_icon_sidebar.png": (
            rrect_outline(3, 6, 29, 26, 3.5),
            rrect_fill(3, 6, 10.5, 26, 2.5),
        ),
        # 資料夾：單一封閉折線（左緣→頁籤→斜切→本體），轉折靠圓頭自然成圓角
        "mui_icon_folder.png": (
            stroke_path([(3, 25), (3, 7), (11, 7), (13.5, 10), (29, 10), (29, 25)], closed=True),
        ),
        # 文件：右上截角的頁面外框＋摺角兩段線
        "mui_icon_document.png": (
            stroke_path([(6.5, 3.5), (19.5, 3.5), (25.5, 9.5), (25.5, 28.5), (6.5, 28.5)],
                        closed=True),
            stroke_path([(19.5, 3.5), (19.5, 9.5), (25.5, 9.5)]),
        ),
        "mui_icon_chevron_right.png": (
            stroke_path([(12.5, 7), (20.5, 16), (12.5, 25)]),
        ),
        # 與 chevron_right 是同一組頂點繞 (16,16) 逆時針轉 90°——兩者筆勢必須一致
        "mui_icon_chevron_down.png": (
            stroke_path([(7, 12.5), (16, 20.5), (25, 12.5)]),
        ),
        # 地球：外圈＋赤道＋經線橢圓，三筆到底（再加一條緯線在 16px 就糊了）
        "mui_icon_language.png": (
            ring(16, 16, 11.5),
            stroke_path([(4.5, 16), (27.5, 16)]),
            ellipse_outline(16, 16, 5.5, 11.5),
        ),
        # 重新載入：300° 圓弧（缺口留在右上）＋頂端箭頭指向缺口，指示順時針
        "mui_icon_reload.png": (
            arc(16, 16, 10.5, -30.0, 270.0),
            polygon_fill([(20.2, 5.5), (15.2, 2.3), (15.2, 8.7)]),
        ),
        # 重設大小：前窗＝預設尺寸的完整框，後窗只露上緣與右緣（避免內部交叉線）
        "mui_icon_reset_size.png": (
            rrect_outline(6, 11, 21, 26, 2.5),
            stroke_path([(11, 11), (11, 6), (26, 6), (26, 21), (21, 21)]),
        ),
        "mui_icon_search.png": (
            ring(13, 13, 8.5),
            stroke_path([(19, 19), (27.5, 27.5)]),
        ),
        "mui_icon_chevron_left.png": (
            stroke_path([(19.5, 7), (11.5, 16), (19.5, 25)]),
        ),
        "mui_icon_layers.png": (
            stroke_path([(5, 11), (16, 5), (27, 11), (16, 17)], closed=True),
            stroke_path([(5, 16), (16, 22), (27, 16)]),
            stroke_path([(5, 21), (16, 27), (27, 21)]),
        ),
        "mui_icon_pin.png": (
            stroke_path([(16, 28), (8, 12), (8, 9), (10, 5), (13, 3), (16, 2.5),
                         (19, 3), (22, 5), (24, 9), (24, 12)], closed=True),
            ring(16, 10, 3),
        ),
        "mui_icon_globe.png": (
            ring(16, 16, 11.5),
            stroke_path([(16, 4.5), (16, 27.5)]),
            ellipse_outline(16, 16, 11.5, 5.5),
        ),
        "mui_icon_sliders.png": (
            stroke_path([(4, 7), (28, 7)]),
            stroke_path([(4, 16), (28, 16)]),
            stroke_path([(4, 25), (28, 25)]),
            rrect_fill(8, 4, 14, 10, 3),
            rrect_fill(19, 13, 25, 19, 3),
            rrect_fill(11, 22, 17, 28, 3),
        ),
        "mui_icon_gauge.png": (
            arc(16, 21, 11, 180, 360),
            stroke_path([(16, 21), (22, 12)]),
            ring(16, 21, 2.5),
        ),
        "mui_icon_lock.png": (
            rrect_outline(6, 12, 26, 28, 3),
            arc(16, 12, 7, 180, 360),
            rrect_fill(14, 18, 18, 24, 2),
        ),
        "mui_icon_unlock.png": (
            rrect_outline(6, 13, 26, 28, 3),
            stroke_path([(10, 13), (10, 10)]),
            arc(17, 10, 7, 180, 350),
            rrect_fill(14, 19, 18, 25, 2),
        ),
        "mui_icon_close.png": (
            stroke_path([(8, 8), (24, 24)]),
            stroke_path([(24, 8), (8, 24)]),
        ),
        "mui_icon_locate.png": (
            stroke_path([(12, 4), (4, 4), (4, 12)]),
            stroke_path([(20, 4), (28, 4), (28, 12)]),
            stroke_path([(4, 20), (4, 28), (12, 28)]),
            stroke_path([(28, 20), (28, 28), (20, 28)]),
            ring(16, 16, 3.5),
        ),
        "mui_icon_copy.png": (
            rrect_outline(7, 7, 25, 29, 2.5),
            rrect_outline(12, 3, 20, 9, 2),
            stroke_path([(12, 17), (20, 17)]),
            stroke_path([(16, 13), (16, 21)]),
            stroke_path([(12, 25), (20, 25)]),
        ),
    }


# 圖示驗證探針：symmetry（h＝上下鏡射、v＝左右鏡射）＋必須實心／必須全透明的像素。
# 探針是幾何定義的獨立交叉檢查——座標由設計時的筆畫位置手算，改幾何而忘了改探針會紅。
ICON_SPECS = {
    "mui_icon_sidebar.png": {
        "symmetry": "h",
        "solid": ((16, 6), (6, 16)),        # 上緣描邊、左欄實心
        "clear": ((20, 16), (16, 16)),      # 右側面板留白
    },
    "mui_icon_folder.png": {
        "symmetry": "",
        "solid": ((16, 25), (3, 16)),       # 下緣、左緣
        "clear": ((16, 16), (20, 4)),       # 內部留白、頁籤上方無物
    },
    "mui_icon_document.png": {
        "symmetry": "",
        "solid": ((16, 28), (7, 16), (22, 6)),   # 下緣、左緣、右上斜切
        "clear": ((16, 16), (24, 4)),            # 內部留白、被切掉的右上角
    },
    "mui_icon_chevron_right.png": {
        "symmetry": "h",
        "solid": ((19, 15),),
        "clear": ((12, 16), (16, 3)),       # 尖端朝右：中線左側必須空（朝左就會紅）
    },
    "mui_icon_chevron_down.png": {
        "symmetry": "v",
        "solid": ((15, 19),),
        "clear": ((16, 12), (3, 16)),       # 尖端朝下：中線上方必須空
    },
    "mui_icon_language.png": {
        "symmetry": "hv",
        "solid": ((16, 4), (16, 16)),       # 外圈頂點、赤道
        "clear": ((8, 12),),                # 經線與外圈之間的鏡片區
    },
    "mui_icon_reload.png": {
        "symmetry": "",
        "solid": ((16, 5), (16, 26)),       # 箭頭本體、圓弧底部
        "clear": ((16, 16), (24, 7)),       # 圓心、右上缺口（缺口消失就不是循環箭頭了）
    },
    "mui_icon_reset_size.png": {
        "symmetry": "",
        "solid": ((16, 6), (16, 26)),       # 後窗上緣、前窗下緣
        "clear": ((16, 16), (8, 8)),        # 前窗內部、兩窗錯位讓出的左上角
    },
    "mui_icon_search.png": {
        "symmetry": "",
        "solid": ((13, 4), (24, 24)),
        "clear": ((13, 13), (27, 4)),
    },
    "mui_icon_chevron_left.png": {
        "symmetry": "h",
        "solid": ((12, 15),),
        "clear": ((20, 16), (16, 3)),
    },
    "mui_icon_layers.png": {
        "symmetry": "v",
        "solid": ((16, 5), (16, 27)),
        "clear": ((16, 12), (3, 3)),
    },
    "mui_icon_pin.png": {
        "symmetry": "v",
        "solid": ((16, 27), (16, 7)),
        "clear": ((16, 10), (5, 10)),
    },
    "mui_icon_globe.png": {
        "symmetry": "hv",
        "solid": ((16, 4), (16, 16)),
        "clear": ((11, 8),),
    },
    "mui_icon_sliders.png": {
        "symmetry": "",
        "solid": ((11, 7), (22, 16), (14, 25)),
        "clear": ((16, 4), (4, 12)),
    },
    "mui_icon_gauge.png": {
        "symmetry": "",
        "solid": ((5, 20), (16, 10), (21, 13)),
        "clear": ((16, 27), (6, 7)),
    },
    "mui_icon_lock.png": {
        "symmetry": "v",
        "solid": ((16, 5), (16, 20), (16, 27)),
        "clear": ((10, 18), (4, 4)),
    },
    "mui_icon_unlock.png": {
        "symmetry": "",
        "solid": ((10, 12), (17, 3), (16, 21), (16, 27)),
        "clear": ((25, 11), (17, 10), (4, 4)),
    },
    "mui_icon_close.png": {
        "symmetry": "hv",
        "solid": ((16, 16), (9, 9)),
        "clear": ((16, 5), (4, 4)),
    },
    "mui_icon_locate.png": {
        "symmetry": "hv",
        "solid": ((4, 8), (16, 12), (24, 28)),
        "clear": ((16, 4), (4, 16), (16, 16)),
    },
    "mui_icon_copy.png": {
        "symmetry": "v",
        "solid": ((7, 16), (16, 3), (16, 17), (16, 28)),
        "clear": ((10, 12), (4, 4)),
    },
}

assert tuple(ICON_SPECS) == ICON_NAMES, "ICON_SPECS 與 ICON_NAMES 必須逐項對應"


def shape_coverage(x: int, y: int, shapes) -> float:
    """圖示版的像素覆蓋率（對應皮膚的 rrect_coverage／circle_coverage）：沿用同一組
    8x8 取樣點，形狀之間取聯集——重疊處不疊加，交叉筆畫才不會爆成雙倍 alpha。"""
    covered = 0
    for j in range(SUPERSAMPLE):
        py = y + (j + 0.5) / SUPERSAMPLE
        for i in range(SUPERSAMPLE):
            px = x + (i + 0.5) / SUPERSAMPLE
            covered += any(shape(px, py) for shape in shapes)
    return covered / (SUPERSAMPLE * SUPERSAMPLE)


def icon_alpha(shapes) -> list[list[int]]:
    return [
        [coverage_alpha(shape_coverage(x, y, shapes)) for x in range(ICON_SIZE)]
        for y in range(ICON_SIZE)
    ]


def generate_images(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    gitkeep = output_dir / ".gitkeep"
    if gitkeep.exists():
        gitkeep.unlink()  # scaffold 佔位檔；貼圖進駐後目錄非空，嚴格 assert 只認 OUTPUT_NAMES
    images = [
        ("mui_round_fill.png", make_nine_patch(border=False, top_only=False)),
        ("mui_round_border.png", make_nine_patch(border=True, top_only=False)),
        ("mui_roundtop_fill.png", make_nine_patch(border=False, top_only=True)),
        ("mui_roundtop_border.png", make_nine_patch(border=True, top_only=True)),
        ("mui_pill_fill.png", make_pill_patch(border=False)),
        ("mui_pill_border.png", make_pill_patch(border=True)),
        ("mui_dot.png", make_dot()),
    ]
    shapes = icon_shapes()
    assert tuple(shapes) == ICON_NAMES, "icon_shapes() 與 ICON_NAMES 必須逐項對應"
    for filename in ICON_NAMES:
        images.append((filename, image_from_alpha(icon_alpha(shapes[filename]))))
    for filename, image in images:
        with image:
            image.save(output_dir / filename, format="PNG")

    actual_entries = {entry.name for entry in output_dir.iterdir()}
    assert actual_entries == set(OUTPUT_NAMES), (
        f"Unexpected output directory entries: {sorted(actual_entries - set(OUTPUT_NAMES))}"
    )


def parse_marker_axis(values: list[int]) -> tuple[int, int, int]:
    start = 0
    end = len(values)
    for index, alpha in enumerate(values):
        if alpha < 128:
            if start != 0:
                end = index
                break
        elif start == 0:
            start = index
    start = max(start - 1, 0)
    end = max(end - 1, 0)
    return start, end - start, len(values) - 1 - end


def parse_nine_patch(alpha: list[list[int]]) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    widths = parse_marker_axis(alpha[0])
    heights = parse_marker_axis([row[0] for row in alpha])
    return widths, heights


def read_png_ihdr(path: Path) -> tuple[int, int, int, int, int, int, int]:
    with path.open("rb") as stream:
        assert stream.read(8) == b"\x89PNG\r\n\x1a\n", f"Invalid PNG signature: {path.name}"
        chunk_types = []
        ihdr_data = None
        while True:
            length_bytes = stream.read(4)
            assert len(length_bytes) == 4, f"Truncated PNG: {path.name}"
            length = struct.unpack(">I", length_bytes)[0]
            chunk_type = stream.read(4)
            chunk_data = stream.read(length)
            assert len(chunk_type) == 4 and len(chunk_data) == length
            assert len(stream.read(4)) == 4, f"Missing chunk CRC: {path.name}"
            chunk_types.append(chunk_type)
            if chunk_type == b"IHDR":
                assert ihdr_data is None and length == 13
                ihdr_data = chunk_data
            if chunk_type == b"IEND":
                break

    assert chunk_types[0] == b"IHDR" and chunk_types[-1] == b"IEND"
    assert set(chunk_types) <= {b"IHDR", b"IDAT", b"IEND"}, (
        f"Unexpected PNG metadata chunks in {path.name}: {chunk_types}"
    )
    assert ihdr_data is not None
    return struct.unpack(">IIBBBBB", ihdr_data)


def assert_nine_patch_content(
    filename: str,
    alpha: list[list[int]],
    widths: tuple[int, int, int],
    heights: tuple[int, int, int],
) -> None:
    if filename.startswith("mui_pill_"):
        border = "border" in filename
        assert widths == (10, 4, 10), f"Unexpected widths for {filename}: {widths}"
        assert heights == (10, 4, 10), f"Unexpected heights for {filename}: {heights}"
        assert alpha[0][0] == 0
        assert all(alpha[0][x] == (255 if 11 <= x <= 14 else 0)
                   for x in range(PILL_NINE_PATCH_SIZE))
        assert all(alpha[y][0] == (255 if 11 <= y <= 14 else 0)
                   for y in range(PILL_NINE_PATCH_SIZE))
        content = [row[1:] for row in alpha[1:]]
        assert all(row == row[::-1] for row in content)
        assert all(content[y] == content[-1 - y] for y in range(PILL_CONTENT_SIZE))
        assert alpha[1][1] == 0 and alpha[1][24] == 0
        assert alpha[12][12] == (0 if border else 255)
        assert alpha[1][11] == 255 and alpha[24][14] == 255
        values = [value for row in content for value in row]
        assert any(0 < value < 255 for value in values)
        return

    top_only = "roundtop" in filename
    border = "border" in filename
    expected_heights = (6, 10, 0) if top_only else (6, 4, 6)

    assert widths == (6, 4, 6), f"Unexpected widths for {filename}: {widths}"
    assert heights == expected_heights, f"Unexpected heights for {filename}: {heights}"
    assert alpha[0][0] == 0, f"Marker origin must be transparent: {filename}"
    assert all(alpha[0][x] == 0 for x in (*range(1, 7), *range(11, 17)))
    assert all(alpha[0][x] == 255 for x in range(7, 11))

    non_marker_rows = range(1, 7) if top_only else (*range(1, 7), *range(11, 17))
    marker_rows = range(7, 17) if top_only else range(7, 11)
    assert all(alpha[y][0] == 0 for y in non_marker_rows)
    assert all(alpha[y][0] == 255 for y in marker_rows)

    reference_column = [alpha[y][7] for y in range(1, 17)]
    for x in range(8, 11):
        assert [alpha[y][x] for y in range(1, 17)] == reference_column

    stretch_rows = range(7, 17) if top_only else range(7, 11)
    reference_row = alpha[7][1:17]
    for y in stretch_rows:
        assert alpha[y][1:17] == reference_row

    assert alpha[8][8] == (0 if border else 255)
    assert alpha[1][1] == 0 and alpha[1][16] == 0
    if top_only:
        assert alpha[16][1] == 255 and alpha[16][16] == 255
        lower_content = ([255] * 16) if not border else ([255] + [0] * 14 + [255])
        assert all(alpha[y][1:17] == lower_content for y in range(7, 17))
    else:
        assert alpha[16][1] == 0 and alpha[16][16] == 0

    if filename == "mui_round_fill.png":
        assert tuple(map(tuple, alpha)) == ROUND_FILL_REFERENCE
    elif filename == "mui_round_border.png":
        assert tuple(map(tuple, alpha)) == ROUND_BORDER_REFERENCE
    elif filename == "mui_roundtop_fill.png":
        assert tuple(map(tuple, alpha[:7])) == ROUND_FILL_REFERENCE[:7]
    elif filename == "mui_roundtop_border.png":
        assert tuple(map(tuple, alpha[:7])) == ROUND_BORDER_REFERENCE[:7]


ASCII_RAMP = " .:-=+*#%@"


def ascii_preview(alpha: list[list[int]], block: int = 2) -> list[str]:
    """把 32x32 alpha 降採樣成 16x16 ASCII——等同遊戲內 16px 的顯示尺寸，
    人眼一眼就能看出圖示糊掉／筆畫黏死；印 32x32 數字表對圖示毫無可讀性。"""
    rows = []
    for y in range(0, len(alpha), block):
        line = []
        for x in range(0, len(alpha[y]), block):
            total = sum(alpha[y + j][x + i] for j in range(block) for i in range(block))
            level = total // (block * block * 26)
            line.append(ASCII_RAMP[min(level, len(ASCII_RAMP) - 1)])
        rows.append("".join(line))
    return rows


def assert_icon_content(filename: str, alpha: list[list[int]]) -> float:
    spec = ICON_SPECS[filename]
    last = ICON_SIZE - 1
    expected_alpha = icon_alpha(icon_shapes()[filename])
    assert alpha == expected_alpha, (
        f"{filename}: committed PNG does not match deterministic icon_shapes geometry"
    )

    # 1px 透明邊：內容貼到邊緣的圖示縮小後會黏在按鈕框上，且左右／上下留白不對稱
    assert all(alpha[0][x] == 0 and alpha[last][x] == 0 for x in range(ICON_SIZE)), (
        f"{filename}: 上／下邊未留 1px 透明邊"
    )
    assert all(alpha[y][0] == 0 and alpha[y][last] == 0 for y in range(ICON_SIZE)), (
        f"{filename}: 左／右邊未留 1px 透明邊"
    )

    if "h" in spec["symmetry"]:
        assert all(alpha[y] == alpha[last - y] for y in range(ICON_SIZE)), (
            f"{filename}: 應上下鏡射對稱"
        )
    if "v" in spec["symmetry"]:
        assert all(row == row[::-1] for row in alpha), f"{filename}: 應左右鏡射對稱"

    for x, y in spec["solid"]:
        assert alpha[y][x] == 255, f"{filename}: ({x},{y}) 應為實心筆畫，實得 {alpha[y][x]}"
    for x, y in spec["clear"]:
        assert alpha[y][x] == 0, f"{filename}: ({x},{y}) 應為全透明，實得 {alpha[y][x]}"

    values = [value for row in alpha for value in row]
    # 純白 RGB 下 alpha 就是整張圖：沒有實心＝沒畫到、沒有透明＝畫成滿版、
    # 沒有半透明＝AA 失效（超取樣被改壞），三者都是資產級事故
    assert max(values) == 255, f"{filename}: 沒有任何實心像素"
    assert min(values) == 0, f"{filename}: 沒有任何全透明像素"
    assert any(0 < value < 255 for value in values), f"{filename}: 邊緣沒有 AA 過渡"

    # 著墨比例：整張空白（幾何全落在畫布外）或整張實心（謂詞恆真）都會被這條擋下
    ratio = sum(1 for value in values if value > 0) / float(ICON_SIZE * ICON_SIZE)
    assert 0.05 <= ratio <= 0.50, f"{filename}: 著墨比例 {ratio:.3f} 不在 0.05-0.50 之間"
    return ratio


def assert_art_icon_content(filename: str, alpha: list[list[int]]) -> float:
    """art 圖示驗證：非幾何生成，只驗與 consumer 契約相關的性質。"""
    last = ICON_SIZE - 1
    assert all(alpha[0][x] == 0 and alpha[last][x] == 0 for x in range(ICON_SIZE)), (
        f"{filename}: 上／下邊未留 1px 透明邊"
    )
    assert all(alpha[y][0] == 0 and alpha[y][last] == 0 for y in range(ICON_SIZE)), (
        f"{filename}: 左／右邊未留 1px 透明邊"
    )
    values = [value for row in alpha for value in row]
    assert any(0 < value < 255 for value in values), f"{filename}: 無 AA 過渡（未經 import_icon_sheet 縮放）"
    ratio = sum(1 for value in values if value > 0) / float(ICON_SIZE * ICON_SIZE)
    assert 0.10 <= ratio <= 0.70, f"{filename}: 著墨比例 {ratio:.3f} 不在 0.10-0.70 之間（剪影應為實心）"
    return ratio


def verify_image(path: Path) -> dict[str, object]:
    is_icon = path.name in ICON_SPECS
    is_art = path.name in ART_ICON_NAMES
    if is_icon or is_art:
        expected_size = (ICON_SIZE, ICON_SIZE)
    elif path.name.startswith("mui_pill_"):
        expected_size = (PILL_NINE_PATCH_SIZE, PILL_NINE_PATCH_SIZE)
    elif path.name == "mui_dot.png":
        expected_size = (CONTENT_SIZE, CONTENT_SIZE)
    else:
        expected_size = (NINE_PATCH_SIZE, NINE_PATCH_SIZE)

    with Image.open(path) as verifier:
        verifier.verify()

    with Image.open(path) as image:
        image.load()
        assert image.size == expected_size, f"Unexpected size for {path.name}: {image.size}"
        assert image.mode == "RGBA", f"Unexpected mode for {path.name}: {image.mode}"
        raw = image.tobytes()  # RGBA 4 bytes/pixel；tobytes 各版 Pillow 都有（get_flattened_data 12.1 才有）
        pixels = [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)]
        size = image.size
        mode = image.mode

    assert all(pixel[:3] == (255, 255, 255) for pixel in pixels), f"Non-white RGB in {path.name}"

    width, height, bit_depth, color_type, compression, filter_method, interlace = read_png_ihdr(path)
    assert (width, height) == expected_size
    assert bit_depth == 8, f"Unexpected bit depth for {path.name}: {bit_depth}"
    assert color_type == 6, f"Unexpected color type for {path.name}: {color_type}"
    assert compression == 0 and filter_method == 0 and interlace == 0

    alpha = [[pixels[y * width + x][3] for x in range(width)] for y in range(height)]
    nine_patch = None
    ink = None
    if is_icon:
        ink = assert_icon_content(path.name, alpha)
    elif is_art:
        ink = assert_art_icon_content(path.name, alpha)
    elif path.name != "mui_dot.png":
        nine_patch = parse_nine_patch(alpha)
        assert_nine_patch_content(path.name, alpha, *nine_patch)
    else:
        assert alpha[8][8] == 255
        assert alpha[0][0] == alpha[0][15] == alpha[15][0] == alpha[15][15] == 0
        # 圓要頂到四邊中點（半徑 8、圓心 (8,8)），且左右／上下對稱：半徑縮水或偏心都會紅
        assert alpha[0][7] == alpha[0][8] == alpha[15][7] == alpha[15][8] == 255
        assert alpha[7][0] == alpha[8][0] == alpha[7][15] == alpha[8][15] == 255
        assert all(alpha[y] == alpha[y][::-1] for y in range(16))
        assert all(alpha[y] == alpha[15 - y] for y in range(16))

    alpha_values = [value for row in alpha for value in row]
    stats = {
        "zero": alpha_values.count(0),
        "full": alpha_values.count(255),
        "partial": sum(0 < value < 255 for value in alpha_values),
        "min": min(alpha_values),
        "max": max(alpha_values),
    }
    return {
        "filename": path.name,
        "kind": "icon" if (is_icon or is_art) else "skin",
        "size": size,
        "mode": mode,
        "alpha": alpha,
        "stats": stats,
        "nine_patch": nine_patch,
        "ink": ink,
    }


def md5_hex(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def print_report(reports: list[dict[str, object]], output_dir: Path) -> None:
    for report in reports:
        width, height = report["size"]
        stats = report["stats"]
        print(f'{report["filename"]}: size={width}x{height}, mode={report["mode"]}')
        print(
            "  alpha: "
            f'zero={stats["zero"]}, full={stats["full"]}, partial={stats["partial"]}, '
            f'min={stats["min"]}, max={stats["max"]}'
        )
        if report["kind"] == "icon":
            print(f'  ink: {report["ink"]:.3f}')
            print("  16px 預覽（2x2 降採樣，等同遊戲內顯示尺寸）：")
            for line in ascii_preview(report["alpha"]):
                print(f"    |{line}|")
            continue
        if report["nine_patch"] is None:
            print("  nine-slice: n/a")
        else:
            widths, heights = report["nine_patch"]
            print(f"  nine-slice: widths={widths}, heights={heights}")
        print("  alpha table:")
        for row in report["alpha"]:
            print(" ".join(f"{value:3d}" for value in row))

    print("MD5:")
    for filename in OUTPUT_NAMES:
        print(f"{filename}: {md5_hex(output_dir / filename)}")
    print("OK")


def default_output_dir() -> Path:
    repo_root = Path(__file__).resolve().parent.parent
    return (
        repo_root
        / "MOD"
        / "MinidoracatUIFor42"
        / "Contents"
        / "mods"
        / "MinidoracatUIFor42"
        / "42"
        / "media"
        / "ui"
        / "MinidoracatUI"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate deterministic MinidoracatUI textures.")
    parser.add_argument("--out", type=Path, help="Override the output directory.")
    args = parser.parse_args()
    output_dir = args.out.expanduser().resolve() if args.out else default_output_dir()

    generate_images(output_dir)
    reports = [verify_image(output_dir / filename) for filename in OUTPUT_NAMES]
    print_report(reports, output_dir)


if __name__ == "__main__":
    main()
