from __future__ import annotations

import hashlib
import os
import re
import textwrap
from pathlib import Path

import click


def normalize_name(name: str) -> str:
    name = name.strip()
    name = re.sub(r"[^A-Za-z0-9_]+", "_", name)
    if not name:
        return "alloconda_module"
    if name[0].isdigit():
        name = f"_{name}"
    return name


def find_alloconda_root(start: Path) -> Path | None:
    for path in (start, *start.parents):
        candidate = path / "build.zig.zon"
        if not candidate.is_file():
            continue
        text = candidate.read_text()
        if ".name = .alloconda" in text:
            return path
    return None


def write_file(path: Path, content: str, force: bool) -> None:
    if path.exists() and not force:
        raise click.ClickException(f"Refusing to overwrite existing file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


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
    type=click.Path(path_type=Path, file_okay=False),
    help="Path to alloconda source for build.zig.zon",
)
@click.option("--force", is_flag=True, help="Overwrite existing files")
def init(
    project_name: str | None,
    module_name: str | None,
    dest_dir: Path,
    alloconda_path: Path | None,
    force: bool,
) -> None:
    """Scaffold build.zig and a minimal root module."""
    dest_dir = dest_dir.resolve()
    package_name = normalize_name(project_name or dest_dir.name)
    module_name = module_name or f"_{package_name}"

    alloconda_root = alloconda_path or find_alloconda_root(dest_dir)
    if alloconda_root is None:
        raise click.ClickException(
            "Could not find alloconda; pass --alloconda-path to a local checkout."
        )
    rel_alloconda = os.path.relpath(alloconda_root, dest_dir)
    fingerprint = int.from_bytes(
        hashlib.blake2b(package_name.encode("utf-8"), digest_size=8).digest(),
        "little",
    )
    fingerprint_hex = f"0x{fingerprint:016x}"

    build_zig = textwrap.dedent(
        f"""\
        const std = @import("std");

        pub fn build(b: *std.Build) void {{
            const target = b.standardTargetOptions(.{{}});
            const optimize = b.standardOptimizeOption(.{{}});

            const alloconda = b.dependency("alloconda", .{{
                .target = target,
                .optimize = optimize,
            }});

            const mod = b.createModule(.{{
                .root_source_file = b.path("src/root.zig"),
                .target = target,
                .optimize = optimize,
            }});
            mod.addImport("alloconda", alloconda.module("alloconda"));

            const lib = @import("alloconda").addPythonLibrary(b, .{{
                .name = "{package_name}",
                .root_module = mod,
            }});
            b.installArtifact(lib);
        }}
        """
    )

    build_zig_zon = textwrap.dedent(
        f"""\
        .{{
            .name = .{package_name},
            .version = "0.0.1a1",
            .fingerprint = {fingerprint_hex},
            .dependencies = .{{
                .alloconda = .{{
                    .path = "{rel_alloconda}",
                }},
            }},
            .minimum_zig_version = "0.15.2",
            .paths = .{{ "build.zig", "build.zig.zon", "src" }},
        }}
        """
    )

    root_zig = textwrap.dedent(
        f"""\
        const std = @import("std");
        const py = @import("alloconda");

        pub const MODULE = py.module(
            "{module_name}",
            "Alloconda module stub.",
            .{{
                .hello = py.method(hello, .{{
                    .doc = "Echo back the provided name.",
                    .args = &.{{ "name" }},
                }}),
            }},
        );

        fn hello(name: []const u8) []const u8 {{
            return name;
        }}
        """
    )

    write_file(dest_dir / "build.zig", build_zig, force)
    write_file(dest_dir / "build.zig.zon", build_zig_zon, force)
    write_file(dest_dir / "src" / "root.zig", root_zig, force)

    click.echo(f"✓ Wrote {dest_dir / 'build.zig'}")
    click.echo(f"✓ Wrote {dest_dir / 'build.zig.zon'}")
    click.echo(f"✓ Wrote {dest_dir / 'src' / 'root.zig'}")
