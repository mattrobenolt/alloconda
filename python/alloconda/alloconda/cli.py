import click

from . import __version__
from .cli_build import build
from .cli_develop import develop
from .cli_init import init
from .cli_inspect import inspect, inspect_lib
from .cli_python import python
from .cli_wheel import wheel
from .cli_wheel_all import wheel_all


@click.group()
@click.version_option(__version__, prog_name="alloconda")
def main() -> None:
    """\b
      ▜ ▜          ▌
    ▀▌▐ ▐ ▛▌▛▘▛▌▛▌▛▌▀▌
    █▌▐▖▐▖▙▌▙▖▙▌▌▌▙▌█▌

    Alloconda CLI for Zig-based Python extensions.
    """
    pass


main.add_command(build)
main.add_command(develop)
main.add_command(init)
main.add_command(inspect)
main.add_command(inspect_lib)
main.add_command(python)
main.add_command(wheel)
main.add_command(wheel_all)


if __name__ == "__main__":
    main()
