"""Tests for cli_helpers module."""

import pytest

from alloconda.cli_helpers import (
    default_platform_tag,
    resolve_arch,
    resolve_platform_tag,
)


class TestResolveArch:
    """Tests for resolve_arch function."""

    def test_x86_64(self) -> None:
        assert resolve_arch("x86_64") == "x86_64"

    def test_amd64_normalized(self) -> None:
        assert resolve_arch("amd64") == "x86_64"

    def test_aarch64(self) -> None:
        assert resolve_arch("aarch64") == "aarch64"

    def test_arm64_normalized(self) -> None:
        assert resolve_arch("arm64") == "aarch64"

    def test_case_insensitive(self) -> None:
        assert resolve_arch("AMD64") == "x86_64"
        assert resolve_arch("ARM64") == "aarch64"


class TestResolvePlatformTag:
    """Tests for resolve_platform_tag function."""

    def test_manylinux_shorthand(self) -> None:
        """Manylinux shorthand is expanded."""
        result = resolve_platform_tag(None, "2_28", None, "x86_64")
        assert result == "manylinux_2_28_x86_64"

    def test_musllinux_shorthand(self) -> None:
        """Musllinux shorthand is expanded."""
        result = resolve_platform_tag(None, None, "1_2", "x86_64")
        assert result == "musllinux_1_2_x86_64"

    def test_explicit_platform_tag(self) -> None:
        """Explicit platform tag is used as-is."""
        result = resolve_platform_tag("macosx_14_0_arm64", None, None, None)
        assert result == "macosx_14_0_arm64"

    def test_rejects_linux_platform_tag(self) -> None:
        """Generic linux_* platform tags are rejected."""
        import click

        with pytest.raises(click.ClickException) as exc_info:
            resolve_platform_tag("linux_x86_64", None, None, None)
        assert "not accepted by PyPI" in str(exc_info.value)
        assert "--manylinux" in str(exc_info.value)

    def test_rejects_linux_aarch64(self) -> None:
        """Generic linux_aarch64 is also rejected."""
        import click

        with pytest.raises(click.ClickException):
            resolve_platform_tag("linux_aarch64", None, None, None)

    def test_rejects_platform_tag_with_manylinux(self) -> None:
        """Cannot specify both platform-tag and manylinux."""
        import click

        with pytest.raises(click.ClickException) as exc_info:
            resolve_platform_tag("some_tag", "2_28", None, None)
        assert "Use either" in str(exc_info.value)

    def test_rejects_platform_tag_with_musllinux(self) -> None:
        """Cannot specify both platform-tag and musllinux."""
        import click

        with pytest.raises(click.ClickException):
            resolve_platform_tag("some_tag", None, "1_2", None)


class TestDefaultPlatformTag:
    """Tests for default_platform_tag function."""

    def test_returns_string(self) -> None:
        """Returns a platform tag string."""
        tag = default_platform_tag()
        assert isinstance(tag, str)
        assert len(tag) > 0

    def test_no_hyphens_or_dots(self) -> None:
        """Platform tag has underscores, not hyphens or dots."""
        tag = default_platform_tag()
        assert "-" not in tag
        assert "." not in tag

    def test_linux_defaults_to_manylinux(self) -> None:
        """On Linux, defaults to manylinux_2_28 instead of generic linux."""
        tag = default_platform_tag()
        # If we're on Linux, it should be manylinux
        if "linux" in tag.lower():
            assert tag.startswith("manylinux_2_28_")
