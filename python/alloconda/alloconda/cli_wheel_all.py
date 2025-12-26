from dataclasses import dataclass
from pathlib import Path

import click

from .cli_helpers import (
    OPTIMIZE_CHOICES,
    config_bool,
    config_list,
    config_path,
    config_value,
    find_project_dir,
    read_tool_alloconda,
    resolve_arch,
    resolve_optimize_mode,
    resolve_pbs_target,
    resolve_release_mode,
)
from .pbs import (
    cache_root,
    fetch_and_extract,
    fetch_release_assets,
    find_cached_entry,
    resolve_versions_for_target,
    select_asset,
)
from .wheel_builder import build_wheel


@dataclass(frozen=True)
class WheelTarget:
    platform_tag: str
    arch: str
    manylinux: str | None = None
    musllinux: str | None = None
    pbs_target: str | None = None


DEFAULT_TARGETS = (
    WheelTarget("macosx_14_0_arm64", "arm64", pbs_target="aarch64-apple-darwin"),
    WheelTarget("macosx_11_0_x86_64", "x86_64", pbs_target="x86_64-apple-darwin"),
    WheelTarget("manylinux_2_28_x86_64", "x86_64", manylinux="2_28"),
    WheelTarget("manylinux_2_28_aarch64", "aarch64", manylinux="2_28"),
)

MUSLLINUX_TARGETS = (
    WheelTarget("musllinux_1_2_x86_64", "x86_64", musllinux="1_2"),
    WheelTarget("musllinux_1_2_aarch64", "aarch64", musllinux="1_2"),
)

WINDOWS_TARGETS = (
    WheelTarget("win_amd64", "x86_64", pbs_target="x86_64-pc-windows-msvc"),
)


@click.command("wheel-all")
@click.option("--release", is_flag=True, help="Build with -Doptimize=ReleaseFast")
@click.option("--debug", is_flag=True, help="Build with -Doptimize=Debug")
@click.option(
    "--optimize",
    type=click.Choice(OPTIMIZE_CHOICES),
    help="Override release optimization",
)
@click.option(
    "--python-version",
    "versions",
    multiple=True,
    help="Python version to build (repeatable, e.g. 3.13 or 3.13.1)",
)
@click.option(
    "--all", "all_versions", is_flag=True, help="Build all available versions"
)
@click.option(
    "--target",
    "targets",
    multiple=True,
    help="Platform tag to build (repeatable, e.g. manylinux_2_28_x86_64)",
)
@click.option("--include-musllinux", is_flag=True, help="Include musllinux targets")
@click.option("--include-windows", is_flag=True, help="Include Windows targets")
@click.option(
    "--package-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Python package directory to package",
)
@click.option(
    "--project-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Project root containing pyproject.toml",
)
@click.option(
    "--out-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Output directory for wheels (default: dist/)",
)
@click.option(
    "--cache-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Cache directory for python-build-standalone",
)
@click.option(
    "--fetch/--no-fetch",
    default=True,
    help="Fetch missing headers automatically",
)
@click.option("--dry-run", is_flag=True, help="Print the build matrix and exit")
@click.option("--no-init", is_flag=True, help="Skip __init__.py generation")
@click.option("--force-init", is_flag=True, help="Overwrite existing __init__.py")
def wheel_all(
    release: bool,
    debug: bool,
    optimize: str | None,
    versions: tuple[str, ...],
    all_versions: bool,
    targets: tuple[str, ...],
    include_musllinux: bool,
    include_windows: bool,
    package_dir: Path | None,
    project_dir: Path | None,
    out_dir: Path | None,
    cache_dir: Path | None,
    fetch: bool,
    dry_run: bool,
    no_init: bool,
    force_init: bool,
) -> None:
    """Build a multi-platform wheel matrix from cached python headers."""
    project_root = project_dir or find_project_dir(Path.cwd())
    config = read_tool_alloconda(project_root, package_dir)

    if not versions and not all_versions:
        config_versions = config_list(config, "python-version")
        if config_versions:
            versions = tuple(config_versions)
    if not versions and not all_versions:
        raise click.ClickException("Provide --python-version or --all")

    if not targets:
        config_targets = config_list(config, "targets", "target")
        if config_targets:
            targets = tuple(config_targets)

    package_dir = package_dir or config_path(config, project_root, "package-dir")
    project_dir = project_dir or config_path(config, project_root, "project-dir")
    out_dir = out_dir or config_path(config, project_root, "out-dir")
    cache_dir = cache_dir or config_path(config, project_root, "python-cache")
    build_step = config_value(config, "build-step")
    no_init = no_init or config_bool(config, "no-init")
    force_init = force_init or config_bool(config, "force-init")
    module_name = config_value(config, "module-name")
    include = config_list(config, "include")
    exclude = config_list(config, "exclude")
    release = resolve_release_mode(
        release_flag=release,
        debug_flag=debug,
        config=config,
        default_release=True,
    )
    optimize = resolve_optimize_mode(
        release=release,
        optimize_flag=optimize,
        config=config,
    )

    if targets:
        target_defs = [parse_target(t) for t in targets]
    else:
        target_defs = list(DEFAULT_TARGETS)
        if include_musllinux:
            target_defs.extend(MUSLLINUX_TARGETS)
        if include_windows:
            target_defs.extend(WINDOWS_TARGETS)

    assets = fetch_release_assets() if (all_versions or fetch) else []
    cache_dir = cache_root(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)

    matrix = []
    for target in target_defs:
        pbs_target = resolve_pbs_target(
            target.pbs_target,
            target.platform_tag,
            target.manylinux,
            target.musllinux,
            target.arch,
        )
        if all_versions:
            version_list = resolve_versions_for_target(assets, pbs_target)
        else:
            version_list = list(versions)

        for version in version_list:
            matrix.append((version, target, pbs_target))

    if dry_run:
        for version, target, pbs_target in matrix:
            click.echo(
                f"{version} -> {target.platform_tag} (pbs {pbs_target}, arch {target.arch})"
            )
        return

    for version, target, pbs_target in matrix:
        cached = find_cached_entry(cache_dir, version, pbs_target)
        if cached is None:
            if not fetch:
                raise click.ClickException(
                    "Python headers not cached. Re-run with --fetch or "
                    f"alloconda python fetch --version {version} --pbs-target {pbs_target}"
                )
            asset = select_asset(assets, version, pbs_target)
            fetch_and_extract(asset, cache_dir, force=False, show_progress=True)

        zig_target = zig_target_for(target)
        wheel_path = build_wheel(
            release=release,
            optimize=optimize,
            zig_target=zig_target,
            lib_path=None,
            module_name=module_name,
            package_dir=package_dir,
            python_version=version,
            pbs_target=pbs_target,
            python_cache=cache_dir,
            ext_suffix=None,
            out_dir=out_dir,
            project_dir=project_dir,
            python_tag=None,
            abi_tag=None,
            platform_tag=None
            if target.manylinux or target.musllinux
            else target.platform_tag,
            manylinux=target.manylinux,
            musllinux=target.musllinux,
            arch=resolve_arch(target.arch),
            build_step=build_step,
            no_init=no_init,
            force_init=force_init,
            skip_build=False,
            include=include,
            exclude=exclude,
        )
        click.echo(f"✓ Built {wheel_path}")


def parse_target(value: str) -> WheelTarget:
    if value.startswith(("manylinux", "musllinux", "macosx")):
        base, arch = split_tag_arch(value)

    if value.startswith("manylinux"):
        manylinux = base.replace("manylinux", "").strip("_") or "2014"
        return WheelTarget(value, arch, manylinux=manylinux)

    if value.startswith("musllinux"):
        musllinux = base.replace("musllinux", "").strip("_")
        return WheelTarget(value, arch, musllinux=musllinux)

    if value.startswith("macosx"):
        return WheelTarget(value, arch, pbs_target=f"{resolve_arch(arch)}-apple-darwin")

    if value.startswith("win"):
        arch = "x86_64" if value == "win_amd64" else "aarch64"
        return WheelTarget(
            value, arch, pbs_target=f"{resolve_arch(arch)}-pc-windows-msvc"
        )

    raise click.ClickException(f"Unsupported platform tag: {value}")


def split_tag_arch(value: str) -> tuple[str, str]:
    arches = [
        "x86_64",
        "aarch64",
        "arm64",
        "armv7l",
        "ppc64le",
        "s390x",
    ]
    for arch in arches:
        suffix = f"_{arch}"
        if value.endswith(suffix):
            return value[: -len(suffix)], arch
    raise click.ClickException(f"Could not parse architecture from {value}")


def zig_target_for(target: WheelTarget) -> str | None:
    arch = resolve_arch(target.arch)
    if target.platform_tag.startswith("macosx"):
        return f"{arch}-macos"
    if target.platform_tag.startswith("win"):
        return f"{arch}-windows-msvc"
    return None
