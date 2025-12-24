"""Tests for pbs module."""

import pytest

from alloconda.pbs import (
    PbsAsset,
    matches_version,
    parse_asset_filename,
    parse_sha256sums,
    select_asset,
)


class TestParseSha256sums:
    """Tests for parse_sha256sums function."""

    def test_parses_valid_lines(self) -> None:
        """Parses SHA256SUMS content into assets."""
        content = """\
abc123  cpython-3.14.2+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz
def456  cpython-3.14.2+20251217-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz
"""
        assets = parse_sha256sums(content)
        assert len(assets) == 2
        assert assets[0].sha256 == "abc123"
        assert assets[0].version_base == "3.14.2"
        assert assets[0].build_id == "20251217"
        assert assets[0].target == "aarch64-apple-darwin"
        assert assets[0].flavor == "install_only_stripped"

    def test_skips_non_cpython_files(self) -> None:
        """Non-cpython files are skipped."""
        content = """\
abc123  SHA256SUMS.sig
def456  cpython-3.14.2+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz
"""
        assets = parse_sha256sums(content)
        assert len(assets) == 1
        assert assets[0].version_base == "3.14.2"

    def test_skips_zst_files(self) -> None:
        """Only .tar.gz files are included, not .tar.zst."""
        content = """\
abc123  cpython-3.14.2+20251217-aarch64-apple-darwin-debug-full.tar.zst
def456  cpython-3.14.2+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz
"""
        assets = parse_sha256sums(content)
        assert len(assets) == 1
        assert assets[0].flavor == "install_only_stripped"

    def test_skips_empty_lines(self) -> None:
        """Empty lines are skipped."""
        content = """\
abc123  cpython-3.14.2+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz

def456  cpython-3.13.11+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz
"""
        assets = parse_sha256sums(content)
        assert len(assets) == 2

    def test_constructs_download_url(self) -> None:
        """Download URL is constructed from build_id and filename."""
        content = "abc123  cpython-3.14.2+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz"
        assets = parse_sha256sums(content)
        assert assets[0].url == (
            "https://github.com/astral-sh/python-build-standalone/releases/download/"
            "20251217/cpython-3.14.2+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz"
        )


class TestParseAssetFilename:
    """Tests for parse_asset_filename function."""

    def test_parses_standard_filename(self) -> None:
        """Parses a standard PBS filename."""
        asset = parse_asset_filename(
            "cpython-3.14.2+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz",
            "abc123",
        )
        assert asset is not None
        assert asset.version_base == "3.14.2"
        assert asset.build_id == "20251217"
        assert asset.target == "aarch64-apple-darwin"
        assert asset.flavor == "install_only_stripped"
        assert asset.sha256 == "abc123"

    def test_parses_linux_target(self) -> None:
        """Parses Linux target with gnu suffix."""
        asset = parse_asset_filename(
            "cpython-3.13.11+20251217-x86_64-unknown-linux-gnu-install_only.tar.gz",
            "def456",
        )
        assert asset is not None
        assert asset.target == "x86_64-unknown-linux-gnu"
        assert asset.flavor == "install_only"

    def test_parses_musl_target(self) -> None:
        """Parses Linux musl target."""
        asset = parse_asset_filename(
            "cpython-3.12.12+20251217-aarch64-unknown-linux-musl-install_only_stripped.tar.gz",
            "ghi789",
        )
        assert asset is not None
        assert asset.target == "aarch64-unknown-linux-musl"

    def test_returns_none_for_non_cpython(self) -> None:
        """Returns None for non-cpython files."""
        asset = parse_asset_filename("SHA256SUMS", "abc123")
        assert asset is None

    def test_returns_none_for_non_targz(self) -> None:
        """Returns None for non-.tar.gz files."""
        asset = parse_asset_filename(
            "cpython-3.14.2+20251217-aarch64-apple-darwin-debug-full.tar.zst",
            "abc123",
        )
        assert asset is None

    def test_returns_none_without_build_id(self) -> None:
        """Returns None if version doesn't have build ID."""
        asset = parse_asset_filename(
            "cpython-3.14.2-aarch64-apple-darwin-install_only.tar.gz",
            "abc123",
        )
        assert asset is None


class TestMatchesVersion:
    """Tests for matches_version function."""

    def test_exact_match(self) -> None:
        """Exact version matches."""
        assert matches_version("3.14.2", "3.14.2") is True

    def test_minor_matches_patch(self) -> None:
        """Minor version matches any patch version."""
        assert matches_version("3.14", "3.14.2") is True
        assert matches_version("3.14", "3.14.0") is True

    def test_major_matches_minor(self) -> None:
        """Major version matches any minor version."""
        assert matches_version("3", "3.14.2") is True
        assert matches_version("3", "3.10.0") is True

    def test_different_minor_no_match(self) -> None:
        """Different minor versions don't match."""
        assert matches_version("3.14", "3.13.11") is False

    def test_all_matches_everything(self) -> None:
        """'all' matches any version."""
        assert matches_version("all", "3.14.2") is True
        assert matches_version("all", "3.10.0") is True


class TestSelectAsset:
    """Tests for select_asset function."""

    def test_selects_matching_version_and_target(self) -> None:
        """Selects asset matching version and target."""
        assets = [
            PbsAsset(
                name="cpython-3.14.2+20251217-aarch64-apple-darwin-install_only_stripped.tar.gz",
                url="https://example.com/a",
                sha256="abc",
                version_base="3.14.2",
                build_id="20251217",
                target="aarch64-apple-darwin",
                flavor="install_only_stripped",
            ),
            PbsAsset(
                name="cpython-3.14.2+20251217-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz",
                url="https://example.com/b",
                sha256="def",
                version_base="3.14.2",
                build_id="20251217",
                target="x86_64-unknown-linux-gnu",
                flavor="install_only_stripped",
            ),
        ]
        result = select_asset(assets, "3.14", "aarch64-apple-darwin")
        assert result.target == "aarch64-apple-darwin"

    def test_prefers_stripped_over_install_only(self) -> None:
        """Prefers install_only_stripped over install_only."""
        assets = [
            PbsAsset(
                name="a.tar.gz",
                url="https://example.com/a",
                sha256="abc",
                version_base="3.14.2",
                build_id="20251217",
                target="aarch64-apple-darwin",
                flavor="install_only",
            ),
            PbsAsset(
                name="b.tar.gz",
                url="https://example.com/b",
                sha256="def",
                version_base="3.14.2",
                build_id="20251217",
                target="aarch64-apple-darwin",
                flavor="install_only_stripped",
            ),
        ]
        result = select_asset(assets, "3.14", "aarch64-apple-darwin")
        assert result.flavor == "install_only_stripped"

    def test_selects_latest_patch_version(self) -> None:
        """Selects the latest patch version when multiple match."""
        assets = [
            PbsAsset(
                name="a.tar.gz",
                url="https://example.com/a",
                sha256="abc",
                version_base="3.14.0",
                build_id="20251217",
                target="aarch64-apple-darwin",
                flavor="install_only_stripped",
            ),
            PbsAsset(
                name="b.tar.gz",
                url="https://example.com/b",
                sha256="def",
                version_base="3.14.2",
                build_id="20251217",
                target="aarch64-apple-darwin",
                flavor="install_only_stripped",
            ),
        ]
        result = select_asset(assets, "3.14", "aarch64-apple-darwin")
        assert result.version_base == "3.14.2"

    def test_raises_for_missing_version(self) -> None:
        """Raises RuntimeError when version not found."""
        assets = [
            PbsAsset(
                name="a.tar.gz",
                url="https://example.com/a",
                sha256="abc",
                version_base="3.14.2",
                build_id="20251217",
                target="aarch64-apple-darwin",
                flavor="install_only_stripped",
            ),
        ]
        with pytest.raises(RuntimeError) as exc_info:
            select_asset(assets, "3.9", "aarch64-apple-darwin")
        assert "not available" in str(exc_info.value)
        assert "3.14.2" in str(exc_info.value)  # Shows available versions

    def test_raises_for_missing_target(self) -> None:
        """Raises RuntimeError when target not found."""
        assets = [
            PbsAsset(
                name="a.tar.gz",
                url="https://example.com/a",
                sha256="abc",
                version_base="3.14.2",
                build_id="20251217",
                target="aarch64-apple-darwin",
                flavor="install_only_stripped",
            ),
        ]
        with pytest.raises(RuntimeError) as exc_info:
            select_asset(assets, "3.14", "x86_64-pc-windows-msvc")
        assert "No PBS assets found" in str(exc_info.value)
