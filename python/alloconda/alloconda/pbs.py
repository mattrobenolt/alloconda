import ast
import json
import os
import re
import tarfile
from dataclasses import dataclass
from pathlib import Path

import click
import httpx

PBS_RELEASE_URL = (
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"
)
PBS_CACHE_ENV = "ALLOCONDA_PBS_CACHE"


@dataclass(frozen=True)
class PbsAsset:
    name: str
    url: str
    version_base: str
    build_id: str | None
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


def cache_root(explicit: Path | None) -> Path:
    if explicit:
        return explicit
    env_value = os.environ.get(PBS_CACHE_ENV)
    if env_value:
        return Path(env_value)
    return Path.home() / ".cache" / "alloconda" / "pbs"


def fetch_release_assets() -> list[PbsAsset]:
    headers = {"Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    resp = httpx.get(PBS_RELEASE_URL, headers=headers, timeout=30.0)
    resp.raise_for_status()
    data = resp.json()
    assets = []
    for asset in data.get("assets", []):
        parsed = parse_asset(asset["name"], asset["browser_download_url"])
        if parsed:
            assets.append(parsed)
    return assets


def parse_asset(name: str, url: str) -> PbsAsset | None:
    if not name.startswith("cpython-"):
        return None
    if not name.endswith(".tar.gz"):
        return None
    stem = name[len("cpython-") : -len(".tar.gz")]
    parts = stem.split("-")
    if len(parts) < 3:
        return None
    version_build = parts[0]
    flavor = parts[-1]
    target = "-".join(parts[1:-1])
    if "+" in version_build:
        version_base, build_id = version_build.split("+", 1)
    else:
        version_base, build_id = version_build, None
    return PbsAsset(
        name=name,
        url=url,
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
    candidates = [
        asset
        for asset in assets
        if asset.target == target and matches_version(version, asset.version_base)
    ]
    if not candidates:
        raise RuntimeError(f"No PBS assets found for {version} on {target}")

    versions = sorted(
        {asset.version_base for asset in candidates},
        key=parse_version_parts,
    )
    chosen_version = versions[-1]
    candidates = [asset for asset in candidates if asset.version_base == chosen_version]

    flavor_order = {"install_only_stripped": 0, "install_only": 1}

    def sort_key(asset: PbsAsset) -> tuple[int, int]:
        flavor_rank = flavor_order.get(asset.flavor, 99)
        build_rank = (
            int(asset.build_id) if asset.build_id and asset.build_id.isdigit() else 0
        )
        build_rank = (
            int(asset.build_id) if asset.build_id and asset.build_id.isdigit() else 0
        )
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
    entry_dir = cache_dir / asset.target / asset.version_base
    meta_path = entry_dir / "metadata.json"
    if meta_path.exists() and not force:
        return load_entry(meta_path)

    entry_dir.mkdir(parents=True, exist_ok=True)
    tar_path = entry_dir / asset.name

    download_asset(asset, tar_path, show_progress)

    include_dir = None
    sysconfig_path = None

    with tarfile.open(tar_path, "r:gz") as tf:
        members = [m for m in tf.getmembers() if is_safe_member(m)]
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

        include_members = [m for m in members if m.name.startswith("python/include/")]
        tf.extractall(entry_dir, members=include_members)
        if include_members:
            include_dir = entry_dir / "python" / "include"

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
    )
    write_entry(entry, meta_path)
    return entry


def download_asset(asset: PbsAsset, path: Path, show_progress: bool) -> None:
    with httpx.stream("GET", asset.url, timeout=120.0, follow_redirects=True) as resp:
        resp.raise_for_status()
        total = resp.headers.get("Content-Length")
        length = int(total) if total and total.isdigit() else None
        with path.open("wb") as f:
            if show_progress:
                with click.progressbar(
                    length=length,
                    label=f"Downloading {asset.name}",
                    show_eta=True,
                ) as bar:
                    for chunk in resp.iter_bytes():
                        f.write(chunk)
                        bar.update(len(chunk))
            else:
                for chunk in resp.iter_bytes():
                    f.write(chunk)


def read_ext_suffix(sysconfig_path: Path) -> str:
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
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )


def load_entry(path: Path) -> PbsEntry:
    data = json.loads(path.read_text())
    return PbsEntry(
        version=data["version"],
        build_id=data.get("build_id"),
        target=data["target"],
        include_dir=Path(data["include_dir"]),
        sysconfig_path=Path(data["sysconfig_path"]),
        ext_suffix=data["ext_suffix"],
        asset_name=data["asset_name"],
        asset_url=data["asset_url"],
    )


def is_safe_member(member: tarfile.TarInfo) -> bool:
    path = Path(member.name)
    if path.is_absolute():
        return False
    return ".." not in path.parts


def find_cached_entry(
    cache_dir: Path,
    version: str,
    target: str,
) -> PbsEntry | None:
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
