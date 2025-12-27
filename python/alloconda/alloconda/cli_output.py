"""Styled console output utilities for alloconda CLI."""

from __future__ import annotations

import contextlib
import os
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import click

# Verbosity level (module-level state)
_verbose: bool = False
_quiet: bool = False


def set_verbose(enabled: bool) -> None:
    """Enable or disable verbose output globally."""
    global _verbose
    _verbose = enabled


def is_verbose() -> bool:
    """Check if verbose mode is enabled."""
    return _verbose


def set_quiet(enabled: bool) -> None:
    """Enable or disable quiet mode (suppresses non-critical output)."""
    global _quiet
    _quiet = enabled


def is_quiet() -> bool:
    """Check if quiet mode is enabled."""
    return _quiet


def supports_color() -> bool:
    """Check if the terminal supports color output."""
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR"):
        return True
    return sys.stdout.isatty()


# Symbols (with fallbacks for non-nerd-font terminals)
SUCCESS = "✓"
ERROR = "✗"
WARNING = "⚠"
INFO = "ℹ"
ARROW = "→"
ELLIPSIS = "⋯"
BULLET = "▸"


def _style(text: str, fg: str | None = None, bold: bool = False, dim: bool = False) -> str:
    """Apply color styling if supported."""
    if not supports_color():
        return text
    return click.style(text, fg=fg, bold=bold, dim=dim)


def success(message: str, **kwargs: Any) -> None:
    """Print a success message."""
    styled = f"{_style(SUCCESS, 'green', bold=True)} {message}"
    click.echo(styled, **kwargs)


def error(message: str, **kwargs: Any) -> None:
    """Print an error message."""
    styled = f"{_style(ERROR, 'red', bold=True)} {_style(message, 'red')}"
    click.echo(styled, err=True, **kwargs)


def warning(message: str, **kwargs: Any) -> None:
    """Print a warning message."""
    styled = f"{_style(WARNING, 'yellow', bold=True)} {_style(message, 'yellow')}"
    click.echo(styled, **kwargs)


def info(message: str, **kwargs: Any) -> None:
    """Print an informational message."""
    styled = f"{_style(INFO, 'blue')} {message}"
    click.echo(styled, **kwargs)


def step(message: str, **kwargs: Any) -> None:
    """Print a step/action message."""
    if _quiet:
        return
    styled = f"{_style(ARROW, 'cyan')} {message}"
    click.echo(styled, **kwargs)


def bullet(message: str, indent: int = 0, **kwargs: Any) -> None:
    """Print a bullet point message."""
    prefix = "  " * indent
    styled = f"{prefix}{_style(BULLET, 'cyan', dim=True)} {message}"
    click.echo(styled, **kwargs)


def verbose(message: str, **kwargs: Any) -> None:
    """Print a verbose debug message (only if verbose mode is enabled)."""
    if not _verbose:
        return
    styled = f"{_style('[verbose]', 'cyan', dim=True)} {_style(message, dim=True)}"
    click.echo(styled, **kwargs)


def verbose_cmd(cmd: list[str] | str, **kwargs: Any) -> None:
    """Print a command being executed (only in verbose mode)."""
    if not _verbose:
        return
    if isinstance(cmd, list):
        cmd_str = " ".join(cmd)
    else:
        cmd_str = cmd
    styled = f"{_style('[cmd]', 'cyan', dim=True)} {_style(cmd_str, dim=True)}"
    click.echo(styled, **kwargs)


def verbose_detail(key: str, value: Any, **kwargs: Any) -> None:
    """Print a key-value detail (only in verbose mode)."""
    if not _verbose:
        return
    styled = f"  {_style(key + ':', 'cyan', dim=True)} {_style(str(value), dim=True)}"
    click.echo(styled, **kwargs)


def section(title: str, **kwargs: Any) -> None:
    """Print a section header."""
    if _verbose:
        styled = f"\n{_style('═' * 60, 'cyan', dim=True)}\n{_style(title, 'cyan', bold=True)}\n{_style('─' * 60, 'cyan', dim=True)}"
    else:
        styled = f"\n{_style(title, 'cyan', bold=True)}"
    click.echo(styled, **kwargs)


def plain(message: str, **kwargs: Any) -> None:
    """Print a plain message without any styling."""
    click.echo(message, **kwargs)


def dim(message: str, **kwargs: Any) -> None:
    """Print a dimmed secondary message."""
    if _quiet:
        return
    styled = _style(message, dim=True)
    click.echo(styled, **kwargs)


def path_style(path: Path | str) -> str:
    """Style a file path for display."""
    path_str = str(path)
    if supports_color():
        return _style(path_str, "yellow")
    return path_str


def key_value(key: str, value: Any, **kwargs: Any) -> None:
    """Print a key-value pair."""
    styled = f"{_style(key + ':', 'cyan')} {value}"
    click.echo(styled, **kwargs)


@contextlib.contextmanager
def verbose_section(title: str) -> Iterator[None]:
    """Context manager for a verbose section with timing."""
    if not _verbose:
        yield
        return

    import time

    styled = f"\n{_style('┌─', 'cyan', dim=True)} {_style(title, 'cyan', bold=True)}"
    click.echo(styled)
    start = time.time()
    try:
        yield
    finally:
        elapsed = time.time() - start
        styled = f"{_style('└─', 'cyan', dim=True)} {_style(f'completed in {elapsed:.2f}s', 'cyan', dim=True)}"
        click.echo(styled)


class ProgressBar:
    """Simple progress indicator for operations."""

    def __init__(self, total: int, desc: str = ""):
        self.total = total
        self.current = 0
        self.desc = desc
        self._started = False

    def update(self, n: int = 1) -> None:
        """Update progress by n steps."""
        self.current += n
        if _verbose or sys.stdout.isatty():
            self._render()

    def _render(self) -> None:
        """Render the progress bar."""
        if not self._started:
            self._started = True
        if self.total > 0:
            pct = int((self.current / self.total) * 100)
            bar_width = 30
            filled = int((self.current / self.total) * bar_width)
            bar = "█" * filled + "░" * (bar_width - filled)
            msg = f"\r{self.desc} [{bar}] {pct}% ({self.current}/{self.total})"
        else:
            msg = f"\r{self.desc} {ELLIPSIS} {self.current}"

        if supports_color():
            msg = _style(msg, "cyan")
        click.echo(msg, nl=False)

    def finish(self) -> None:
        """Complete the progress bar."""
        if self._started:
            click.echo()  # New line after progress bar


class LiveStatus:
    """Context manager for ephemeral status updates that overwrite previous output."""

    def __init__(self, total: int, desc: str = "Building"):
        self.total = total
        self.current = 0
        self.desc = desc
        self._status_lines = 0
        self._is_tty = sys.stdout.isatty()
        self._use_live = self._is_tty and not _verbose
        self._progress_bar = ProgressBar(total, desc)

    def __enter__(self) -> "LiveStatus":
        if self._use_live:
            self._progress_bar._render()
            # Enable quiet mode to suppress intermediate output
            set_quiet(True)
        return self

    def __exit__(self, *args: object) -> None:
        # Disable quiet mode
        set_quiet(False)
        self._clear_status()
        self._progress_bar.finish()

    def update(self, status_lines: list[str]) -> None:
        """Update the live status with new lines, overwriting previous ones."""
        if not self._use_live:
            # If not in live mode (verbose or not TTY), just print normally
            for line in status_lines:
                click.echo(line)
            return

        # Clear previous status lines
        self._clear_status()

        # Render progress bar
        self._progress_bar._render()
        click.echo()  # Newline after progress bar

        # Print new status lines
        for line in status_lines:
            click.echo(line)

        self._status_lines = len(status_lines)

    def increment(self, status_lines: list[str]) -> None:
        """Increment progress and update status."""
        self.current += 1
        self._progress_bar.update(1)
        self.update(status_lines)

    def persist(self, message: str) -> None:
        """Print a persistent message and increment progress."""
        if not self._use_live:
            # In non-live mode, just print and we're done
            click.echo(message)
            self.current += 1
            return

        # Clear ephemeral status
        self._clear_status()

        # Temporarily disable quiet mode to print persistent message
        set_quiet(False)
        click.echo(message)
        set_quiet(True)

        # Update progress
        self.current += 1
        self._progress_bar.update(1)

        # Reset status lines counter after persisting
        self._status_lines = 0

    def _clear_status(self) -> None:
        """Clear the current status lines."""
        if not self._use_live or self._status_lines == 0:
            return

        # Move cursor up and clear lines
        for _ in range(self._status_lines + 1):  # +1 for the newline after progress
            click.echo("\x1b[1A\x1b[2K", nl=False)  # Move up, clear line


def print_build_summary(
    items: list[tuple[str, str]],
    title: str = "Build Configuration",
) -> None:
    """Print a formatted build configuration summary."""
    if not items:
        return

    section(title)
    max_key_len = max(len(k) for k, _ in items)
    for key, value in items:
        padded_key = key.ljust(max_key_len)
        styled = f"  {_style(padded_key, 'cyan')}: {value}"
        click.echo(styled)


def print_matrix(
    rows: list[list[str]],
    headers: list[str] | None = None,
) -> None:
    """Print a formatted matrix/table."""
    if not rows:
        return

    all_rows = [headers] + rows if headers else rows
    col_widths = [max(len(str(row[i])) for row in all_rows) for i in range(len(all_rows[0]))]

    if headers:
        # Print headers
        header_row = "  ".join(
            _style(str(headers[i]).ljust(col_widths[i]), "cyan", bold=True)
            for i in range(len(headers))
        )
        click.echo(header_row)
        click.echo(_style("─" * sum(col_widths) + "─" * (len(headers) - 1) * 2, dim=True))

    # Print data rows
    for row in rows:
        styled_row = "  ".join(str(row[i]).ljust(col_widths[i]) for i in range(len(row)))
        click.echo(styled_row)
