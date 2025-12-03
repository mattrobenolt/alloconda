import platform
import shutil
import subprocess
import sysconfig
from pathlib import Path

import click


@click.group()
def main():
    pass

@main.command()
@click.option("--release", is_flag=True, help="Build in release mode")
def build(release: bool):
    cmd = ["zig", "build"]
    if release:
        cmd.append("-Doptimize=ReleaseFast")

    click.echo(f"Running: {cmd}")
    subprocess.run(cmd, check=True)

    module_name = "zigadd"
    src = Path.cwd() / "zig-out" / "lib" / f"lib{module_name}.dylib"
    dst = Path.cwd() / f"{module_name}{get_extension_suffix()}"

    click.echo(f"Renaming {src} -> {dst}")
    shutil.copy(src, dst)

    click.echo(f"✓ Built {dst}")

def get_so_suffix() -> str:
    match (p := platform.system()):
        case "Darwin":
            return "dylib"
        case "Linux":
            return "so"
        case _:
            raise Exception(f"Unsupported platform: {p}")



def get_extension_suffix() -> str:
    return sysconfig.get_config_var('EXT_SUFFIX')

if __name__ == "__main__":
    main()
