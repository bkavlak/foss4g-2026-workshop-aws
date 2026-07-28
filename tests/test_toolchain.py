"""The setup path.

A fresh clone runs `make setup` once and everything else depends on it having
worked. These checks guard the two ways it silently stops working: the pinned
tool list and the asdf plugin list drifting apart, and the preflight script
losing its executable bit in a way nobody notices until a colleague clones.
"""

import re
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL_VERSIONS = ROOT / ".tool-versions"
MAKEFILE = ROOT / "Makefile"
PREFLIGHT = ROOT / "scripts" / "preflight.sh"


def _pinned_tools() -> set[str]:
    lines = TOOL_VERSIONS.read_text(encoding="utf-8").splitlines()
    return {
        line.split()[0]
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    }


def _declared_plugins() -> set[str]:
    body = MAKEFILE.read_text(encoding="utf-8")
    match = re.search(r"^ASDF_PLUGINS\s*:=\s*(.*)$", body, re.M)
    assert match, "Makefile no longer declares ASDF_PLUGINS"
    return set(match.group(1).split())


def test_every_pinned_tool_has_a_plugin_to_install_it():
    """`asdf install` is a silent no-op for a tool whose plugin is not added.

    A version pinned in .tool-versions but missing from ASDF_PLUGINS means
    `make setup` reports success and installs nothing.
    """
    missing = _pinned_tools() - _declared_plugins()
    assert not missing, f"pinned but never installed: {sorted(missing)}"


def test_no_plugin_is_installed_without_a_pinned_version():
    """An unpinned plugin would install whatever is newest that day."""
    extra = _declared_plugins() - _pinned_tools()
    assert not extra, f"plugin added but no version pinned: {sorted(extra)}"


def test_preflight_is_executable():
    """The Makefile runs it as ./scripts/preflight.sh."""
    mode = PREFLIGHT.stat().st_mode
    assert mode & stat.S_IXUSR, f"{PREFLIGHT.name} has lost its executable bit"


def test_preflight_covers_every_tool_the_makefile_gates_on():
    """A target may only demand a tool the script knows how to advise on."""
    body = MAKEFILE.read_text(encoding="utf-8")
    demanded = {
        tool
        for line in re.findall(r"\$\(PREFLIGHT\)(.*)$", body, re.M)
        for tool in line.split()
    }
    declared = re.search(
        r"^ALL=\((.*)\)$", PREFLIGHT.read_text(encoding="utf-8"), re.M
    )
    assert declared, "preflight.sh no longer declares an ALL list"
    known = set(declared.group(1).split())
    assert demanded <= known, (
        f"preflight cannot advise on: {sorted(demanded - known)}"
    )
