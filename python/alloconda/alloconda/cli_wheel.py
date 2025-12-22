from pathlib import Path

import click

from .wheel_builder import build_wheel


@click.command()
@click.option("--release", is_flag=True, help="Build in release mode")
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
def wheel(
    release: bool,
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
) -> None:
    """Build a single wheel for the current project."""
    wheel_path = build_wheel(
        release=release,
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
        no_init=no_init,
        force_init=force_init,
        skip_build=skip_build,
    )
    click.echo(f"✓ Built wheel {wheel_path}")
