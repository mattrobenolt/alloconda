from __future__ import annotations

import os
import re
import shutil
import subprocess
import tomllib
from pathlib import Path

import click
import tomlkit
from jinja2 import Environment, PackageLoader, StrictUndefined

DEFAULT_ALLOCONDA_URL = "git+https://github.com/mattrobenolt/alloconda?ref=main"
FINGERPRINT_RE = re.compile(r"use this value: (0x[0-9a-fA-F]+)")
ZON_VERSION = "0.0.1"
MINIMUM_ZIG_VERSION = "0.15.2"
TEMPLATE_ENV = Environment(
    loader=PackageLoader("alloconda", "templates"),
    autoescape=False,
    keep_trailing_newline=True,
    undefined=StrictUndefined,
)


def normalize_name(name: str) -> str:
    name = name.strip()
    name = re.sub(r"[^A-Za-z0-9_]+", "_", name)
    if not name:
        return "alloconda_module"
    if name[0].isdigit():
        name = f"_{name}"
    return name


def read_project_name(dest_dir: Path) -> str | None:
    pyproject = dest_dir / "pyproject.toml"
    if not pyproject.is_file():
        return None
    data = tomllib.loads(pyproject.read_text())
    project = data.get("project", {})
    name = project.get("name")
    return name if isinstance(name, str) else None


def is_url(value: str) -> bool:
    return value.startswith(
        (
            "git+https://",
            "git+http://",
            "https://",
            "http://",
        )
    )


def save_alloconda_dependency(url: str, dest_dir: Path) -> None:
    cmd = ["zig", "fetch", "--save=alloconda", url]
    click.echo(f"Running: {cmd}")
    try:
        subprocess.run(cmd, check=True, cwd=dest_dir)
    except subprocess.CalledProcessError as exc:
        raise click.ClickException(f"zig fetch failed: {exc}") from exc


def resolve_fingerprint(dest_dir: Path) -> str:
    cache_dir = dest_dir / ".zig-cache"
    had_cache = cache_dir.exists()
    result = subprocess.run(
        ["zig", "build"],
        cwd=dest_dir,
        capture_output=True,
        text=True,
    )
    if not had_cache and cache_dir.exists():
        shutil.rmtree(cache_dir)
    if result.returncode == 0:
        return ""
    match = FINGERPRINT_RE.search(result.stderr)
    if not match:
        message = result.stderr.strip() or "zig build failed"
        raise click.ClickException(f"Could not determine fingerprint: {message}")
    return match.group(1)


def update_fingerprint(path: Path, fingerprint: str) -> None:
    text = path.read_text()
    updated = re.sub(
        r"\.fingerprint\s*=\s*0x[0-9a-fA-F]+",
        f".fingerprint = {fingerprint}",
        text,
        count=1,
    )
    path.write_text(updated)


def render_template(name: str, context: dict[str, str]) -> str:
    return TEMPLATE_ENV.get_template(name).render(**context)


def update_pyproject(pyproject_path: Path, package_dir: str) -> bool:
    if not pyproject_path.is_file():
        return False
    doc = tomlkit.parse(pyproject_path.read_text())
    updated = False

    if "build-system" not in doc:
        build_system = tomlkit.table()
        build_system.add("requires", ["alloconda"])
        build_system.add("build-backend", "alloconda.build_backend")
        doc["build-system"] = build_system
        updated = True

    tool = doc.get("tool")
    if tool is None:
        tool = tomlkit.table()
        doc["tool"] = tool
        updated = True

    alloconda = tool.get("alloconda")
    if alloconda is None:
        alloconda = tomlkit.table()
        tool["alloconda"] = alloconda
        updated = True

    if "package-dir" not in alloconda:
        alloconda["package-dir"] = package_dir
        updated = True

    if updated:
        pyproject_path.write_text(tomlkit.dumps(doc))
    return updated


def write_file(path: Path, content: str, force: bool) -> None:
    if path.exists() and not force:
        raise click.ClickException(f"Refusing to overwrite existing file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def ensure_package_dir(dest_dir: Path, package_name: str) -> Path:
    package_dir = dest_dir / "python" / package_name
    package_dir.mkdir(parents=True, exist_ok=True)
    init_path = package_dir / "__init__.py"
    if not init_path.exists():
        init_path.write_text("")
    return package_dir


@click.command("init")
@click.option("--name", "project_name", help="Project name (default: directory name)")
@click.option(
    "--module-name",
    help="Python extension module name (default: _<name>)",
)
@click.option(
    "--dir",
    "dest_dir",
    type=click.Path(path_type=Path, file_okay=False),
    default=Path.cwd(),
    help="Directory to scaffold (default: current working directory)",
)
@click.option(
    "--alloconda-path",
    default=DEFAULT_ALLOCONDA_URL,
    help="Path or git+https URL to alloconda source for build.zig.zon",
)
@click.option("--force", is_flag=True, help="Overwrite existing files")
def init(
    project_name: str | None,
    module_name: str | None,
    dest_dir: Path,
    alloconda_path: str,
    force: bool,
) -> None:
    """Scaffold build.zig and a minimal root module."""
    dest_dir = dest_dir.resolve()
    inferred_name = project_name or read_project_name(dest_dir) or dest_dir.name
    package_name = normalize_name(inferred_name)
    module_name = module_name or f"_{package_name}"

    alloconda_dep = ""
    needs_fetch = False
    if is_url(alloconda_path):
        needs_fetch = True
    else:
        alloconda_path_obj = Path(alloconda_path).expanduser()
        if not alloconda_path_obj.exists():
            raise click.ClickException(
                "Could not find alloconda; pass --alloconda-path to a local checkout."
            )
        rel_alloconda = os.path.relpath(alloconda_path_obj, dest_dir)
        alloconda_dep = f'.alloconda = .{{\n    .path = "{rel_alloconda}",\n}},'
    fingerprint_hex = "0x0000000000000000"

    template_context = {
        "package_name": package_name,
        "module_name": module_name,
        "fingerprint_hex": fingerprint_hex,
        "alloconda_dep_block": alloconda_dep,
        "zon_version": ZON_VERSION,
        "minimum_zig_version": MINIMUM_ZIG_VERSION,
    }
    build_zig = render_template("build.zig.j2", template_context)
    build_zig_zon = render_template("build.zig.zon.j2", template_context)
    root_zig = render_template("root.zig.j2", template_context)

    write_file(dest_dir / "build.zig", build_zig, force)
    write_file(dest_dir / "build.zig.zon", build_zig_zon, force)
    write_file(dest_dir / "src" / "root.zig", root_zig, force)
    ensure_package_dir(dest_dir, package_name)

    fingerprint = resolve_fingerprint(dest_dir)
    if fingerprint:
        update_fingerprint(dest_dir / "build.zig.zon", fingerprint)

    if needs_fetch:
        save_alloconda_dependency(alloconda_path, dest_dir)

    pyproject_path = dest_dir / "pyproject.toml"
    updated_pyproject = False
    if update_pyproject(pyproject_path, f"python/{package_name}"):
        updated_pyproject = True
    if updated_pyproject:
        click.echo(f"✓ Updated {dest_dir / 'pyproject.toml'}")

    click.echo(f"✓ Wrote {dest_dir / 'build.zig'}")
    click.echo(f"✓ Wrote {dest_dir / 'build.zig.zon'}")
    click.echo(f"✓ Wrote {dest_dir / 'src' / 'root.zig'}")
    click.echo(f"✓ Wrote {dest_dir / 'python' / package_name / '__init__.py'}")
