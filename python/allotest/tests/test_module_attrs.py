"""Tests for module-level attributes."""

import math

import allotest


class TestModuleAttributes:
    def test_version(self) -> None:
        assert allotest.VERSION == "0.1.0"

    def test_default_size(self) -> None:
        assert allotest.DEFAULT_SIZE == 256

    def test_enabled(self) -> None:
        assert allotest.ENABLED is True

    def test_optional(self) -> None:
        assert allotest.OPTIONAL is None

    def test_pi(self) -> None:
        assert math.isclose(allotest.PI, 3.14159)
