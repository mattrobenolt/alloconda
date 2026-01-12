import fnmatch
import importlib.machinery
import importlib.util
import os
import platform
import re
import shutil
import subprocess
import sys
import sysconfig
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import click

from . import cli_output as out

OPTIMIZE_CHOICES = ("ReleaseSafe", "ReleaseFast", "ReleaseSmall")


def resolve_zig_command(use_pypi_zig: bool = False) -> list[str]:
    """Resolve the zig command prefix based on configuration.

    Resolution order:
    1. If use_pypi_zig=True, use ziglang PyPI package (error if not installed)
    2. If system zig is available (shutil.which), use it
    3. If ziglang PyPI package is importable, use it as fallback
    4. If uvx is available, use `uvx --from ziglang python-zig`
    5. Otherwise, raise an error with installation instructions

    Args:
        use_pypi_zig: If True, force use of the ziglang PyPI package.

    Returns:
        Command prefix list, e.g. ["zig"] or [sys.executable, "-m", "ziglang"].

    Raises:
        click.ClickException: If no zig installation is available.
    """
    if use_pypi_zig:
        if importlib.util.find_spec("ziglang") is None:
            raise click.ClickException(
                "The ziglang package is not installed. Install it with: pip install ziglang"
            )
        out.verbose("Zig resolution: using ziglang PyPI package (explicit)")
        return [sys.executable, "-m", "ziglang"]

    if shutil.which("zig"):
        out.verbose("Zig resolution: using system zig")
        return ["zig"]

    if importlib.util.find_spec("ziglang") is not None:
        out.verbose("Zig resolution: using ziglang PyPI package (fallback)")
        return [sys.executable, "-m", "ziglang"]

    uvx_path = shutil.which("uvx")
    if uvx_path:
        out.verbose("Zig resolution: using ziglang via uvx")
        return [uvx_path, "--from", "ziglang", "python-zig"]

    raise click.ClickException(
        "No zig installation found. Install zig system-wide, run `pip install ziglang`, "
        "or install uv for automatic ziglang fetching."
    )


@dataclass(frozen=True)
class ProjectMetadata:
    name: str
    version: str
    summary: str | None
    license: str | None
    classifiers: list[str]
    requires_python: str | None
    dependencies: list[str]


def read_tool_alloconda(
    project_dir: Path | None,
    package_dir: Path | None = None,
) -> dict[str, Any]:
    root = project_dir or find_project_dir(package_dir or Path.cwd())
    if not root:
        return {}

    data = tomllib.loads((root / "pyproject.toml").read_text())
    tool = data.get("tool", {})
    config = tool.get("alloconda", {})
    if not isinstance(config, dict):
        return {}
    return {key.replace("_", "-"): value for key, value in config.items()}


def config_value(config: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in config:
            return config[key]
    return None


def config_path(
    config: dict[str, Any],
    root: Path | None,
    *keys: str,
) -> Path | None:
    value = config_value(config, *keys)
    if value is None:
        return None
    path = Path(value)
    if root and not path.is_absolute():
        return root / path
    return path


def config_bool(config: dict[str, Any], *keys: str) -> bool:
    value = config_value(config, *keys)
    if value is None:
        return False
    return bool(value)


def config_list(config: dict[str, Any], *keys: str) -> list[str] | None:
    value = config_value(config, *keys)
    if value is None:
        return None
    if isinstance(value, list):
        return [str(item) for item in value]
    return [str(value)]


def matches_any(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def should_include_path(
    rel_path: str,
    include: list[str] | None,
    exclude: list[str] | None,
) -> bool:
    if include and not matches_any(rel_path, include):
        return False
    if exclude and matches_any(rel_path, exclude):
        return False
    return True


def resolve_python_include(
    python_include: str | None, zig_target: str | None
) -> str | None:
    """Resolve Python include path, auto-detecting from running interpreter if needed.

    For native builds (no zig_target), we auto-detect from sysconfig to ensure
    the correct Python headers are used when running under uv or similar tools.
    """
    if python_include:
        return python_include

    if zig_target:
        return None

    include_path = sysconfig.get_path("include")
    if include_path:
        out.verbose(f"Auto-detected Python include: {include_path}")
        return include_path

    return None


def run_zig_build(
    release: bool,
    zig_target: str | None,
    python_include: str | None,
    build_step: str | None = None,
    optimize: str | None = None,
    workdir: Path | None = None,
    use_pypi_zig: bool = False,
) -> None:
    cmd = [*resolve_zig_command(use_pypi_zig), "build"]
    if build_step:
        cmd.append(build_step)
    if optimize:
        cmd.append(f"-Doptimize={optimize}")
    elif release:
        cmd.append("-Doptimize=ReleaseFast")
    if zig_target:
        cmd.append(f"-Dtarget={zig_target}")

    resolved_include = resolve_python_include(python_include, zig_target)
    env = None
    if resolved_include:
        cmd.append(f"-Dpython-include={resolved_include}")
        env = os.environ.copy()
        env["ALLOCONDA_PYTHON_INCLUDE"] = resolved_include

    out.step("Compiling extension")
    out.verbose_cmd(cmd)
    if workdir:
        out.verbose_detail("workdir", workdir)
    if env and "ALLOCONDA_PYTHON_INCLUDE" in env:
        out.verbose_detail("ALLOCONDA_PYTHON_INCLUDE", env["ALLOCONDA_PYTHON_INCLUDE"])

    subprocess.run(cmd, check=True, cwd=workdir, env=env)


def resolve_release_mode(
    *,
    release_flag: bool,
    debug_flag: bool,
    config: dict[str, Any],
    default_release: bool,
) -> bool:
    if release_flag and debug_flag:
        raise click.ClickException("Use only one of --release or --debug")
    if debug_flag:
        return False
    if release_flag:
        return True
    config_release = config_value(config, "release")
    if config_release is None:
        return default_release
    return bool(config_release)


def resolve_optimize_mode(
    *,
    release: bool,
    optimize_flag: str | None,
    config: dict[str, Any],
) -> str | None:
    if not release:
        return "Debug"
    value = optimize_flag or config_value(config, "optimize")
    if value is None:
        return None
    value = str(value)
    if value not in OPTIMIZE_CHOICES:
        raise click.ClickException(
            f"Unsupported optimize mode: {value}. "
            f"Use one of: {', '.join(OPTIMIZE_CHOICES)}"
        )
    return value


def get_so_suffix() -> str:
    match p := platform.system():
        case "Darwin":
            return "dylib"
        case "Linux":
            return "so"
        case "Windows":
            return "dll"
        case _:
            raise click.ClickException(f"Unsupported platform: {p}")


def get_extension_suffix() -> str:
    suffixes = importlib.machinery.EXTENSION_SUFFIXES
    if not suffixes:
        raise click.ClickException("Could not determine extension suffixes")
    return suffixes[0]


def resolve_extension_suffix(ext_suffix: str | None) -> str:
    return ext_suffix or get_extension_suffix()


def resolve_library_path(
    lib_path: Path | None,
    base_dir: Path | None = None,
    lib_suffix: str | None = None,
) -> Path:
    base_dir = base_dir or Path.cwd()
    if lib_path:
        out.verbose_detail("using explicit library path", lib_path)
        if not lib_path.exists():
            raise click.ClickException(f"Library not found: {lib_path}")
        return lib_path

    lib_dir = base_dir / "zig-out" / "lib"
    out.verbose(f"Searching for library in {lib_dir}")
    if not lib_dir.is_dir():
        raise click.ClickException(f"Missing build output directory: {lib_dir}")

    suffix = normalize_lib_suffix(lib_suffix) if lib_suffix else f".{get_so_suffix()}"
    out.verbose_detail("library suffix", suffix)
    libs = sorted(p for p in lib_dir.iterdir() if p.is_file() and p.suffix == suffix)
    out.verbose(f"Found {len(libs)} candidate library(ies)")
    if not libs:
        raise click.ClickException(
            f"No libraries with suffix {suffix} found in {lib_dir}"
        )
    if len(libs) > 1:
        names = ", ".join(p.name for p in libs)
        raise click.ClickException(f"Multiple libraries found in {lib_dir}: {names}")
    out.verbose_detail("selected library", libs[0].name)
    return libs[0]


def normalize_lib_suffix(suffix: str) -> str:
    return suffix if suffix.startswith(".") else f".{suffix}"


def lib_suffix_for_target(
    zig_target: str | None, platform_tag: str | None
) -> str | None:
    target = (zig_target or "").lower()
    if "windows" in target or "mingw" in target:
        return ".dll"
    if "macos" in target or "darwin" in target:
        return ".dylib"
    if "linux" in target:
        return ".so"

    platform = (platform_tag or "").lower()
    if platform.startswith(("manylinux", "musllinux", "linux")):
        return ".so"
    if platform.startswith("macosx"):
        return ".dylib"
    if "win" in platform:
        return ".dll"
    return None


def detect_module_name(lib_path: Path) -> str:
    out.verbose(f"Detecting module name from {lib_path.name}")
    pyinit_symbol_re = re.compile(r"_*PyInit_[A-Za-z0-9_]+")
    symbol_names = load_symbol_names(lib_path)
    out.verbose(f"Loaded {len(symbol_names)} symbols from library")
    matches = sorted(
        {name.lstrip("_") for name in symbol_names if pyinit_symbol_re.fullmatch(name)}
    )
    out.verbose(f"Found {len(matches)} PyInit_* symbol(s)")
    for match in matches:
        out.verbose_detail("PyInit symbol", match)
    if not matches:
        raise click.ClickException(f"No PyInit_* symbols found in {lib_path}")
    if len(matches) > 1:
        names = ", ".join(matches)
        raise click.ClickException(
            f"Multiple PyInit_* symbols found in {lib_path}: {names}"
        )
    module_name = matches[0].removeprefix("PyInit_")
    out.verbose_detail("detected module name", module_name)
    return module_name


def load_symbol_names(lib_path: Path) -> list[str]:
    import lief

    lief.logging.set_level(lief.logging.LEVEL.ERROR)
    try:
        binary = lief.parse(str(lib_path))
    except Exception as exc:  # pragma: no cover - lief errors vary by platform
        raise click.ClickException(
            f"Could not parse library symbols in {lib_path}"
        ) from exc
    if binary is None:
        raise click.ClickException(f"Could not parse library symbols in {lib_path}")

    names: list[str] = []
    for attr in ("exported_symbols", "dynamic_symbols", "symbols"):
        symbols = getattr(binary, attr, None)
        if not symbols:
            continue
        for symbol in symbols:
            name = getattr(symbol, "name", "")
            if not name:
                continue
            if isinstance(name, bytes):
                name = name.decode("utf-8", "replace")
            names.append(name)
    return names


def resolve_package_dir(package_dir: Path | None, base_dir: Path | None = None) -> Path:
    base_dir = base_dir or Path.cwd()
    if package_dir:
        if not package_dir.is_dir():
            raise click.ClickException(f"Package directory not found: {package_dir}")
        return package_dir

    project_name = read_project_name(base_dir)
    candidates: list[Path] = []
    for base in (
        base_dir,
        base_dir / "src",
        base_dir / "python",
        base_dir / "python" / "src",
    ):
        if project_name:
            candidate = base / project_name
            if candidate.is_dir():
                candidates.append(candidate)

        if base.is_dir():
            for child in base.iterdir():
                if not child.is_dir():
                    continue
                if child.name in {".zig-cache", "zig-out", "src", "python", ".git"}:
                    continue
                if (child / "__init__.py").is_file():
                    candidates.append(child)

    unique = []
    for candidate in candidates:
        if candidate not in unique:
            unique.append(candidate)

    if not unique:
        raise click.ClickException(
            "Could not determine package directory; use --package-dir"
        )
    if len(unique) > 1:
        names = ", ".join(str(p) for p in unique)
        raise click.ClickException(
            f"Multiple package dirs found; use --package-dir: {names}"
        )
    return unique[0]


def read_project_name(root: Path) -> str | None:
    pyproject = root / "pyproject.toml"
    if not pyproject.is_file():
        return None
    data = tomllib.loads(pyproject.read_text())
    return data.get("project", {}).get("name")


def find_project_dir(start: Path) -> Path | None:
    for path in [start, *start.parents]:
        if (path / "pyproject.toml").is_file():
            return path
    return None


def read_project_metadata(
    project_dir: Path | None, package_dir: Path | None
) -> ProjectMetadata:
    root = project_dir or (find_project_dir(package_dir or Path.cwd()))
    if not root:
        name = package_dir.name if package_dir else "alloconda-extension"
        return ProjectMetadata(
            name=name,
            version="0.0.0",
            summary=None,
            license=None,
            classifiers=[],
            requires_python=None,
            dependencies=[],
        )

    data = tomllib.loads((root / "pyproject.toml").read_text())
    project = data.get("project", {})
    name = project.get("name") or (
        package_dir.name if package_dir else "alloconda-extension"
    )
    version = project.get("version", "0.0.0")
    summary = project.get("description")
    license_value = project.get("license")
    license_text = None
    if isinstance(license_value, str):
        license_text = license_value
    elif isinstance(license_value, dict):
        text = license_value.get("text")
        file = license_value.get("file")
        if isinstance(text, str):
            license_text = text
        elif isinstance(file, str):
            license_text = f"See {file}"
    requires_python = project.get("requires-python")
    dependencies = list(project.get("dependencies", []))
    classifiers = project.get("classifiers", [])
    if isinstance(classifiers, str):
        classifiers = [classifiers]
    classifiers = [str(item) for item in classifiers]
    return ProjectMetadata(
        name=name,
        version=version,
        summary=summary,
        license=license_text,
        classifiers=classifiers,
        requires_python=requires_python,
        dependencies=dependencies,
    )


def normalize_dist_name(name: str) -> str:
    return re.sub(r"[-.]+", "_", name)


def default_platform_tag() -> str:
    tag = sysconfig.get_platform()
    tag = tag.replace("-", "_").replace(".", "_")
    # Default to manylinux_2_28 on Linux (generic linux_* tags are rejected by PyPI)
    if tag.startswith("linux_"):
        arch = tag.split("_", 1)[1]
        return f"manylinux_2_28_{arch}"
    return tag


def resolve_arch(arch: str | None) -> str:
    machine = arch.lower() if arch else platform.machine().lower()
    return {
        "amd64": "x86_64",
        "x86_64": "x86_64",
        "aarch64": "aarch64",
        "arm64": "aarch64",
        "armv7l": "armv7l",
    }.get(machine, machine)


def resolve_platform_tag(
    platform_tag: str | None,
    manylinux: str | None,
    musllinux: str | None,
    arch: str | None,
) -> str:
    if platform_tag and (manylinux or musllinux):
        raise click.ClickException(
            "Use either --platform-tag or --manylinux/--musllinux"
        )
    if platform_tag and platform_tag.startswith("linux_"):
        raise click.ClickException(
            "Generic linux_* platform tags are not accepted by PyPI. "
            "Use --manylinux or --musllinux instead."
        )
    if manylinux:
        return f"{normalize_manylinux(manylinux)}_{resolve_arch(arch)}"
    if musllinux:
        return f"{normalize_musllinux(musllinux)}_{resolve_arch(arch)}"
    return platform_tag or default_platform_tag()


def resolve_pbs_target(
    pbs_target: str | None,
    platform_tag: str | None,
    manylinux: str | None,
    musllinux: str | None,
    arch: str | None,
) -> str:
    if pbs_target:
        return pbs_target

    resolved_arch = resolve_arch(arch)
    plat = platform_tag or ""

    if manylinux or plat.startswith("manylinux") or plat.startswith("linux"):
        return f"{resolved_arch}-unknown-linux-gnu"
    if musllinux or plat.startswith("musllinux"):
        return f"{resolved_arch}-unknown-linux-musl"
    if plat.startswith("macosx") or platform.system() == "Darwin":
        return f"{resolved_arch}-apple-darwin"
    if plat.startswith("win") or platform.system() == "Windows":
        if resolved_arch in {"aarch64", "arm64"}:
            return "aarch64-pc-windows-msvc"
        return "x86_64-pc-windows-msvc"

    raise click.ClickException("Unable to infer PBS target; use --pbs-target")


def resolve_zig_target(
    zig_target: str | None,
    manylinux: str | None,
    musllinux: str | None,
    arch: str | None,
) -> str | None:
    if zig_target:
        return zig_target
    resolved_arch = resolve_arch(arch)
    if manylinux:
        glibc = manylinux_glibc_version(manylinux)
        if not glibc:
            raise click.ClickException(f"Unsupported manylinux value: {manylinux}")
        return f"{resolved_arch}-linux-gnu.{glibc}"
    if musllinux:
        return f"{resolved_arch}-linux-musl"
    return None


def manylinux_glibc_version(value: str) -> str | None:
    normalized = normalize_manylinux(value)
    if normalized.startswith("manylinux_"):
        return normalized.split("_", 1)[1].replace("_", ".")
    if normalized == "manylinux2014":
        return "2.17"
    if normalized == "manylinux2010":
        return "2.12"
    if normalized == "manylinux1":
        return "2.5"
    return None


def normalize_manylinux(value: str) -> str:
    value = value.strip()
    if value.startswith("manylinux"):
        return value
    if value.isdigit():
        return f"manylinux{value}"
    if value.startswith("2_"):
        return f"manylinux_{value}"
    raise click.ClickException(f"Unrecognized manylinux value: {value}")


def normalize_musllinux(value: str) -> str:
    value = value.strip()
    if value.startswith("musllinux"):
        return value
    if value.startswith("1_"):
        return f"musllinux_{value}"
    raise click.ClickException(f"Unrecognized musllinux value: {value}")


def write_init_py(package_dir: Path, module_name: str, force: bool) -> None:
    init_path = package_dir / "__init__.py"
    content = init_path.read_text() if init_path.exists() else ""

    if content.strip() and "Generated by alloconda" not in content and not force:
        out.dim("Skipping existing __init__.py (use --force-init to overwrite)")
        out.verbose_detail("path", init_path)
        return

    out.verbose(f"Writing __init__.py to {init_path}")
    init_body = f"""# Generated by alloconda
from . import {module_name} as _mod
from .{module_name} import *  # noqa: F403

__doc__ = _mod.__doc__

if hasattr(_mod, "__all__"):
    __all__ = _mod.__all__
"""
    init_path.write_text(init_body)


def build_extension(
    *,
    release: bool,
    optimize: str | None,
    module_name: str | None,
    lib_path: Path | None,
    package_dir: Path | None,
    ext_suffix: str | None,
    zig_target: str | None,
    python_include: str | None,
    build_step: str | None,
    no_init: bool,
    force_init: bool,
    skip_build: bool = False,
    workdir: Path | None = None,
    use_pypi_zig: bool = False,
) -> Path:
    build_root = workdir or Path.cwd()

    with out.verbose_section("Building extension"):
        if out.is_verbose():
            config_items = [
                ("release", release),
                ("optimize", optimize or "default"),
                ("zig_target", zig_target or "host"),
                ("python_include", python_include or "default"),
                ("build_step", build_step or "default"),
                ("workdir", build_root),
            ]
            for key, value in config_items:
                out.verbose_detail(key, value)

        if not skip_build:
            run_zig_build(
                release,
                zig_target,
                python_include,
                build_step=build_step,
                optimize=optimize,
                workdir=build_root,
                use_pypi_zig=use_pypi_zig,
            )
        else:
            out.verbose("Skipping build (--skip-build)")

        lib_suffix = lib_suffix_for_target(zig_target, None)
        lib_path = resolve_library_path(
            lib_path,
            base_dir=build_root,
            lib_suffix=lib_suffix,
        )
        if module_name is None:
            module_name = detect_module_name(lib_path)

        package_dir = resolve_package_dir(package_dir, base_dir=build_root)
        suffix = resolve_extension_suffix(ext_suffix)
        dst = package_dir / f"{module_name}{suffix}"

        out.step(f"Installing {lib_path.name} → {out.path_style(dst)}")
        out.verbose_detail("source", lib_path)
        out.verbose_detail("destination", dst)
        shutil.copy2(lib_path, dst)

        if not no_init:
            write_init_py(package_dir, module_name, force_init)

    return dst
