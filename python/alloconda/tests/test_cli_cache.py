"""Tests for cache CLI commands."""

from __future__ import annotations

from pathlib import Path

from click.testing import CliRunner

from alloconda.cli_cache import cache as cache_cmd
from alloconda.pbs import PbsEntry, write_entry


def write_cache_entry(
    cache_dir: Path, version: str, build_id: str, target: str
) -> None:
    entry_dir = cache_dir / target / version
    include_dir = entry_dir / "python" / "include" / "python3"
    include_dir.mkdir(parents=True, exist_ok=True)
    (include_dir / "Python.h").write_text("// stub")

    sysconfig_path = entry_dir / "_sysconfigdata.py"
    sysconfig_path.write_text("build_time_vars = {'EXT_SUFFIX': '.so'}")

    entry = PbsEntry(
        version=version,
        build_id=build_id,
        target=target,
        include_dir=include_dir,
        sysconfig_path=sysconfig_path,
        ext_suffix=".so",
        asset_name="asset.tar.gz",
        asset_url="https://example.invalid/asset.tar.gz",
        sha256="deadbeef",
    )
    write_entry(entry, entry_dir / "metadata.json")


def test_cache_path_prints_location(tmp_path: Path) -> None:
    runner = CliRunner()
    result = runner.invoke(cache_cmd, ["path", "--cache-dir", str(tmp_path)])
    assert result.exit_code == 0, result.output
    assert str(tmp_path) in result.output


def test_cache_list_empty(tmp_path: Path) -> None:
    runner = CliRunner()
    result = runner.invoke(cache_cmd, ["list", "--cache-dir", str(tmp_path)])
    assert result.exit_code == 0, result.output
    assert f"No cached headers in {tmp_path}" in result.output


def test_cache_list_entries(tmp_path: Path) -> None:
    cache_dir = tmp_path / "pbs"
    write_cache_entry(cache_dir, "3.13.1", "20240101", "x86_64-unknown-linux-gnu")
    write_cache_entry(cache_dir, "3.14.0", "20240202", "aarch64-apple-darwin")

    runner = CliRunner()
    result = runner.invoke(cache_cmd, ["list", "--cache-dir", str(cache_dir)])
    assert result.exit_code == 0, result.output
    assert "Cached Python Headers" in result.output
    assert "3.13.1+20240101" in result.output
    assert "3.14.0+20240202" in result.output
    assert "x86_64-unknown-linux-gnu" in result.output
    assert "aarch64-apple-darwin" in result.output


def test_cache_clear_removes_directory(tmp_path: Path) -> None:
    cache_dir = tmp_path / "pbs"
    cache_dir.mkdir()
    (cache_dir / "sentinel.txt").write_text("data")

    runner = CliRunner()
    result = runner.invoke(cache_cmd, ["clear", "--cache-dir", str(cache_dir)])
    assert result.exit_code == 0, result.output
    assert not cache_dir.exists()
