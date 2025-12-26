import base64
import hashlib
import shutil
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path

import click

from .cli_helpers import (
    ProjectMetadata,
    detect_module_name,
    find_project_dir,
    lib_suffix_for_target,
    normalize_dist_name,
    read_project_metadata,
    resolve_extension_suffix,
    resolve_library_path,
    resolve_package_dir,
    resolve_pbs_target,
    resolve_platform_tag,
    resolve_zig_target,
    run_zig_build,
    should_include_path,
    write_init_py,
)
from .pbs import (
    cache_root,
    fetch_and_extract,
    fetch_release_assets,
    find_cached_entry,
    select_asset,
)


@dataclass(frozen=True)
class WheelOptions:
    python_tag: str
    abi_tag: str
    platform_tag: str
    ext_suffix: str
    out_dir: Path
    no_init: bool
    force_init: bool
    include: list[str] | None
    exclude: list[str] | None


def build_wheel(
    *,
    release: bool,
    optimize: str | None,
    zig_target: str | None,
    lib_path: Path | None,
    module_name: str | None,
    package_dir: Path | None,
    python_version: str | None,
    pbs_target: str | None,
    python_cache: Path | None,
    ext_suffix: str | None,
    out_dir: Path | None,
    project_dir: Path | None,
    python_tag: str | None,
    abi_tag: str | None,
    platform_tag: str | None,
    manylinux: str | None,
    musllinux: str | None,
    arch: str | None,
    build_step: str | None,
    no_init: bool,
    force_init: bool,
    skip_build: bool,
    include: list[str] | None,
    exclude: list[str] | None,
    fetch: bool = True,
) -> Path:
    python_include = None
    if python_version:
        platform = resolve_platform_tag(platform_tag, manylinux, musllinux, arch)
        target = resolve_pbs_target(pbs_target, platform, manylinux, musllinux, arch)
        cache_dir = cache_root(python_cache)
        entry = find_cached_entry(cache_dir, python_version, target)
        if entry is None:
            if not fetch:
                raise click.ClickException(
                    "Python headers not cached. Run with --fetch or: "
                    f"alloconda python fetch --version {python_version} --pbs-target {target}"
                )
            assets = fetch_release_assets()
            asset = select_asset(assets, python_version, target)
            entry = fetch_and_extract(asset, cache_dir, force=False, show_progress=True)
        python_include = str(entry.include_dir)
        if ext_suffix is None:
            ext_suffix = entry.ext_suffix

    zig_target = resolve_zig_target(zig_target, manylinux, musllinux, arch)

    base_for_package = project_dir or Path.cwd()
    package_dir = resolve_package_dir(package_dir, base_dir=base_for_package)
    build_root = project_dir or find_project_dir(package_dir) or Path.cwd()

    if not skip_build:
        run_zig_build(
            release,
            zig_target,
            python_include,
            build_step=build_step,
            optimize=optimize,
            workdir=build_root,
        )

    metadata = read_project_metadata(project_dir, package_dir)

    if python_version and python_tag is None:
        parts = python_version.split(".")
        if len(parts) >= 2:
            python_tag = f"cp{parts[0]}{parts[1]}"
            if abi_tag is None:
                abi_tag = python_tag

    tags = resolve_wheel_tags(
        python_tag=python_tag,
        abi_tag=abi_tag,
        platform_tag=platform_tag,
        manylinux=manylinux,
        musllinux=musllinux,
        arch=arch,
    )

    lib_suffix = lib_suffix_for_target(zig_target, tags.platform_tag)
    lib_path = resolve_library_path(
        lib_path,
        base_dir=build_root,
        lib_suffix=lib_suffix,
    )
    if module_name is None:
        module_name = detect_module_name(lib_path)

    if (
        tags.platform_tag != platform_tag
        and ext_suffix is None
        and (manylinux or musllinux)
    ):
        click.echo(
            "Warning: using host extension suffix; pass --ext-suffix for cross builds."
        )

    wheel_opts = WheelOptions(
        python_tag=tags.python_tag,
        abi_tag=tags.abi_tag,
        platform_tag=tags.platform_tag,
        ext_suffix=resolve_extension_suffix(ext_suffix),
        out_dir=out_dir or (Path.cwd() / "dist"),
        no_init=no_init,
        force_init=force_init,
        include=include,
        exclude=exclude,
    )
    wheel_opts.out_dir.mkdir(parents=True, exist_ok=True)

    return assemble_wheel(
        lib_path=lib_path,
        module_name=module_name,
        package_dir=package_dir,
        metadata=metadata,
        opts=wheel_opts,
    )


@dataclass(frozen=True)
class WheelTags:
    python_tag: str
    abi_tag: str
    platform_tag: str


def resolve_wheel_tags(
    *,
    python_tag: str | None,
    abi_tag: str | None,
    platform_tag: str | None,
    manylinux: str | None,
    musllinux: str | None,
    arch: str | None,
) -> WheelTags:
    py_tag = python_tag or default_python_tag()
    abi = abi_tag or py_tag
    plat = resolve_platform_tag(platform_tag, manylinux, musllinux, arch)
    return WheelTags(py_tag, abi, plat)


def default_python_tag() -> str:
    impl = sys.implementation.name
    major = sys.version_info.major
    minor = sys.version_info.minor
    if impl == "cpython":
        return f"cp{major}{minor}"
    return f"{impl}{major}{minor}"


def assemble_wheel(
    *,
    lib_path: Path,
    module_name: str,
    package_dir: Path,
    metadata: ProjectMetadata,
    opts: WheelOptions,
) -> Path:
    dist_name = normalize_dist_name(metadata.name)
    wheel_name = f"{dist_name}-{metadata.version}-{opts.python_tag}-{opts.abi_tag}-{opts.platform_tag}.whl"
    wheel_path = opts.out_dir / wheel_name

    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp)
        staged_pkg = staging / package_dir.name
        copy_package_tree(
            package_dir, staged_pkg, opts.include, opts.exclude, module_name
        )

        ext_path = staged_pkg / f"{module_name}{opts.ext_suffix}"
        shutil.copy2(lib_path, ext_path)

        if not opts.no_init:
            write_init_py(staged_pkg, module_name, opts.force_init)

        dist_info = staging / f"{dist_name}-{metadata.version}.dist-info"
        dist_info.mkdir()

        (dist_info / "METADATA").write_text(format_metadata(metadata))
        (dist_info / "WHEEL").write_text(format_wheel(opts))

        write_record(staging, dist_info)

        with zipfile.ZipFile(wheel_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(staging.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(staging).as_posix())

    return wheel_path


def copy_package_tree(
    src: Path,
    dst: Path,
    include: list[str] | None,
    exclude: list[str] | None,
    module_name: str,
) -> None:
    for path in sorted(src.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(src).as_posix()
        if "__pycache__" in path.parts:
            continue
        if path.suffix in {".pyc", ".pyo"}:
            continue
        # Skip extension modules matching our module name - the correct one is copied separately
        if path.suffix in {".so", ".dylib", ".pyd"} and path.name.startswith(
            module_name
        ):
            continue
        if not should_include_path(rel, include, exclude):
            continue
        dest_path = dst / rel
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest_path)


def format_metadata(metadata: ProjectMetadata) -> str:
    lines = [
        "Metadata-Version: 2.1",
        f"Name: {metadata.name}",
        f"Version: {metadata.version}",
    ]
    if metadata.summary:
        lines.append(f"Summary: {metadata.summary}")
    if metadata.license:
        lines.append(f"License: {metadata.license}")
    for classifier in metadata.classifiers:
        lines.append(f"Classifier: {classifier}")
    if metadata.requires_python:
        lines.append(f"Requires-Python: {metadata.requires_python}")
    for dep in metadata.dependencies:
        lines.append(f"Requires-Dist: {dep}")
    return "\n".join(lines) + "\n"


def format_wheel(opts: WheelOptions) -> str:
    return "\n".join(
        [
            "Wheel-Version: 1.0",
            "Generator: alloconda",
            "Root-Is-Purelib: false",
            f"Tag: {opts.python_tag}-{opts.abi_tag}-{opts.platform_tag}",
            "",
        ]
    )


def write_record(root: Path, dist_info: Path) -> None:
    record_path = dist_info / "RECORD"
    entries = []

    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if path == record_path:
            entries.append((rel, "", ""))
            continue
        digest, size = hash_file(path)
        entries.append((rel, digest, size))

    record_path.write_text("\n".join(",".join(row) for row in entries) + "\n")


def hash_file(path: Path) -> tuple[str, str]:
    data = path.read_bytes()
    digest = hashlib.sha256(data).digest()
    b64 = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return f"sha256={b64}", str(len(data))
