"""程序化生成 UI 圓角皮膚貼圖（規格沿用 NoticeBoard repo docs/UI_SKIN_TEXTURES.md §2-§4，檔名前綴改 mui_）。

輸出到 42/media/ui/MinidoracatUI/：4 張 17x17 的 NinePatchTexture 9-slice（半徑 6、切線 6/4/6；
roundtop 縱向 6/10/0）＋ 1 張 16x16 未讀圓點。全白 RGB、alpha 為形狀（8x8 覆蓋率 AA），
純確定性計算，重跑產物逐位元組相同；生成後自檢並印 alpha 表／反解析結果／md5。

用法：python -B scripts/gen_ui_textures.py [--out DIR]
改半徑／尺寸：改 CONTENT_SIZE／make_nine_patch 內的 6、5、15、16 與參考表後重跑。
"""
from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

from PIL import Image


SUPERSAMPLE = 8
CONTENT_SIZE = 16
NINE_PATCH_SIZE = 17
WHITE = (255, 255, 255)
OUTPUT_NAMES = (
    "mui_round_fill.png",
    "mui_round_border.png",
    "mui_roundtop_fill.png",
    "mui_roundtop_border.png",
    "mui_dot.png",
)


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


def make_dot() -> Image.Image:
    alpha = []
    for y in range(CONTENT_SIZE):
        row = []
        for x in range(CONTENT_SIZE):
            row.append(coverage_alpha(circle_coverage(x, y, 8, 8, 8)))
        alpha.append(row)
    return image_from_alpha(alpha)


def generate_images(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    gitkeep = output_dir / ".gitkeep"
    if gitkeep.exists():
        gitkeep.unlink()  # scaffold 佔位檔；貼圖進駐後目錄非空，嚴格 assert 只認 5 張 PNG
    images = (
        ("mui_round_fill.png", make_nine_patch(border=False, top_only=False)),
        ("mui_round_border.png", make_nine_patch(border=True, top_only=False)),
        ("mui_roundtop_fill.png", make_nine_patch(border=False, top_only=True)),
        ("mui_roundtop_border.png", make_nine_patch(border=True, top_only=True)),
        ("mui_dot.png", make_dot()),
    )
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


def verify_image(path: Path) -> dict[str, object]:
    expected_size = (16, 16) if path.name == "mui_dot.png" else (17, 17)

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
    if path.name != "mui_dot.png":
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
        "size": size,
        "mode": mode,
        "alpha": alpha,
        "stats": stats,
        "nine_patch": nine_patch,
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
