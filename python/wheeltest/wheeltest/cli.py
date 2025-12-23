"""
Multi-Python version wheel testing harness for alloconda projects.

Usage:
    wheeltest zigadd                    # Test all configured versions
    wheeltest zigadd -p 3.13            # Test specific version
    wheeltest zigadd --no-build         # Use existing wheels
    wheeltest zigadd -- -v -k test_add  # Pass args to pytest
"""

from __future__ import annotations

import platform
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

import click


def get_native_platform_tag() -> str:
    """Get the platform tag for native wheels on this machine."""
    system = platform.system().lower()
    machine = platform.machine().lower()

    if system == "darwin":
        # macOS: e.g., macosx_14_0_arm64
        version = platform.mac_ver()[0]
        major, minor, *_ = version.split(".")
        arch = "arm64" if machine == "arm64" else "x86_64"
        return f"macosx_{major}_{minor}_{arch}"
    elif system == "linux":
        # Linux: typically manylinux or musllinux
        arch = "aarch64" if machine == "aarch64" else "x86_64"
        return f"manylinux_2_28_{arch}"
    elif system == "windows":
        arch = "amd64" if machine == "amd64" or machine == "x86_64" else machine
        return f"win_{arch}"
    else:
        raise click.ClickException(f"Unsupported platform: {system}")


def find_package_dir(name: str) -> Path:
    """Find the package directory given a package name."""
    # Look relative to CWD first
    candidates = [
        Path.cwd() / "python" / name,
        Path.cwd() / name,
        Path.cwd(),
    ]
    for candidate in candidates:
        pyproject = candidate / "pyproject.toml"
        if pyproject.exists():
            return candidate

    raise click.ClickException(
        f"Could not find package '{name}'. "
        f"Tried: {', '.join(str(c) for c in candidates)}"
    )


def read_python_versions(package_dir: Path) -> list[str]:
    """Read python-version from [tool.alloconda] in pyproject.toml."""
    pyproject_path = package_dir / "pyproject.toml"
    if not pyproject_path.exists():
        raise click.ClickException(f"No pyproject.toml found in {package_dir}")

    with open(pyproject_path, "rb") as f:
        data = tomllib.load(f)

    tool_alloconda = data.get("tool", {}).get("alloconda", {})
    versions = tool_alloconda.get("python-version", [])

    if isinstance(versions, str):
        versions = [versions]

    return list(versions)


def get_native_arch() -> str:
    """Get the native architecture string for wheel matching."""
    machine = platform.machine().lower()
    if machine == "arm64":
        return "arm64"
    elif machine == "aarch64":
        return "aarch64"
    elif machine in ("x86_64", "amd64"):
        return "x86_64"
    else:
        return machine


def is_compatible_platform(wheel_platform: str, native_platform: str) -> bool:
    """Check if a wheel platform is compatible with the native platform.

    For macOS, wheels built for older versions are forward compatible.
    We just need to match the architecture.
    """
    native_arch = get_native_arch()
    system = platform.system().lower()

    if system == "darwin":
        # macOS: match on architecture, any version is fine
        # macosx_14_0_arm64 is compatible with macosx_15_7_arm64
        return wheel_platform.startswith("macosx_") and wheel_platform.endswith(
            f"_{native_arch}"
        )
    elif system == "linux":
        # Linux: match manylinux/musllinux with correct arch
        return (
            wheel_platform.startswith("manylinux")
            or wheel_platform.startswith("musllinux")
        ) and wheel_platform.endswith(f"_{native_arch}")
    elif system == "windows":
        # Windows: direct match for now
        return native_platform in wheel_platform
    else:
        return native_platform in wheel_platform


def find_matching_wheel(
    dist_dir: Path, python_version: str, platform_tag: str
) -> Path | None:
    """Find a wheel matching the given Python version and platform."""
    # Convert 3.13 -> cp313
    major, minor = python_version.split(".")[:2]
    python_tag = f"cp{major}{minor}"

    for wheel in dist_dir.glob("*.whl"):
        parts = wheel.stem.split("-")
        if len(parts) >= 5:
            wheel_python = parts[2]
            wheel_platform = parts[4]
            if wheel_python == python_tag and is_compatible_platform(
                wheel_platform, platform_tag
            ):
                return wheel

    return None


def run_cmd(
    cmd: list[str],
    cwd: Path | None = None,
    check: bool = True,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Run a command with nice output."""
    click.echo(click.style(f"  $ {' '.join(cmd)}", dim=True))
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=check,
        capture_output=capture,
        text=True,
    )


def build_wheel(package_dir: Path, python_version: str) -> Path:
    """Build a native wheel for the given Python version."""
    run_cmd(
        ["alloconda", "wheel", "--python-version", python_version],
        cwd=package_dir,
    )

    dist_dir = package_dir / "dist"
    platform_tag = get_native_platform_tag()
    wheel = find_matching_wheel(dist_dir, python_version, platform_tag)

    if wheel is None:
        raise click.ClickException(
            f"Could not find wheel for Python {python_version} "
            f"with platform {platform_tag} in {dist_dir}"
        )

    return wheel


def create_venv(venv_dir: Path, python_version: str) -> Path:
    """Create a virtual environment with the specified Python version."""
    if venv_dir.exists():
        shutil.rmtree(venv_dir)

    run_cmd(
        [
            "uv",
            "venv",
            "--python",
            python_version,
            str(venv_dir),
            "--managed-python",
            "--no-config",
        ]
    )

    # Return path to python executable
    if sys.platform == "win32":
        return venv_dir / "Scripts" / "python.exe"
    else:
        return venv_dir / "bin" / "python"


def install_wheel(python_path: Path, wheel_path: Path) -> None:
    """Install a wheel and pytest into the venv."""
    run_cmd(
        [
            "uv",
            "pip",
            "install",
            "--python",
            str(python_path),
            str(wheel_path),
            "pytest",
        ]
    )


def run_tests(
    python_path: Path,
    tests_dir: Path,
    pytest_args: tuple[str, ...],
    workdir: Path,
) -> bool:
    """Run pytest and return True if tests pass.

    Tests are copied to a temp directory and run from the workdir to avoid
    importing from the source tree instead of the installed package.
    """
    # Copy tests to temp dir to isolate from source tree
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_tests = Path(tmpdir) / "tests"
        shutil.copytree(tests_dir, tmp_tests)

        # Also copy conftest.py from package root if it exists
        conftest = tests_dir.parent / "conftest.py"
        if conftest.exists():
            shutil.copy(conftest, Path(tmpdir) / "conftest.py")

        cmd = [str(python_path), "-m", "pytest", str(tmp_tests), *pytest_args]
        # Run from workdir (the venv dir) to avoid source tree in Python path
        result = run_cmd(cmd, cwd=workdir, check=False)
        return result.returncode == 0


@click.command()
@click.argument("package")
@click.option(
    "-p",
    "--python",
    "python_versions",
    multiple=True,
    help="Python version(s) to test (e.g., 3.13). Can be repeated.",
)
@click.option(
    "--no-build",
    is_flag=True,
    help="Skip wheel building, use existing wheels in dist/",
)
@click.option(
    "--build-only",
    is_flag=True,
    help="Only build wheels, don't run tests",
)
@click.option(
    "--dry-run",
    is_flag=True,
    help="Show what would be done without doing it",
)
@click.argument("pytest_args", nargs=-1, type=click.UNPROCESSED)
def main(
    package: str,
    python_versions: tuple[str, ...],
    no_build: bool,
    build_only: bool,
    dry_run: bool,
    pytest_args: tuple[str, ...],
) -> None:
    """
    Test wheels across multiple Python versions.

    PACKAGE is the name of the package to test (e.g., zigadd).

    Extra arguments after -- are passed to pytest.
    """
    package_dir = find_package_dir(package)
    click.echo(f"Package directory: {package_dir}")

    # Determine which Python versions to test
    if python_versions:
        versions = list(python_versions)
    else:
        versions = read_python_versions(package_dir)
        if not versions:
            raise click.ClickException(
                "No Python versions specified. Either pass -p/--python or add "
                "[tool.alloconda].python-version to pyproject.toml"
            )

    click.echo(f"Python versions: {', '.join(versions)}")

    platform_tag = get_native_platform_tag()
    click.echo(f"Native platform: {platform_tag}")

    dist_dir = package_dir / "dist"
    wheeltest_dir = package_dir / ".wheeltest"
    tests_dir = package_dir / "tests"

    if not tests_dir.exists() and not build_only:
        raise click.ClickException(f"No tests directory found at {tests_dir}")

    if dry_run:
        click.echo("\n[Dry run] Would perform the following:")
        if not no_build:
            click.echo(f"  - Clean {dist_dir}")
        for version in versions:
            if not no_build:
                click.echo(f"  - Build wheel for Python {version}")
            if not build_only:
                click.echo(f"  - Create venv at {wheeltest_dir / version}")
                click.echo("  - Install wheel + pytest")
                click.echo(f"  - Run pytest {tests_dir}")
        return

    # Always clean dist/ when building to ensure fresh wheels
    if not no_build and dist_dir.exists():
        click.echo(f"Cleaning {dist_dir}")
        shutil.rmtree(dist_dir)

    wheeltest_dir.mkdir(exist_ok=True)

    # Track results
    results: dict[str, bool | None] = {}  # None = skipped, True = pass, False = fail

    for version in versions:
        click.echo(f"\n{'=' * 60}")
        click.echo(f"Python {version}")
        click.echo("=" * 60)

        # Build wheel
        if no_build:
            wheel = find_matching_wheel(dist_dir, version, platform_tag)
            if wheel is None:
                click.echo(
                    click.style(
                        f"No wheel found for Python {version}, skipping", fg="yellow"
                    )
                )
                results[version] = None
                continue
            click.echo(f"Using existing wheel: {wheel.name}")
        else:
            click.echo("Building wheel...")
            try:
                wheel = build_wheel(package_dir, version)
                click.echo(f"Built: {wheel.name}")
            except subprocess.CalledProcessError as e:
                click.echo(click.style(f"Build failed: {e}", fg="red"))
                results[version] = False
                continue

        if build_only:
            results[version] = True
            continue

        # Create venv
        venv_dir = wheeltest_dir / version
        click.echo(f"Creating venv at {venv_dir}")
        try:
            python_path = create_venv(venv_dir, version)
        except subprocess.CalledProcessError as e:
            click.echo(
                click.style(
                    f"Failed to create venv (Python {version} may not be available): {e}",
                    fg="red",
                )
            )
            results[version] = None
            continue

        # Install wheel
        click.echo("Installing wheel and pytest...")
        try:
            install_wheel(python_path, wheel)
        except subprocess.CalledProcessError as e:
            click.echo(click.style(f"Install failed: {e}", fg="red"))
            results[version] = False
            continue

        # Run tests
        click.echo("Running tests...")
        passed = run_tests(python_path, tests_dir, pytest_args, workdir=venv_dir)
        results[version] = passed

        if passed:
            click.echo(click.style(f"Python {version}: PASSED", fg="green"))
        else:
            click.echo(click.style(f"Python {version}: FAILED", fg="red"))

    # Summary
    click.echo(f"\n{'=' * 60}")
    click.echo("Summary")
    click.echo("=" * 60)

    passed_versions = [v for v, r in results.items() if r is True]
    failed_versions = [v for v, r in results.items() if r is False]
    skipped_versions = [v for v, r in results.items() if r is None]

    if passed_versions:
        click.echo(click.style(f"Passed:  {', '.join(passed_versions)}", fg="green"))
    if failed_versions:
        click.echo(click.style(f"Failed:  {', '.join(failed_versions)}", fg="red"))
    if skipped_versions:
        click.echo(click.style(f"Skipped: {', '.join(skipped_versions)}", fg="yellow"))

    if failed_versions:
        sys.exit(1)


if __name__ == "__main__":
    main()
