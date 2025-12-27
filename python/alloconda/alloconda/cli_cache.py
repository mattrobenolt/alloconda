from __future__ import annotations

import shutil
from pathlib import Path

import click

from . import cli_output as out
from .pbs import cache_root, list_cached_entries


def get_directory_size(path: Path) -> int:
    """Calculate total size of a directory in bytes."""
    total = 0
    try:
        for entry in path.rglob("*"):
            if entry.is_file():
                total += entry.stat().st_size
    except (OSError, PermissionError):
        pass
    return total


def format_size(size_bytes: int) -> str:
    """Format bytes as human-readable size."""
    for unit in ["B", "KB", "MB", "GB"]:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} TB"


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
    total_size = 0
    for entry in entries:
        version = entry.version
        if entry.build_id:
            version = f"{version}+{entry.build_id}"

        # Calculate size of the entry's parent directory (contains all files)
        entry_dir = entry.include_dir.parent.parent  # Go up to version dir
        size_bytes = get_directory_size(entry_dir)
        total_size += size_bytes
        size_str = format_size(size_bytes)

        rows.append([version, entry.target, size_str, str(entry.include_dir)])

    out.print_matrix(rows, headers=["Version", "Target", "Size", "Include Directory"])
    out.dim(f"\nTotal cache size: {format_size(total_size)}")


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
