"""Shared fixtures.

Nothing in this suite reaches AWS, Kubernetes or the network. The two things
that would normally need a live system are substituted: the JupyterHub runtime
by a stub module, and a deployed release by a local `helm template` render.
"""

# A pytest fixture is referenced by a parameter of the same name, which Pylint
# reads as shadowing, and a fixture requested purely for its side effect looks
# unused. Both are the idiom, not a defect.
# pylint: disable=redefined-outer-name,unused-argument

from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import types
from pathlib import Path
from typing import Any

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
CHART_DIR = REPO_ROOT / "charts" / "workshop"


@pytest.fixture
def hub_runtime(monkeypatch):
    """Stand in for the JupyterHub package inside the hub image.

    The authenticator imports `jupyterhub.auth.Authenticator` at module level.
    A stub lets the suite exercise the real shipped file without depending on
    JupyterHub, which is deliberately absent from this project's environment.
    """

    class Authenticator:
        log = types.SimpleNamespace(exception=lambda *a, **k: None)

    auth_module = types.ModuleType("jupyterhub.auth")
    auth_module.Authenticator = Authenticator  # type: ignore[attr-defined]
    package = types.ModuleType("jupyterhub")
    package.auth = auth_module  # type: ignore[attr-defined]

    monkeypatch.setitem(sys.modules, "jupyterhub", package)
    monkeypatch.setitem(sys.modules, "jupyterhub.auth", auth_module)
    return Authenticator


@pytest.fixture
def authenticator(hub_runtime):
    """The authenticator exactly as the chart ships it to the hub."""
    path = CHART_DIR / "files" / "roster_authenticator.py"
    spec = importlib.util.spec_from_file_location("roster_authenticator", path)
    assert spec is not None and spec.loader is not None, (
        f"cannot load the chart's authenticator from {path}"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def render_chart():
    """Render this chart's templates locally. No cluster is contacted."""
    helm = shutil.which("helm")
    if helm is None:
        pytest.skip("helm is not installed; run `make setup`")
    if not list(CHART_DIR.glob("charts/jupyterhub-*.tgz")):
        pytest.skip(
            "chart dependencies not vendored; run"
            " `helm dependency build charts/workshop`"
        )

    def _render(values_yaml: str, template: str) -> dict[str, Any]:
        # Values go in over stdin so a test run leaves nothing behind in the
        # chart directory.
        result = subprocess.run(
            [
                helm,
                "template",
                "workshop",
                str(CHART_DIR),
                "--namespace",
                "workshop",
                "--values",
                "-",
                "--show-only",
                template,
            ],
            input=values_yaml,
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr
        rendered = yaml.safe_load(result.stdout)
        assert isinstance(rendered, dict), (
            f"expected {template} to render exactly one object"
        )
        return rendered

    return _render
