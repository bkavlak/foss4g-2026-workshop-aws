"""Command-line entry point. Argument parsing and printing only."""

from __future__ import annotations

import argparse

from workshop.roster import HANDOUT_FILE, ROSTER_FILE, Roster


def main(argv: list[str] | None = None) -> int:
    """Run the workshop CLI.

    Args:
        argv: Command-line arguments, or None to read them from sys.argv.

    Returns:
        A process exit status.
    """
    parser = argparse.ArgumentParser(prog="workshop", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    provision = commands.add_parser(
        "provision", help="mint participant credentials"
    )
    provision.add_argument("--participants", type=int, required=True)
    provision.add_argument("--directory", default="roster")
    provision.add_argument("--prefix", default="user")

    show = commands.add_parser(
        "show", help="list the usernames in an existing roster"
    )
    show.add_argument("--directory", default="roster")

    args = parser.parse_args(argv)

    if args.command == "provision":
        roster = Roster.provision(
            args.directory, args.participants, args.prefix
        )
        print(f"{len(roster)} accounts written to {args.directory}/")
        print(f"  {ROSTER_FILE}   verifiers, consumed by `tofu apply`")
        print(
            f"  {HANDOUT_FILE}  plaintext passwords, mode 0600 — do not commit"
        )
    else:
        for name in Roster.load(args.directory).usernames:
            print(name)
    return 0
