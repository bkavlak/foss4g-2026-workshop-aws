"""The documentation's links.

Checked offline: no URL is fetched, so this stays fast and works on a plane.
What it can prove is that the links are well formed, that internal references
resolve to files that exist, and that a concept is not sent to two different
places in two different documents -- which is how a docs set quietly starts
teaching contradictory things.
"""

import re
from collections import defaultdict
from pathlib import Path

import pytest

DOCS = Path(__file__).resolve().parents[1] / "docs"
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

# Concepts the repository invents. Nothing upstream describes them, so the
# glossary is allowed to leave them unlinked.
LOCAL_TERMS = {
    "Capacity plan",
    "Handout",
    "Roster",
    "Seat",
    "Verifier",
}


def _documents() -> list[Path]:
    return sorted(DOCS.glob("*.md"))


def _links(path: Path) -> list[tuple[str, str]]:
    return LINK.findall(path.read_text(encoding="utf-8"))


@pytest.mark.parametrize("path", _documents(), ids=lambda p: p.name)
def test_internal_links_resolve(path):
    """A cross-reference to a document that does not exist is a dead end."""
    for text, url in _links(path):
        if url.startswith(("http://", "https://", "#")):
            continue
        target = url.partition("#")[0]
        assert (DOCS / target).exists(), (
            f"{path.name}: '{text}' points at {target}, which does not exist"
        )


def _slug(heading: str) -> str:
    """Reproduce the anchor a markdown renderer derives from a heading."""
    text = heading.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    return re.sub(r"[\s_]+", "-", text).strip("-")


def _anchors(path: Path) -> set[str]:
    body = path.read_text(encoding="utf-8")
    return {_slug(h) for h in re.findall(r"^#{1,6}\s+(.*)$", body, re.M)}


@pytest.mark.parametrize("path", _documents(), ids=lambda p: p.name)
def test_anchors_point_at_real_headings(path):
    """A jump link to a section that was renamed lands the reader nowhere."""
    for text, url in _links(path):
        if url.startswith("http"):
            continue
        target, _, anchor = url.partition("#")
        if not anchor:
            continue
        page = path if not target else (DOCS / target).resolve()
        assert anchor in _anchors(page), (
            f"{path.name}: '{text}' jumps to #{anchor}, "
            f"which is not a heading in {page.name}"
        )


@pytest.mark.parametrize("path", _documents(), ids=lambda p: p.name)
def test_external_links_are_well_formed(path):
    """Catches the truncated or wrapped URL that markdown renders as text."""
    for text, url in _links(path):
        if not url.startswith("http"):
            continue
        assert url.startswith("https://"), (
            f"{path.name}: '{text}' uses plain http"
        )
        assert " " not in url and "\n" not in url, (
            f"{path.name}: '{text}' has whitespace in its URL"
        )
        assert not url.endswith(("(", ",", ".")), (
            f"{path.name}: '{text}' looks like it swallowed punctuation"
        )


def test_a_concept_always_points_to_the_same_place():
    """Two documents sending the same term to different docs is a defect."""
    destinations = defaultdict(set)
    for path in _documents():
        for text, url in _links(path):
            if url.startswith("http"):
                destinations[text.strip("`")].add(url)

    conflicting = {
        term: urls for term, urls in destinations.items() if len(urls) > 1
    }
    assert not conflicting, f"terms linked inconsistently: {conflicting}"


def test_every_glossary_term_is_linked_or_local():
    """A glossary entry with no link is only useful if we invented the term."""
    glossary = (DOCS / "glossary.md").read_text(encoding="utf-8")
    unlinked = set(re.findall(r"^\*\*([^*\[]+)\*\* —", glossary, re.M))
    assert unlinked <= LOCAL_TERMS, (
        "glossary terms missing an upstream link: "
        f"{sorted(unlinked - LOCAL_TERMS)}"
    )


def test_the_reading_order_covers_every_document():
    """A document nobody links to will not be found."""
    index = (DOCS / "README.md").read_text(encoding="utf-8")
    linked = {
        url for _, url in LINK.findall(index) if not url.startswith("http")
    }
    for path in _documents():
        if path.name == "README.md":
            continue
        assert path.name in linked, (
            f"{path.name} is not reachable from the index"
        )
