"""Tests for ziglang PyPI package support."""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import pytest
from click.testing import CliRunner

from alloconda.cli_build import build as build_cmd


class TestResolveZigCommand:
    """Tests for resolve_zig_command function."""

    @pytest.mark.skipif(
        importlib.util.find_spec("ziglang") is None,
        reason="ziglang package not installed",
    )
    def test_with_pypi_zig_explicit(self) -> None:
        """Returns python -m ziglang when use_pypi_zig=True."""
        from alloconda.cli_helpers import resolve_zig_command

        cmd = resolve_zig_command(use_pypi_zig=True)
        assert cmd == [sys.executable, "-m", "ziglang"]

    def test_uses_system_zig_when_available(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Returns zig when system zig is available."""
        from alloconda import cli_helpers

        monkeypatch.setattr("shutil.which", lambda x: "/usr/bin/zig" if x == "zig" else None)

        cmd = cli_helpers.resolve_zig_command(use_pypi_zig=False)
        assert cmd == ["zig"]

    def test_falls_back_to_ziglang_when_no_system_zig(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Falls back to ziglang PyPI when system zig not found."""
        from alloconda import cli_helpers

        monkeypatch.setattr("shutil.which", lambda _: None)
        monkeypatch.setattr(
            importlib.util, "find_spec", lambda x: MagicMock() if x == "ziglang" else None
        )

        cmd = cli_helpers.resolve_zig_command(use_pypi_zig=False)
        assert cmd == [sys.executable, "-m", "ziglang"]

    def test_raises_when_no_zig_available(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Raises ClickException when neither system zig nor ziglang available."""
        import click
        from alloconda import cli_helpers

        monkeypatch.setattr("shutil.which", lambda _: None)
        monkeypatch.setattr(importlib.util, "find_spec", lambda _: None)

        with pytest.raises(click.ClickException) as exc_info:
            cli_helpers.resolve_zig_command(use_pypi_zig=False)
        assert "No zig installation found" in str(exc_info.value)

    def test_raises_when_pypi_zig_forced_but_not_installed(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Raises ClickException when use_pypi_zig=True but ziglang not installed."""
        import click
        from alloconda import cli_helpers

        monkeypatch.setattr(importlib.util, "find_spec", lambda _: None)

        with pytest.raises(click.ClickException) as exc_info:
            cli_helpers.resolve_zig_command(use_pypi_zig=True)
        assert "ziglang" in str(exc_info.value)
        assert "not installed" in str(exc_info.value)


class TestBuildWithPypiZig:
    """Tests for build command with --use-pypi-zig flag."""

    def test_flag_passed_to_build_extension(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Verify --use-pypi-zig flag is passed to build_extension."""
        root = tmp_path / "project"
        root.mkdir()
        (root / "pyproject.toml").write_text(
            '[project]\nname = "demo"\nversion = "0.0.0"\n'
        )

        captured: dict[str, Any] = {}

        def fake_build_extension(**kwargs: object) -> Path:
            captured.update(kwargs)
            return root / "dummy"

        monkeypatch.setattr("alloconda.cli_build.build_extension", fake_build_extension)

        runner = CliRunner()
        cwd = Path.cwd()
        try:
            os.chdir(root)
            result = runner.invoke(build_cmd, ["--use-pypi-zig"])
        finally:
            os.chdir(cwd)

        assert result.exit_code == 0, result.output
        assert captured.get("use_pypi_zig") is True

    def test_config_sets_use_pypi_zig(
        self, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
    ) -> None:
        """Verify [tool.alloconda] use-pypi-zig = true is read from config."""
        root = tmp_path / "project"
        root.mkdir()
        (root / "pyproject.toml").write_text(
            "[project]\n"
            'name = "demo"\n'
            'version = "0.0.0"\n'
            "[tool.alloconda]\n"
            "use-pypi-zig = true\n"
        )

        captured: dict[str, Any] = {}

        def fake_build_extension(**kwargs: object) -> Path:
            captured.update(kwargs)
            return root / "dummy"

        monkeypatch.setattr("alloconda.cli_build.build_extension", fake_build_extension)

        runner = CliRunner()
        cwd = Path.cwd()
        try:
            os.chdir(root)
            result = runner.invoke(build_cmd, [])
        finally:
            os.chdir(cwd)

        assert result.exit_code == 0, result.output
        assert captured.get("use_pypi_zig") is True


class TestRunZigBuild:
    """Tests for run_zig_build with use_pypi_zig parameter."""

    @pytest.mark.skipif(
        importlib.util.find_spec("ziglang") is None,
        reason="ziglang package not installed",
    )
    def test_uses_pypi_zig_command(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Verify run_zig_build invokes python -m ziglang when use_pypi_zig=True."""
        from alloconda import cli_helpers

        captured_cmd: list[str] = []

        def fake_subprocess_run(cmd: list[str], **kwargs: object) -> MagicMock:
            captured_cmd.extend(cmd)
            return MagicMock(returncode=0)

        monkeypatch.setattr("subprocess.run", fake_subprocess_run)

        cli_helpers.run_zig_build(
            release=True,
            zig_target=None,
            python_include=None,
            use_pypi_zig=True,
        )

        assert captured_cmd[:3] == [sys.executable, "-m", "ziglang"]
        assert "build" in captured_cmd

    def test_uses_system_zig_by_default(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Verify run_zig_build invokes zig when system zig available."""
        from alloconda import cli_helpers

        captured_cmd: list[str] = []

        def fake_subprocess_run(cmd: list[str], **kwargs: object) -> MagicMock:
            captured_cmd.extend(cmd)
            return MagicMock(returncode=0)

        monkeypatch.setattr("subprocess.run", fake_subprocess_run)
        monkeypatch.setattr("shutil.which", lambda x: "/usr/bin/zig" if x == "zig" else None)

        cli_helpers.run_zig_build(
            release=True,
            zig_target=None,
            python_include=None,
            use_pypi_zig=False,
        )

        assert captured_cmd[0] == "zig"
        assert "build" in captured_cmd
