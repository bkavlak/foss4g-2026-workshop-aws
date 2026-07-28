#!/usr/bin/env bash
# Report every missing tool at once, with the command that installs it.
#
# A bare `command not found` from make names one tool, in a message that does
# not say where the tool comes from -- so a fresh clone costs one failed run
# per missing tool. This reports the whole set, once, with the fix.
#
#   scripts/preflight.sh tofu helm   # check only what this target needs
#   scripts/preflight.sh             # check everything
set -uo pipefail

ALL=(tofu helm kubectl aws uv docker)
WANTED=("${@:-}")
[ -z "${1:-}" ] && WANTED=("${ALL[@]}")

hint() {
  case "$1" in
    docker) echo "install Docker Desktop -> https://docs.docker.com/get-started/get-docker/" ;;
    aws)    echo "run 'make setup', or install the AWS CLI directly" ;;
    *)      echo "run 'make setup'" ;;
  esac
}

missing=()
for tool in "${WANTED[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  ok       %s\n' "$tool"
  else
    printf '  MISSING  %-9s %s\n' "$tool" "$(hint "$tool")"
    missing+=("$tool")
  fi
done

[ ${#missing[@]} -eq 0 ] && exit 0

echo
echo "Missing: ${missing[*]}"

if ! command -v asdf >/dev/null 2>&1; then
  cat <<'ASDF'

asdf is not installed. It is what installs every tool above except Docker.

  macOS:  brew install asdf
  other:  https://asdf-vm.com/guide/getting-started.html

Then add it to your shell (the asdf docs show the exact line for your shell),
open a new terminal, and run:

  make setup
ASDF
else
  cat <<'SETUP'

asdf is installed but these tools are not. Run:

  make setup

If that has already been run and the tools are still missing, your shell may
not have asdf's shims on PATH yet -- open a new terminal and try again.
SETUP
fi

exit 1
