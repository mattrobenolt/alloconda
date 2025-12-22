from pathlib import Path

import click

from .cli_helpers import (
    build_extension,
    config_bool,
    config_path,
    config_value,
    find_project_dir,
    read_tool_alloconda,
)


@click.command()
@click.option("--release", is_flag=True, help="Build in release mode")
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
    config = read_tool_alloconda(project_root, package_dir)

    module_name = module_name or config_value(config, "module-name")
    lib_path = lib_path or config_path(config, project_root, "lib")
    package_dir = package_dir or config_path(config, project_root, "package-dir")
    ext_suffix = ext_suffix or config_value(config, "ext-suffix")
    zig_target = zig_target or config_value(config, "zig-target")
    python_include = python_include or config_value(config, "python-include")
    no_init = no_init or config_bool(config, "no-init")
    force_init = force_init or config_bool(config, "force-init")

    dst = build_extension(
        release=release,
        module_name=module_name,
        lib_path=lib_path,
        package_dir=package_dir,
        ext_suffix=ext_suffix,
        zig_target=zig_target,
        python_include=python_include,
        no_init=no_init,
        force_init=force_init,
    )
    click.echo(f"✓ Built {dst}")
