"""Tests for wheel_builder module."""

from pathlib import Path

import pytest
from alloconda.wheel_builder import copy_package_tree
from pyfakefs.fake_filesystem import FakeFilesystem


@pytest.fixture
def fs(fs: FakeFilesystem) -> FakeFilesystem:
    """Provide a fake filesystem for tests."""
    return fs


class TestCopyPackageTree:
    """Tests for copy_package_tree function."""

    def test_copies_python_files(self, fs: FakeFilesystem) -> None:
        """Basic Python files are copied."""
        fs.create_file("/src/__init__.py", contents="# init")
        fs.create_file("/src/module.py", contents="# module")

        copy_package_tree(Path("/src"), Path("/dst"), None, None, "_mymod")

        assert Path("/dst/__init__.py").read_text() == "# init"
        assert Path("/dst/module.py").read_text() == "# module"

    def test_copies_nested_files(self, fs: FakeFilesystem) -> None:
        """Nested directory structure is preserved."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/sub/__init__.py")
        fs.create_file("/src/sub/nested.py", contents="nested")

        copy_package_tree(Path("/src"), Path("/dst"), None, None, "_mymod")

        assert Path("/dst/sub/nested.py").read_text() == "nested"

    def test_skips_pycache(self, fs: FakeFilesystem) -> None:
        """__pycache__ directories are not copied."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/__pycache__/module.cpython-314.pyc")

        copy_package_tree(Path("/src"), Path("/dst"), None, None, "_mymod")

        assert not Path("/dst/__pycache__").exists()

    def test_skips_pyc_files(self, fs: FakeFilesystem) -> None:
        """.pyc and .pyo files are not copied."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/module.pyc")
        fs.create_file("/src/module.pyo")

        copy_package_tree(Path("/src"), Path("/dst"), None, None, "_mymod")

        assert not Path("/dst/module.pyc").exists()
        assert not Path("/dst/module.pyo").exists()

    def test_filters_extension_modules_matching_module_name(
        self, fs: FakeFilesystem
    ) -> None:
        """Extension files matching module_name are filtered out."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/_mymod.cpython-314-darwin.so", contents="stale")
        fs.create_file("/src/_mymod.cpython-313-darwin.so", contents="stale")
        fs.create_file("/src/_mymod.cpython-314-x86_64-linux-gnu.so", contents="stale")

        copy_package_tree(Path("/src"), Path("/dst"), None, None, "_mymod")

        assert Path("/dst/__init__.py").exists()
        assert not Path("/dst/_mymod.cpython-314-darwin.so").exists()
        assert not Path("/dst/_mymod.cpython-313-darwin.so").exists()
        assert not Path("/dst/_mymod.cpython-314-x86_64-linux-gnu.so").exists()

    def test_keeps_extension_modules_with_different_name(
        self, fs: FakeFilesystem
    ) -> None:
        """Extension files not matching module_name are kept."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/_mymod.cpython-314-darwin.so", contents="filter me")
        fs.create_file("/src/vendor.so", contents="keep me")
        fs.create_file("/src/_other.cpython-314-darwin.so", contents="keep me too")

        copy_package_tree(Path("/src"), Path("/dst"), None, None, "_mymod")

        assert Path("/dst/vendor.so").exists()
        assert Path("/dst/_other.cpython-314-darwin.so").exists()
        assert not Path("/dst/_mymod.cpython-314-darwin.so").exists()

    def test_filters_dylib_extensions(self, fs: FakeFilesystem) -> None:
        """.dylib files matching module_name are filtered."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/_mymod.dylib", contents="stale")

        copy_package_tree(Path("/src"), Path("/dst"), None, None, "_mymod")

        assert not Path("/dst/_mymod.dylib").exists()

    def test_filters_pyd_extensions(self, fs: FakeFilesystem) -> None:
        """.pyd files matching module_name are filtered."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/_mymod.pyd", contents="stale")

        copy_package_tree(Path("/src"), Path("/dst"), None, None, "_mymod")

        assert not Path("/dst/_mymod.pyd").exists()

    def test_include_pattern(self, fs: FakeFilesystem) -> None:
        """Only files matching include pattern are copied."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/module.py")
        fs.create_file("/src/types.pyi")

        copy_package_tree(Path("/src"), Path("/dst"), ["*.pyi"], None, "_mymod")

        assert Path("/dst/types.pyi").exists()
        assert not Path("/dst/__init__.py").exists()
        assert not Path("/dst/module.py").exists()

    def test_exclude_pattern(self, fs: FakeFilesystem) -> None:
        """Files matching exclude pattern are not copied."""
        fs.create_file("/src/__init__.py")
        fs.create_file("/src/module.py")
        fs.create_file("/src/tests/test_module.py")

        copy_package_tree(Path("/src"), Path("/dst"), None, ["tests/*"], "_mymod")

        assert Path("/dst/__init__.py").exists()
        assert Path("/dst/module.py").exists()
        assert not Path("/dst/tests").exists()
