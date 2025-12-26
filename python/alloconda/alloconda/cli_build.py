from pathlib import Path

import click

from .cli_helpers import (
    OPTIMIZE_CHOICES,
    build_extension,
    config_bool,
    config_path,
    config_value,
    find_project_dir,
    read_tool_alloconda,
    resolve_optimize_mode,
    resolve_release_mode,
)


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
    help="Python package directory to install the extension",
)
@click.option(
    "--ext-suffix",
    help="Override extension suffix (default from running Python)",
)
@click.option("--zig-target", help="Zig target triple for cross builds")
@click.option("--python-include", help="Python include path for cross builds")
@click.option("--no-init", is_flag=True, help="Skip __init__.py generation")
@click.option("--force-init", is_flag=True, help="Overwrite existing __init__.py")
def build(
    release: bool,
    debug: bool,
    optimize: str | None,
    module_name: str | None,
    lib_path: Path | None,
    package_dir: Path | None,
    ext_suffix: str | None,
    zig_target: str | None,
    python_include: str | None,
    no_init: bool,
    force_init: bool,
) -> None:
    """Build a Zig extension and install it into a package directory."""
    project_root = find_project_dir(package_dir or Path.cwd())
    build_root = project_root or Path.cwd()
    config = read_tool_alloconda(project_root, package_dir)

    module_name = module_name or config_value(config, "module-name")
    lib_path = lib_path or config_path(config, project_root, "lib")
    package_dir = package_dir or config_path(config, project_root, "package-dir")
    ext_suffix = ext_suffix or config_value(config, "ext-suffix")
    zig_target = zig_target or config_value(config, "zig-target")
    python_include = python_include or config_value(config, "python-include")
    build_step = config_value(config, "build-step")
    no_init = no_init or config_bool(config, "no-init")
    force_init = force_init or config_bool(config, "force-init")
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

    dst = build_extension(
        release=release,
        optimize=optimize,
        module_name=module_name,
        lib_path=lib_path,
        package_dir=package_dir,
        ext_suffix=ext_suffix,
        zig_target=zig_target,
        python_include=python_include,
        build_step=build_step,
        no_init=no_init,
        force_init=force_init,
        workdir=build_root,
    )
    click.echo(f"✓ Built {dst}")
