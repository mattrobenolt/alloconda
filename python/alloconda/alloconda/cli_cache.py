from __future__ import annotations

import shutil
from pathlib import Path

import click

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
    click.echo(cache_root(cache_dir))


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
        click.echo(f"No cached headers in {cache_dir}")
        return

    rows: list[tuple[str, str, str]] = []
    for entry in entries:
        version = entry.version
        if entry.build_id:
            version = f"{version}+{entry.build_id}"
        rows.append((version, entry.target, str(entry.include_dir)))

    version_width = max(len("Version"), max(len(row[0]) for row in rows))
    target_width = max(len("Target"), max(len(row[1]) for row in rows))

    click.echo(
        f"{'Version'.ljust(version_width)}  {'Target'.ljust(target_width)}  Include"
    )
    for version, target, include_dir in rows:
        click.echo(
            f"{version.ljust(version_width)}  {target.ljust(target_width)}  {include_dir}"
        )


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
        click.echo(f"No cache directory at {cache_dir}")
        return
    if not cache_dir.is_dir():
        raise click.ClickException(f"Cache path is not a directory: {cache_dir}")

    shutil.rmtree(cache_dir)
    click.echo(f"Cleared cache at {cache_dir}")
