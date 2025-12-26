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
    resolve_optimize_mode,
    resolve_release_mode,
)
from .wheel_builder import build_wheel


@click.command()
@click.option("--release", is_flag=True, help="Build with -Doptimize=ReleaseFast")
@click.option("--debug", is_flag=True, help="Build with -Doptimize=Debug")
@click.option(
    "--optimize",
    type=click.Choice(OPTIMIZE_CHOICES),
    help="Override release optimization",
)
@click.option("--module", "module_name", help="Override module name (PyInit_*)")
@click.option(
    "--lib", "lib_path", type=click.Path(path_type=Path), help="Path to built library"
)
@click.option(
    "--package-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Python package directory to package",
)
@click.option("--python-version", help="Python version to use from cached headers")
@click.option("--pbs-target", help="Override python-build-standalone target triple")
@click.option(
    "--python-cache",
    type=click.Path(path_type=Path, file_okay=False),
    help="Cache directory for python-build-standalone",
)
@click.option(
    "--project-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Project root containing pyproject.toml",
)
@click.option("--python-tag", help="Wheel python tag, e.g. cp312")
@click.option("--abi-tag", help="Wheel ABI tag, e.g. cp312 or abi3")
@click.option("--platform-tag", help="Wheel platform tag, e.g. manylinux_2_28_x86_64")
@click.option("--manylinux", help="Manylinux policy (e.g. 2014, 2_28, manylinux_2_28)")
@click.option("--musllinux", help="Musllinux policy (e.g. 1_2, musllinux_1_2)")
@click.option("--arch", help="Override wheel architecture (e.g. x86_64, aarch64)")
@click.option("--ext-suffix", help="Override extension suffix for the module")
@click.option(
    "--out-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Output directory for wheels (default: dist/)",
)
@click.option("--zig-target", help="Zig target triple for cross builds")
@click.option("--skip-build", is_flag=True, help="Skip zig build step")
@click.option("--no-init", is_flag=True, help="Skip __init__.py generation")
@click.option("--force-init", is_flag=True, help="Overwrite existing __init__.py")
@click.option(
    "--fetch/--no-fetch",
    default=True,
    help="Fetch missing headers automatically",
)
def wheel(
    release: bool,
    debug: bool,
    optimize: str | None,
    module_name: str | None,
    lib_path: Path | None,
    package_dir: Path | None,
    python_version: str | None,
    pbs_target: str | None,
    python_cache: Path | None,
    project_dir: Path | None,
    python_tag: str | None,
    abi_tag: str | None,
    platform_tag: str | None,
    manylinux: str | None,
    musllinux: str | None,
    arch: str | None,
    ext_suffix: str | None,
    out_dir: Path | None,
    zig_target: str | None,
    skip_build: bool,
    no_init: bool,
    force_init: bool,
    fetch: bool,
) -> None:
    """Build a single wheel for the current project."""
    project_root = project_dir or find_project_dir(Path.cwd())
    config = read_tool_alloconda(project_root, package_dir)

    module_name = module_name or config_value(config, "module-name")
    lib_path = lib_path or config_path(config, project_root, "lib")
    package_dir = package_dir or config_path(config, project_root, "package-dir")
    python_version = python_version or config_value(config, "python-version")
    pbs_target = pbs_target or config_value(config, "pbs-target")
    python_cache = python_cache or config_path(config, project_root, "python-cache")
    project_dir = project_dir or config_path(config, project_root, "project-dir")
    python_tag = python_tag or config_value(config, "python-tag")
    abi_tag = abi_tag or config_value(config, "abi-tag")
    platform_tag = platform_tag or config_value(config, "platform-tag")
    manylinux = manylinux or config_value(config, "manylinux")
    musllinux = musllinux or config_value(config, "musllinux")
    arch = arch or config_value(config, "arch")
    ext_suffix = ext_suffix or config_value(config, "ext-suffix")
    out_dir = out_dir or config_path(config, project_root, "out-dir")
    zig_target = zig_target or config_value(config, "zig-target")
    build_step = config_value(config, "build-step")
    no_init = no_init or config_bool(config, "no-init")
    force_init = force_init or config_bool(config, "force-init")
    skip_build = skip_build or config_bool(config, "skip-build")
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
    include = config_list(config, "include")
    exclude = config_list(config, "exclude")

    wheel_path = build_wheel(
        release=release,
        optimize=optimize,
        zig_target=zig_target,
        lib_path=lib_path,
        module_name=module_name,
        package_dir=package_dir,
        python_version=python_version,
        pbs_target=pbs_target,
        python_cache=python_cache,
        project_dir=project_dir,
        python_tag=python_tag,
        abi_tag=abi_tag,
        platform_tag=platform_tag,
        manylinux=manylinux,
        musllinux=musllinux,
        arch=arch,
        ext_suffix=ext_suffix,
        out_dir=out_dir,
        build_step=build_step,
        no_init=no_init,
        force_init=force_init,
        skip_build=skip_build,
        include=include,
        exclude=exclude,
        fetch=fetch,
    )
    click.echo(f"✓ Built wheel {wheel_path}")
