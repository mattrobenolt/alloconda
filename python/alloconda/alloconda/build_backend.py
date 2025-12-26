from __future__ import annotations

import tarfile
import tempfile
import zipfile
from pathlib import Path
from typing import Any

from .cli_helpers import (
    build_extension,
    config_list,
    find_project_dir,
    normalize_dist_name,
    read_project_metadata,
    read_tool_alloconda,
    resolve_package_dir,
    should_include_path,
)
from .wheel_builder import (
    build_wheel as build_wheel_impl,
)
from .wheel_builder import (
    format_metadata,
    resolve_wheel_tags,
    write_record,
)

OPTIMIZE_CHOICES = {"ReleaseSafe", "ReleaseFast", "ReleaseSmall"}


def build_wheel(
    wheel_directory: str,
    config_settings: dict[str, Any] | None = None,
    metadata_directory: str | None = None,
) -> str:
    settings = _normalize_config_settings(config_settings)
    project_dir = _resolve_project_dir(settings.get("project-dir"))
    tool_config = read_tool_alloconda(project_dir)
    settings = _merge_config(tool_config, settings)
    release = _resolve_release(settings, default_release=True)
    wheel_path = build_wheel_impl(
        release=release,
        optimize=_resolve_optimize(settings, release),
        zig_target=settings.get("zig-target"),
        lib_path=_path_setting(settings, "lib"),
        module_name=settings.get("module-name"),
        package_dir=_path_setting(settings, "package-dir"),
        python_version=settings.get("python-version"),
        pbs_target=settings.get("pbs-target"),
        python_cache=_path_setting(settings, "python-cache"),
        ext_suffix=settings.get("ext-suffix"),
        out_dir=Path(wheel_directory),
        project_dir=project_dir,
        python_tag=settings.get("python-tag"),
        abi_tag=settings.get("abi-tag"),
        platform_tag=settings.get("platform-tag"),
        manylinux=settings.get("manylinux"),
        musllinux=settings.get("musllinux"),
        arch=settings.get("arch"),
        build_step=_string_setting(settings, "build-step"),
        no_init=_bool_setting(settings, "no-init", False),
        force_init=_bool_setting(settings, "force-init", False),
        skip_build=_bool_setting(settings, "skip-build", False),
        include=config_list(settings, "include"),
        exclude=config_list(settings, "exclude"),
        fetch=_bool_setting(settings, "fetch", True),
    )
    return wheel_path.name


def build_editable(
    wheel_directory: str,
    config_settings: dict[str, Any] | None = None,
    metadata_directory: str | None = None,
) -> str:
    settings = _normalize_config_settings(config_settings)
    project_dir = _resolve_project_dir(settings.get("project-dir"))
    tool_config = read_tool_alloconda(project_dir)
    settings = _merge_config(tool_config, settings)
    package_dir = _resolve_package_dir(settings.get("package-dir"), project_dir)

    release = _resolve_release(settings, default_release=True)
    build_extension(
        release=release,
        optimize=_resolve_optimize(settings, release),
        module_name=settings.get("module-name"),
        lib_path=_path_setting(settings, "lib"),
        package_dir=package_dir,
        ext_suffix=settings.get("ext-suffix"),
        zig_target=settings.get("zig-target"),
        python_include=settings.get("python-include"),
        build_step=_string_setting(settings, "build-step"),
        no_init=_bool_setting(settings, "no-init", False),
        force_init=_bool_setting(settings, "force-init", False),
        skip_build=_bool_setting(settings, "skip-build", False),
        workdir=project_dir,
    )

    metadata = read_project_metadata(project_dir, package_dir)
    tags = resolve_wheel_tags(
        python_tag=settings.get("python-tag"),
        abi_tag=settings.get("abi-tag"),
        platform_tag=settings.get("platform-tag"),
        manylinux=settings.get("manylinux"),
        musllinux=settings.get("musllinux"),
        arch=settings.get("arch"),
    )

    dist_name = normalize_dist_name(metadata.name)
    wheel_name = f"{dist_name}-{metadata.version}-{tags.python_tag}-{tags.abi_tag}-{tags.platform_tag}.whl"
    wheel_path = Path(wheel_directory) / wheel_name

    _write_editable_wheel(
        wheel_path, metadata, dist_name, tags, project_dir, package_dir
    )
    return wheel_path.name


def prepare_metadata_for_build_wheel(
    metadata_directory: str,
    config_settings: dict[str, Any] | None = None,
) -> str:
    settings = _normalize_config_settings(config_settings)
    project_dir = _resolve_project_dir(settings.get("project-dir"))
    tool_config = read_tool_alloconda(project_dir)
    settings = _merge_config(tool_config, settings)
    package_dir = _resolve_package_dir(settings.get("package-dir"), project_dir)
    metadata = read_project_metadata(project_dir, package_dir)
    dist_name = normalize_dist_name(metadata.name)
    dist_info = f"{dist_name}-{metadata.version}.dist-info"
    out_dir = Path(metadata_directory) / dist_info
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "METADATA").write_text(format_metadata(metadata))
    return dist_info


prepare_metadata_for_build_editable = prepare_metadata_for_build_wheel


def build_sdist(
    sdist_directory: str,
    config_settings: dict[str, Any] | None = None,
) -> str:
    settings = _normalize_config_settings(config_settings)
    project_dir = _resolve_project_dir(settings.get("project-dir"))
    tool_config = read_tool_alloconda(project_dir)
    settings = _merge_config(tool_config, settings)
    metadata = read_project_metadata(project_dir, None)
    dist_name = normalize_dist_name(metadata.name)
    archive_name = f"{dist_name}-{metadata.version}.tar.gz"
    archive_path = Path(sdist_directory) / archive_name
    root = project_dir
    include = config_list(settings, "include")
    exclude = config_list(settings, "exclude")

    with tarfile.open(archive_path, "w:gz") as tf:
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(root).as_posix()
            if _is_sdist_ignored(path):
                continue
            if not should_include_path(rel, include, exclude):
                continue
            tf.add(path, arcname=f"{dist_name}-{metadata.version}/{rel}")

    return archive_path.name


def get_requires_for_build_wheel(
    config_settings: dict[str, Any] | None = None,
) -> list[str]:
    return []


def get_requires_for_build_editable(
    config_settings: dict[str, Any] | None = None,
) -> list[str]:
    return []


def get_requires_for_build_sdist(
    config_settings: dict[str, Any] | None = None,
) -> list[str]:
    return []


def _write_editable_wheel(
    wheel_path: Path,
    metadata,
    dist_name: str,
    tags,
    project_dir: Path,
    package_dir: Path,
) -> None:
    dist_info = f"{dist_name}-{metadata.version}.dist-info"
    pth_root = project_dir if package_dir == project_dir else package_dir.parent
    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp)
        dist_info_dir = staging / dist_info
        dist_info_dir.mkdir()

        (dist_info_dir / "METADATA").write_text(format_metadata(metadata))
        (dist_info_dir / "WHEEL").write_text(
            "\n".join(
                [
                    "Wheel-Version: 1.0",
                    "Generator: alloconda",
                    "Root-Is-Purelib: true",
                    f"Tag: {tags.python_tag}-{tags.abi_tag}-{tags.platform_tag}",
                    "",
                ]
            )
        )

        (staging / f"{dist_name}.pth").write_text(str(pth_root.resolve()) + "\n")

        write_record(staging, dist_info_dir)

        with zipfile.ZipFile(wheel_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(staging.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(staging).as_posix())


def _resolve_project_dir(setting: str | None) -> Path:
    if setting:
        return Path(setting).resolve()
    return find_project_dir(Path.cwd()) or Path.cwd()


def _resolve_package_dir(setting: str | None, project_dir: Path) -> Path:
    if setting:
        return Path(setting)
    return resolve_package_dir(None, base_dir=project_dir)


def _normalize_config_settings(
    config_settings: dict[str, Any] | None,
) -> dict[str, Any]:
    if not config_settings:
        return {}
    normalized = {}
    for key, value in config_settings.items():
        normalized[key.lstrip("-").replace("_", "-")] = value
    return normalized


def _merge_config(base: dict[str, Any], overrides: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    merged.update(overrides)
    return merged


def _bool_setting(settings: dict[str, Any], key: str, default: bool) -> bool:
    value = settings.get(key, default)
    if isinstance(value, list):
        if not value:
            return default
        value = value[-1]
    if isinstance(value, str):
        if value == "":
            return True
        return value.lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _path_setting(settings: dict[str, Any], key: str) -> Path | None:
    value = settings.get(key)
    if isinstance(value, list):
        if not value:
            return None
        value = value[-1]
    if value:
        return Path(value)
    return None


def _string_setting(settings: dict[str, Any], key: str) -> str | None:
    value = settings.get(key)
    if isinstance(value, list):
        if not value:
            return None
        value = value[-1]
    if value is None:
        return None
    return str(value)


def _resolve_release(settings: dict[str, Any], default_release: bool) -> bool:
    debug = _bool_setting(settings, "debug", False)
    if debug:
        return False
    return _bool_setting(settings, "release", default_release)


def _resolve_optimize(settings: dict[str, Any], release: bool) -> str | None:
    if not release:
        return "Debug"
    value = _string_setting(settings, "optimize")
    if value is None:
        return None
    if value not in OPTIMIZE_CHOICES:
        raise ValueError(
            f"Unsupported optimize mode: {value}. "
            f"Use one of: {', '.join(sorted(OPTIMIZE_CHOICES))}"
        )
    return value


def _is_sdist_ignored(path: Path) -> bool:
    parts = set(path.parts)
    ignored = {
        ".git",
        ".zig-cache",
        "zig-out",
        ".venv",
        "dist",
        "__pycache__",
        ".pytest_cache",
        ".ruff_cache",
        ".mypy_cache",
    }
    return bool(parts & ignored)
