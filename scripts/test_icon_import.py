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

        for record in ("navigation", "vehicle"):
            source = json.loads((REPO / f"scripts/icons/{record}-source.json").read_text(encoding="utf-8"))
            keys = ",".join(key for row in source["request"]["row_major_order"] for key in row)
            imported = run_import(REPO / source["output_path"], root / record, keys)
            shipped = REPO / source["import"]["output_directory"]
            assert set(imported) == set(source["import"]["output_files"])
            for name, data in imported.items():
                assert data == (shipped / name).read_bytes(), f"{record} 圖示無法重現：{name}"
    print("Icon import passed: legacy default/explicit match; navigation/vehicle match shipped assets")


if __name__ == "__main__":
    main()
