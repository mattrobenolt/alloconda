import json
import zipfile
from pathlib import Path

import click

from .cli_helpers import (
    detect_module_name,
    get_extension_suffix,
    resolve_library_path,
    resolve_package_dir,
)

EXTENSION_ENDINGS = (".so", ".pyd", ".dll", ".dylib")


@click.command()
@click.option(
    "--lib",
    "lib_path",
    type=click.Path(path_type=Path),
    help="Path to built library (default: zig-out/lib)",
)
@click.option("--module", "module_name", help="Override module name (PyInit_*)")
@click.option(
    "--package-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Python package directory to inspect",
)
@click.option(
    "--wheel",
    "wheel_path",
    type=click.Path(path_type=Path),
    help="Inspect a built wheel instead of a library",
)
@click.option("--verify", is_flag=True, help="Fail if required files are missing")
@click.option("--json", "as_json", is_flag=True, help="Emit JSON output")
def inspect(
    lib_path: Path | None,
    module_name: str | None,
    package_dir: Path | None,
    wheel_path: Path | None,
    verify: bool,
    as_json: bool,
) -> None:
    """Inspect a library or wheel and print derived metadata."""
    if wheel_path and lib_path:
        raise click.ClickException("Use either --wheel or --lib, not both")

    data: dict[str, object] = {"extension_suffix": get_extension_suffix()}

    if wheel_path:
        if not wheel_path.exists():
            raise click.ClickException(f"Wheel not found: {wheel_path}")
        data.update(inspect_wheel(wheel_path, verify))
    else:
        lib = resolve_library_path(lib_path)
        module_name = module_name or detect_module_name(lib)
        data.update(inspect_library(lib, module_name, package_dir))

    if as_json:
        click.echo(json.dumps(data, indent=2, sort_keys=True))
        return

    print_human(data)


def inspect_library(
    lib_path: Path,
    module_name: str,
    package_dir: Path | None,
) -> dict[str, object]:
    info: dict[str, object] = {
        "library": str(lib_path),
        "module_name": module_name,
    }
    try:
        pkg = resolve_package_dir(package_dir)
    except click.ClickException:
        pkg = package_dir
    if pkg:
        info["package_dir"] = str(pkg)
    return info


def inspect_wheel(wheel_path: Path, verify: bool) -> dict[str, object]:
    with zipfile.ZipFile(wheel_path) as zf:
        names = zf.namelist()

    dist_info_files = [
        name
        for name in names
        if name.endswith(
            (".dist-info/WHEEL", ".dist-info/METADATA", ".dist-info/RECORD")
        )
    ]
    extension_files = [name for name in names if name.endswith(EXTENSION_ENDINGS)]

    if verify:
        required = {".dist-info/WHEEL", ".dist-info/METADATA", ".dist-info/RECORD"}
        missing = [
            suffix
            for suffix in required
            if not any(name.endswith(suffix) for name in names)
        ]
        if missing:
            raise click.ClickException(f"Wheel missing files: {', '.join(missing)}")
        if not extension_files:
            raise click.ClickException("Wheel missing extension module")

    return {
        "wheel": str(wheel_path),
        "dist_info_files": dist_info_files,
        "extension_files": extension_files,
    }


def print_human(data: dict[str, object]) -> None:
    click.echo(f"extension_suffix: {data['extension_suffix']}")
    if "wheel" in data:
        click.echo(f"wheel: {data['wheel']}")
        extension_files = data.get("extension_files")
        dist_info_files = data.get("dist_info_files")
        ext_count = len(extension_files) if isinstance(extension_files, list) else 0
        dist_count = len(dist_info_files) if isinstance(dist_info_files, list) else 0
        click.echo(f"extension_files: {ext_count}")
        click.echo(f"dist_info_files: {dist_count}")
        return

    click.echo(f"library: {data.get('library')}")
    click.echo(f"module_name: {data.get('module_name')}")
    if "package_dir" in data:
        click.echo(f"package_dir: {data.get('package_dir')}")
