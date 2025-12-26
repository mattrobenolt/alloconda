"""Tests for cli_build command."""

from __future__ import annotations

import os
from pathlib import Path

from click.testing import CliRunner

from alloconda.cli_build import build as build_cmd


def test_build_uses_project_root_as_workdir(monkeypatch, tmp_path: Path) -> None:
    root = tmp_path / "project"
    root.mkdir()
    (root / "pyproject.toml").write_text(
        "\n".join(
            [
                "[project]",
                'name = "demo"',
                'version = "0.0.0"',
            ]
        )
    )

    nested = root / "nested"
    nested.mkdir()

    captured: dict[str, Path | None] = {"workdir": None}

    def fake_build_extension(*, workdir: Path | None, **_kwargs: object) -> Path:
        captured["workdir"] = workdir
        return root / "dummy"

    monkeypatch.setattr("alloconda.cli_build.build_extension", fake_build_extension)

    runner = CliRunner()
    cwd = Path.cwd()
    try:
        os.chdir(nested)
        result = runner.invoke(build_cmd, [])
    finally:
        os.chdir(cwd)

    assert result.exit_code == 0, result.output
    assert captured["workdir"] == root


def test_build_uses_configured_build_step(monkeypatch, tmp_path: Path) -> None:
    root = tmp_path / "project"
    root.mkdir()
    (root / "pyproject.toml").write_text(
        "\n".join(
            [
                "[project]",
                'name = "demo"',
                'version = "0.0.0"',
                "[tool.alloconda]",
                'build-step = "lib"',
            ]
        )
    )

    captured: dict[str, str | None] = {"build_step": None}

    def fake_build_extension(*, build_step: str | None, **_kwargs: object) -> Path:
        captured["build_step"] = build_step
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
    assert captured["build_step"] == "lib"
