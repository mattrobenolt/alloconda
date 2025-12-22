import json
import zipfile
from pathlib import Path

import click

from .cli_helpers import (
    detect_module_name,
    get_extension_suffix,
    normalize_dist_name,
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
    errors: list[str] = []
    with zipfile.ZipFile(wheel_path) as zf:
        names = zf.namelist()

        dist_info_dirs = sorted(
            {
                name.split("/", 1)[0]
                for name in names
                if name.endswith(".dist-info/WHEEL")
                or name.endswith(".dist-info/METADATA")
                or name.endswith(".dist-info/RECORD")
            }
        )
        dist_info_dir = dist_info_dirs[0] if len(dist_info_dirs) == 1 else None
        if not dist_info_dirs:
            errors.append("missing .dist-info directory")
        elif len(dist_info_dirs) > 1:
            errors.append("multiple .dist-info directories found")

        dist_info_files = [
            name
            for name in names
            if name.endswith(
                (".dist-info/WHEEL", ".dist-info/METADATA", ".dist-info/RECORD")
            )
        ]
        extension_files = [name for name in names if name.endswith(EXTENSION_ENDINGS)]

        required = {".dist-info/WHEEL", ".dist-info/METADATA", ".dist-info/RECORD"}
        missing = [
            suffix
            for suffix in required
            if not any(name.endswith(suffix) for name in names)
        ]
        if missing:
            errors.append(f"missing files: {', '.join(missing)}")
        if not extension_files:
            errors.append("missing extension module")

        metadata = None
        wheel_tags: list[str] = []
        if dist_info_dir:
            metadata_text = _read_zip_text(zf, f"{dist_info_dir}/METADATA")
            wheel_text = _read_zip_text(zf, f"{dist_info_dir}/WHEEL")
            if metadata_text is None:
                errors.append("missing METADATA file")
            else:
                metadata = parse_metadata(metadata_text)

            if wheel_text is None:
                errors.append("missing WHEEL file")
            else:
                wheel_tags = parse_wheel_tags(wheel_text)
                if not wheel_tags:
                    errors.append("WHEEL file has no Tag entries")

        filename_tags = parse_wheel_filename(wheel_path.name)
        if filename_tags and wheel_tags:
            expected_tag = (
                f"{filename_tags['python_tag']}-"
                f"{filename_tags['abi_tag']}-"
                f"{filename_tags['platform_tag']}"
            )
            if expected_tag not in wheel_tags:
                errors.append("filename tag missing from WHEEL tags")

        if metadata and dist_info_dir:
            name = metadata.get("Name")
            version = metadata.get("Version")
            if name and version:
                expected = f"{normalize_dist_name(name)}-{version}.dist-info"
                if dist_info_dir != expected:
                    errors.append("dist-info directory does not match metadata")

    if verify and errors:
        raise click.ClickException("; ".join(errors))

    return {
        "wheel": str(wheel_path),
        "dist_info_dir": dist_info_dir,
        "dist_info_files": dist_info_files,
        "extension_files": extension_files,
        "metadata": metadata,
        "wheel_tags": wheel_tags,
        "filename_tags": filename_tags,
        "valid": not errors,
        "errors": errors,
    }


def _read_zip_text(zf: zipfile.ZipFile, name: str) -> str | None:
    try:
        return zf.read(name).decode("utf-8")
    except KeyError:
        return None


def parse_metadata(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    current_key: str | None = None
    for line in text.splitlines():
        if not line.strip():
            current_key = None
            continue
        if line[0].isspace() and current_key:
            values[current_key] += "\n" + line.strip()
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip()
        current_key = key.strip()
    return values


def parse_wheel_tags(text: str) -> list[str]:
    tags = []
    for line in text.splitlines():
        if line.startswith("Tag:"):
            tags.append(line.split(":", 1)[1].strip())
    return tags


def parse_wheel_filename(filename: str) -> dict[str, str]:
    if not filename.endswith(".whl"):
        return {}
    stem = filename[:-4]
    parts = stem.split("-")
    if len(parts) < 5:
        return {}
    python_tag, abi_tag, platform_tag = parts[-3:]
    version = parts[-4]
    name = "-".join(parts[:-4])
    return {
        "distribution": name,
        "version": version,
        "python_tag": python_tag,
        "abi_tag": abi_tag,
        "platform_tag": platform_tag,
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
        if data.get("valid") is False:
            errors = data.get("errors")
            if isinstance(errors, list) and errors:
                click.echo(f"validation_errors: {len(errors)}")
        return

    click.echo(f"library: {data.get('library')}")
    click.echo(f"module_name: {data.get('module_name')}")
    if "package_dir" in data:
        click.echo(f"package_dir: {data.get('package_dir')}")
