from __future__ import annotations

import shutil
from pathlib import Path

import click

from . import cli_output as out
from .pbs import cache_root, list_cached_entries


@click.group()
def cache() -> None:
    """Manage cached python-build-standalone headers."""
    pass


@cache.command("path")
@click.option(
    "--cache-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Cache directory (default: ~/.cache/alloconda/pbs)",
)
def cache_path(cache_dir: Path | None) -> None:
    """Print the PBS cache directory path."""
    path = cache_root(cache_dir)
    out.info(f"Cache directory: {out.path_style(path)}")


@cache.command("list")
@click.option(
    "--cache-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Cache directory (default: ~/.cache/alloconda/pbs)",
)
def cache_list(cache_dir: Path | None) -> None:
    """List cached python-build-standalone headers."""
    cache_dir = cache_root(cache_dir)
    if cache_dir.exists() and not cache_dir.is_dir():
        raise click.ClickException(f"Cache path is not a directory: {cache_dir}")

    entries = list_cached_entries(cache_dir)
    if not entries:
        out.info(f"No cached headers in {out.path_style(cache_dir)}")
        return

    out.section(f"Cached Python Headers ({len(entries)} entries)")
    out.verbose_detail("cache directory", cache_dir)

    rows: list[list[str]] = []
    for entry in entries:
        version = entry.version
        if entry.build_id:
            version = f"{version}+{entry.build_id}"
        rows.append([version, entry.target, str(entry.include_dir)])

    out.print_matrix(rows, headers=["Version", "Target", "Include Directory"])


@cache.command("clear")
@click.option(
    "--cache-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Cache directory (default: ~/.cache/alloconda/pbs)",
)
def cache_clear(cache_dir: Path | None) -> None:
    """Remove cached python-build-standalone headers."""
    cache_dir = cache_root(cache_dir)
    if not cache_dir.exists():
        out.info(f"No cache directory at {out.path_style(cache_dir)}")
        return
    if not cache_dir.is_dir():
        raise click.ClickException(f"Cache path is not a directory: {cache_dir}")

    out.verbose(f"Removing cache directory: {cache_dir}")
    shutil.rmtree(cache_dir)
    out.success(f"Cleared cache at {out.path_style(cache_dir)}")
