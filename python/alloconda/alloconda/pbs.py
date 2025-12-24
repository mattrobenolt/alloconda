"""Python-build-standalone (PBS) header fetching and caching.

This module downloads Python headers from the python-build-standalone project
for cross-compilation. It uses the SHA256SUMS file for fast discovery instead
of the GitHub API.
"""

import ast
import hashlib
import json
import os
import re
import tarfile
from dataclasses import dataclass, replace
from pathlib import Path

import click
import httpx

PBS_SHA256SUMS_URL = "https://github.com/astral-sh/python-build-standalone/releases/latest/download/SHA256SUMS"
PBS_DOWNLOAD_BASE = (
    "https://github.com/astral-sh/python-build-standalone/releases/download"
)
PBS_CACHE_ENV = "ALLOCONDA_PBS_CACHE"


@dataclass(frozen=True)
class PbsAsset:
    name: str
    url: str
    sha256: str
    version_base: str
    build_id: str
    target: str
    flavor: str


@dataclass(frozen=True)
class PbsEntry:
    version: str
    build_id: str | None
    target: str
    include_dir: Path
    sysconfig_path: Path
    ext_suffix: str
    asset_name: str
    asset_url: str
    sha256: str | None = None


def cache_root(explicit: Path | None) -> Path:
    if explicit:
        return explicit
    env_value = os.environ.get(PBS_CACHE_ENV)
    if env_value:
        return Path(env_value)
    return Path.home() / ".cache" / "alloconda" / "pbs"


def fetch_release_assets() -> list[PbsAsset]:
    """Fetch available assets from SHA256SUMS file.

    This is much faster than the GitHub API as it's a single small file.
    """
    resp = httpx.get(PBS_SHA256SUMS_URL, timeout=30.0, follow_redirects=True)
    resp.raise_for_status()
    return parse_sha256sums(resp.text)


def parse_sha256sums(content: str) -> list[PbsAsset]:
    """Parse SHA256SUMS file content into PbsAsset objects."""
    assets = []
    for line in content.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        # Format: <sha256>  <filename>
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            continue
        sha256, filename = parts
        parsed = parse_asset_filename(filename.strip(), sha256)
        if parsed:
            assets.append(parsed)
    return assets


def parse_asset_filename(name: str, sha256: str) -> PbsAsset | None:
    """Parse a PBS asset filename into its components."""
    if not name.startswith("cpython-"):
        return None
    # We only care about .tar.gz files (not .tar.zst)
    if not name.endswith(".tar.gz"):
        return None

    stem = name[len("cpython-") : -len(".tar.gz")]
    parts = stem.split("-")
    if len(parts) < 3:
        return None

    version_build = parts[0]
    flavor = parts[-1]
    target = "-".join(parts[1:-1])

    if "+" not in version_build:
        return None
    version_base, build_id = version_build.split("+", 1)

    url = f"{PBS_DOWNLOAD_BASE}/{build_id}/{name}"

    return PbsAsset(
        name=name,
        url=url,
        sha256=sha256,
        version_base=version_base,
        build_id=build_id,
        target=target,
        flavor=flavor,
    )


def matches_version(requested: str, actual: str) -> bool:
    if requested == "all":
        return True
    req_parts = parse_version_parts(requested)
    act_parts = parse_version_parts(actual)
    return act_parts[: len(req_parts)] == req_parts


def parse_version_parts(version: str) -> list[int]:
    return [int(piece) for piece in re.split(r"[.+]", version) if piece.isdigit()]


def select_asset(
    assets: list[PbsAsset],
    version: str,
    target: str,
) -> PbsAsset:
    """Select the best matching asset for a version and target."""
    candidates = [
        asset
        for asset in assets
        if asset.target == target and matches_version(version, asset.version_base)
    ]
    if not candidates:
        available_versions = sorted(
            {a.version_base for a in assets if a.target == target},
            key=parse_version_parts,
        )
        if available_versions:
            raise RuntimeError(
                f"Python {version} not available for {target}. "
                f"Available: {', '.join(available_versions)}"
            )
        available_targets = sorted({a.target for a in assets})
        raise RuntimeError(
            f"No PBS assets found for {target}. "
            f"Available targets: {', '.join(available_targets[:10])}..."
        )

    # Pick the latest patch version
    versions = sorted(
        {asset.version_base for asset in candidates},
        key=parse_version_parts,
    )
    chosen_version = versions[-1]
    candidates = [asset for asset in candidates if asset.version_base == chosen_version]

    # Prefer stripped > install_only > others
    flavor_order = {"install_only_stripped": 0, "install_only": 1}

    def sort_key(asset: PbsAsset) -> tuple[int, int]:
        flavor_rank = flavor_order.get(asset.flavor, 99)
        build_rank = int(asset.build_id) if asset.build_id.isdigit() else 0
        return (flavor_rank, -build_rank)

    candidates.sort(key=sort_key)
    for asset in candidates:
        if asset.flavor in flavor_order:
            return asset
    return candidates[0]


def fetch_and_extract(
    asset: PbsAsset,
    cache_dir: Path,
    force: bool,
    show_progress: bool = False,
) -> PbsEntry:
    """Download and extract a PBS asset, returning the cache entry.

    The tarball is deleted after extraction to save disk space.
    """
    entry_dir = cache_dir / asset.target / asset.version_base
    meta_path = entry_dir / "metadata.json"

    # Check if already cached with matching SHA256
    if meta_path.exists() and not force:
        entry = load_entry(meta_path)
        if entry.sha256 == asset.sha256:
            return entry

    entry_dir.mkdir(parents=True, exist_ok=True)
    tar_path = entry_dir / asset.name

    try:
        download_asset(asset, tar_path, show_progress)
        verify_sha256(tar_path, asset.sha256, asset.name)

        include_dir = None
        sysconfig_path = None

        with tarfile.open(tar_path, "r:gz") as tf:
            members = [m for m in tf.getmembers() if is_safe_member(m)]

            # Extract sysconfig
            sysconfig_member = next(
                (
                    m
                    for m in members
                    if "_sysconfigdata" in m.name and m.name.endswith(".py")
                ),
                None,
            )
            if sysconfig_member:
                sysconfig_path = entry_dir / sysconfig_member.name
                tf.extract(sysconfig_member, entry_dir)

            # Extract headers
            include_members = [
                m for m in members if m.name.startswith("python/include/")
            ]
            tf.extractall(entry_dir, members=include_members)
            if include_members:
                include_dir = resolve_python_include(entry_dir / "python" / "include")

        if not include_dir or not sysconfig_path:
            raise RuntimeError("PBS archive missing include/sysconfig data")

        ext_suffix = read_ext_suffix(sysconfig_path)

        entry = PbsEntry(
            version=asset.version_base,
            build_id=asset.build_id,
            target=asset.target,
            include_dir=include_dir,
            sysconfig_path=sysconfig_path,
            ext_suffix=ext_suffix,
            asset_name=asset.name,
            asset_url=asset.url,
            sha256=asset.sha256,
        )
        write_entry(entry, meta_path)
        return entry

    finally:
        # Always clean up tarball to save disk space
        if tar_path.exists():
            tar_path.unlink()


def download_asset(asset: PbsAsset, path: Path, show_progress: bool) -> None:
    """Download a PBS asset to the given path."""
    click.echo(f"Downloading {asset.name}")
    with httpx.stream("GET", asset.url, timeout=120.0, follow_redirects=True) as resp:
        resp.raise_for_status()
        total = resp.headers.get("Content-Length")
        length = int(total) if total and total.isdigit() else None
        with path.open("wb") as f:
            if show_progress:
                with click.progressbar(
                    length=length,
                    label="  Progress",
                    show_eta=True,
                ) as bar:
                    for chunk in resp.iter_bytes():
                        f.write(chunk)
                        bar.update(len(chunk))
            else:
                for chunk in resp.iter_bytes():
                    f.write(chunk)


def verify_sha256(path: Path, expected: str, name: str) -> None:
    """Verify the SHA256 hash of a downloaded file."""
    sha256 = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            sha256.update(chunk)
    actual = sha256.hexdigest()
    if actual != expected:
        path.unlink()  # Remove corrupted file
        raise RuntimeError(
            f"SHA256 mismatch for {name}: expected {expected}, got {actual}"
        )


def read_ext_suffix(sysconfig_path: Path) -> str:
    """Extract EXT_SUFFIX from a sysconfig data file."""
    content = sysconfig_path.read_text()
    tree = ast.parse(content)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == "build_time_vars"
            for target in node.targets
        ):
            data = ast.literal_eval(node.value)
            ext_suffix = data.get("EXT_SUFFIX")
            if not ext_suffix:
                raise RuntimeError("EXT_SUFFIX missing from sysconfig")
            return ext_suffix
    raise RuntimeError("build_time_vars not found in sysconfig data")


def write_entry(entry: PbsEntry, path: Path) -> None:
    """Write a cache entry metadata file."""
    path.write_text(
        json.dumps(
            {
                "version": entry.version,
                "build_id": entry.build_id,
                "target": entry.target,
                "include_dir": str(entry.include_dir),
                "sysconfig_path": str(entry.sysconfig_path),
                "ext_suffix": entry.ext_suffix,
                "asset_name": entry.asset_name,
                "asset_url": entry.asset_url,
                "sha256": entry.sha256,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )


def load_entry(path: Path) -> PbsEntry:
    """Load a cache entry from its metadata file."""
    data = json.loads(path.read_text())
    entry = PbsEntry(
        version=data["version"],
        build_id=data.get("build_id"),
        target=data["target"],
        include_dir=Path(data["include_dir"]),
        sysconfig_path=Path(data["sysconfig_path"]),
        ext_suffix=data["ext_suffix"],
        asset_name=data["asset_name"],
        asset_url=data["asset_url"],
        sha256=data.get("sha256"),
    )
    return fix_entry_include_dir(entry, path)


def resolve_python_include(include_root: Path) -> Path | None:
    """Find the Python.h directory within an include root."""
    if include_root.is_dir() and (include_root / "Python.h").is_file():
        return include_root
    if not include_root.is_dir():
        return None

    candidates = [
        child
        for child in include_root.iterdir()
        if child.is_dir() and (child / "Python.h").is_file()
    ]
    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0]

    def version_key(path: Path) -> tuple[int, int] | None:
        match = re.search(r"python(\d+)\.(\d+)", path.name)
        if not match:
            return None
        return (int(match.group(1)), int(match.group(2)))

    versioned = [(version_key(path), path) for path in candidates]
    versioned = [item for item in versioned if item[0] is not None]
    if versioned:
        return sorted(versioned, key=lambda item: item[0])[-1][1]
    return sorted(candidates, key=lambda path: path.name)[-1]


def fix_entry_include_dir(entry: PbsEntry, meta_path: Path) -> PbsEntry:
    """Fix include_dir path if it points to wrong location."""
    resolved = resolve_python_include(entry.include_dir)
    if not resolved or resolved == entry.include_dir:
        return entry
    updated = replace(entry, include_dir=resolved)
    write_entry(updated, meta_path)
    return updated


def is_safe_member(member: tarfile.TarInfo) -> bool:
    """Check if a tar member is safe to extract (no path traversal)."""
    path = Path(member.name)
    if path.is_absolute():
        return False
    return ".." not in path.parts


def find_cached_entry(
    cache_dir: Path,
    version: str,
    target: str,
) -> PbsEntry | None:
    """Find a cached entry matching the version and target."""
    target_dir = cache_dir / target
    if not target_dir.is_dir():
        return None

    candidates: list[PbsEntry] = []
    for child in target_dir.iterdir():
        meta = child / "metadata.json"
        if not meta.is_file():
            continue
        entry = load_entry(meta)
        if matches_version(version, entry.version):
            candidates.append(entry)

    if not candidates:
        return None

    candidates.sort(key=lambda e: parse_version_parts(e.version))
    return candidates[-1]


def resolve_versions_for_target(assets: list[PbsAsset], target: str) -> list[str]:
    """Get all available Python versions for a target, one per minor version."""
    versions: dict[tuple[int, int], str] = {}
    for asset in assets:
        if asset.target != target:
            continue
        parts = parse_version_parts(asset.version_base)
        if len(parts) < 2:
            continue
        key = (parts[0], parts[1])
        if key not in versions or parse_version_parts(versions[key]) < parts:
            versions[key] = asset.version_base

    return [versions[key] for key in sorted(versions.keys())]
