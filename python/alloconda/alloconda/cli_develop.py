import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

import click

from .cli_helpers import (
    OPTIMIZE_CHOICES,
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
@click.option("--skip-build", is_flag=True, help="Skip zig build step")
@click.option("--no-init", is_flag=True, help="Skip __init__.py generation")
@click.option("--force-init", is_flag=True, help="Overwrite existing __init__.py")
@click.option(
    "--project-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Project root containing pyproject.toml",
)
@click.option(
    "--pip-arg",
    "pip_args",
    multiple=True,
    help="Extra argument to pass to pip (repeatable)",
)
@click.option("--uv", "use_uv", is_flag=True, help="Use uv pip for editable install")
def develop(
    release: bool,
    debug: bool,
    optimize: str | None,
    module_name: str | None,
    lib_path: Path | None,
    package_dir: Path | None,
    ext_suffix: str | None,
    zig_target: str | None,
    python_include: str | None,
    skip_build: bool,
    no_init: bool,
    force_init: bool,
    project_dir: Path | None,
    pip_args: tuple[str, ...],
    use_uv: bool,
) -> None:
    """Build and install the project in editable mode."""
    project_root = project_dir or find_project_dir(Path.cwd()) or Path.cwd()
    config = read_tool_alloconda(project_root, package_dir)

    module_name = module_name or config_value(config, "module-name")
    lib_path = lib_path or config_path(config, project_root, "lib")
    package_dir = package_dir or config_path(config, project_root, "package-dir")
    ext_suffix = ext_suffix or config_value(config, "ext-suffix")
    zig_target = zig_target or config_value(config, "zig-target")
    python_include = python_include or config_value(config, "python-include")
    build_step = config_value(config, "build-step")
    skip_build = skip_build or config_bool(config, "skip-build")
    no_init = no_init or config_bool(config, "no-init")
    force_init = force_init or config_bool(config, "force-init")
    release_flag = release
    debug_flag = debug
    release = resolve_release_mode(
        release_flag=release_flag,
        debug_flag=debug_flag,
        config=config,
        default_release=False,
    )
    if not release_flag and not debug_flag:
        release = False
    optimize = resolve_optimize_mode(
        release=release,
        optimize_flag=optimize,
        config=config,
    )

    has_uv = shutil.which("uv") is not None
    has_pip = importlib.util.find_spec("pip") is not None
    if use_uv or (not has_pip and has_uv):
        cmd = ["uv", "pip", "install", "-e", str(project_root)]
    elif has_pip:
        cmd = [sys.executable, "-m", "pip", "install", "-e", str(project_root)]
    else:
        raise click.ClickException(
            "pip is not available; install pip or re-run with --uv."
        )
    if release:
        _add_config_setting(cmd, "release", True)
        _add_config_setting(cmd, "optimize", optimize)
    else:
        _add_config_setting(cmd, "debug", True)
    _add_config_setting(cmd, "module-name", module_name)
    _add_config_setting(cmd, "lib", _path_str(lib_path))
    _add_config_setting(cmd, "package-dir", _path_str(package_dir))
    _add_config_setting(cmd, "ext-suffix", ext_suffix)
    _add_config_setting(cmd, "zig-target", zig_target)
    _add_config_setting(cmd, "python-include", python_include)
    _add_config_setting(cmd, "build-step", build_step)
    _add_config_setting(cmd, "skip-build", skip_build)
    _add_config_setting(cmd, "no-init", no_init)
    _add_config_setting(cmd, "force-init", force_init)
    _add_config_setting(cmd, "project-dir", str(project_root))

    for arg in pip_args:
        cmd.append(arg)

    click.echo(f"Running: {cmd}")
    subprocess.run(cmd, check=True, cwd=project_root)


def _add_config_setting(cmd: list[str], key: str, value: object) -> None:
    if isinstance(value, bool):
        if value:
            cmd.extend(["--config-settings", f"{key}=true"])
        return
    if value is None:
        return
    if value == "":
        cmd.extend(["--config-settings", f"{key}=true"])
    else:
        cmd.extend(["--config-settings", f"{key}={value}"])


def _path_str(path: Path | None) -> str | None:
    if path is None:
        return None
    return str(path)
