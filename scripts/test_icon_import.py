"""驗證預設舊圖表與明確指定新圖表；所有產物只寫入暫存目錄。"""
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

REPO = Path(__file__).resolve().parent.parent
LEGACY_KEYS = "house,skull,pawprint,steeringwheel,chicken,cow,pig,sheep,deer,rabbit,raccoon,rodent,turkey"


def run_import(sheet, output, keys=None):
    args = [sys.executable, str(REPO / "scripts/import_icon_sheet.py"), str(sheet), "--out", str(output)]
    if keys is not None:
        args.extend(["--keys", keys])
    result = subprocess.run(args, capture_output=True, text=True, encoding="utf-8")
    assert result.returncode == 0, result.stdout + result.stderr
    return {path.name: path.read_bytes() for path in output.glob("*.png")}


def main():
    with TemporaryDirectory(prefix="mui-icon-import-") as temporary:
        root = Path(temporary)
        sheet = REPO / "scripts/icons/sheet.png"
        default = run_import(sheet, root / "default")
        explicit = run_import(sheet, root / "explicit", LEGACY_KEYS)
        assert set(default) == {f"mui_art_{key}.png" for key in LEGACY_KEYS.split(",")}
        assert default == explicit, "預設舊圖表的 key 排列或像素發生改變"

        source = json.loads((REPO / "scripts/icons/navigation-source.json").read_text(encoding="utf-8"))
        keys = ",".join(key for row in source["request"]["row_major_order"] for key in row)
        navigation = run_import(REPO / source["output_path"], root / "navigation", keys)
        shipped = REPO / source["import"]["output_directory"]
        assert set(navigation) == set(source["import"]["output_files"])
        for name, data in navigation.items():
            assert data == (shipped / name).read_bytes(), f"導覽圖示無法重現：{name}"
    print("Icon import passed: legacy default/explicit match; navigation matches shipped assets")


if __name__ == "__main__":
    main()
