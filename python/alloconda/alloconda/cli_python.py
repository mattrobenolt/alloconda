from pathlib import Path

import click

from .cli_helpers import resolve_pbs_target, resolve_platform_tag
from .pbs import (
    cache_root,
    fetch_and_extract,
    fetch_release_assets,
    find_cached_entry,
    resolve_versions_for_target,
    select_asset,
)


@click.group()
def python() -> None:
    """Manage cached python-build-standalone headers."""
    pass


@python.command("fetch")
@click.option(
    "--version",
    "versions",
    multiple=True,
    help="Python version to fetch (repeatable, e.g. 3.13 or 3.13.1)",
)
@click.option("--all", "all_versions", is_flag=True, help="Fetch all versions")
@click.option("--pbs-target", help="Override python-build-standalone target triple")
@click.option("--platform-tag", help="Wheel platform tag (used to infer PBS target)")
@click.option("--manylinux", help="Manylinux policy (e.g. 2014, 2_28)")
@click.option("--musllinux", help="Musllinux policy (e.g. 1_2)")
@click.option("--arch", help="Target architecture (x86_64, aarch64)")
@click.option(
    "--cache-dir",
    type=click.Path(path_type=Path, file_okay=False),
    help="Cache directory (default: ~/.cache/alloconda/pbs)",
)
@click.option("--force", is_flag=True, help="Re-download even if cached")
def fetch(
    versions: tuple[str, ...],
    all_versions: bool,
    pbs_target: str | None,
    platform_tag: str | None,
    manylinux: str | None,
    musllinux: str | None,
    arch: str | None,
    cache_dir: Path | None,
    force: bool,
) -> None:
    """Fetch python-build-standalone headers into the cache."""
    platform = resolve_platform_tag(platform_tag, manylinux, musllinux, arch)
    target = resolve_pbs_target(pbs_target, platform, manylinux, musllinux, arch)
    cache_dir = cache_root(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)

    assets = fetch_release_assets()
    if all_versions:
        version_list = resolve_versions_for_target(assets, target)
    elif versions:
        version_list = list(versions)
    else:
        raise click.ClickException("Provide --version or --all")

    for version in version_list:
        entry = find_cached_entry(cache_dir, version, target)
        if entry and not force:
            click.echo(
                f"Cached {entry.version} ({entry.target}) at {entry.include_dir}"
            )
            continue

        asset = select_asset(assets, version, target)
        entry = fetch_and_extract(asset, cache_dir, force, show_progress=True)
        click.echo(f"Fetched {entry.version} ({entry.target}) -> {entry.include_dir}")
