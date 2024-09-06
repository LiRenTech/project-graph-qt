import argparse
import subprocess
from pathlib import Path

import PyInstaller.__main__

# 项目根目录，不是src
path = Path(__file__).parent

if not (path / "src" / "project_graph" / "assets" / "assets.py").exists():
    from PyQt5 import pyrcc_main


def main():
    parser = argparse.ArgumentParser()
    # 只编译assets文件
    parser.add_argument("--assets-only", action="store_true")
    args = parser.parse_args()
    # 生成assets
    if not (path / "src" / "project_graph" / "assets" / "assets.py").exists():
        pyrcc_main.processResourceFile(
            [(path / "src" / "project_graph" / "assets" / "image.rcc").as_posix()],
            (path / "src" / "project_graph" / "assets" / "assets.py").as_posix(),
            False,
        )
    if args.assets_only:
        return
    # 修改版本号
    with open(path / "src" / "project_graph" / "__init__.py", "r") as f:
        original_content = f.read()
    with open(path / "src" / "project_graph" / "__init__.py", "w") as f:
        f.write(
            f"""\
class INFO:
    commit = {subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()}
    date = {subprocess.check_output(["git", "log", "-1", "--format=%cd"]).decode().strip()}
    branch = {subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"]).decode().strip()}
    env = "prod"
"""
        )
    # 创建临时文件
    with open(path / "src" / "_package.py", "w") as f:
        f.write(
            "from project_graph.__main__ import main\nif __name__ == '__main__': main()"
        )
    # 打包
    PyInstaller.__main__.run(
        [
            "--onefile",
            "--windowed",
            f"--icon={path / 'src' / 'project_graph' / 'assets' / 'favicon.ico'}",
            "-n",
            "project-graph",
            (path / "src" / "_package.py").as_posix(),
        ]
    )
    # 还原版本号
    with open(path / "src" / "project_graph" / "__init__.py", "w") as f:
        f.write(original_content)
    # 删除临时文件
    (path / "src" / "_package.py").unlink()
