#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Gate-0: design Base Registry structural check (methodology A-layer).

Fails when any required category is silent, malformed, or points at a missing
``see path`` target. Does not judge specification quality (Gate-1 human slice).
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from typing import Any

REQUIRED_CATEGORIES: tuple[str, ...] = (
    "G.goal",
    "G.actor",
    "G.io",
    "G.behavior",
    "G.data",
    "G.oracle",
    "G.invariant",
    "G.compose",
    "G.env",
    "G.feedback",
    "G.ops",
    "G.open",
)

ALLOWED_STATES = frozenset({"filled", "na", "deferred"})

# Path-like tokens inside filled values (indexes or bare paths).
_PATH_TOKEN_RE = re.compile(
    r"(?P<path>"
    r"(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+/?"  # dir or nested file
    r"|"
    r"[A-Za-z0-9_.-]+\.(?:md|py|yml|yaml|toml|json|txt)"  # extensioned file
    r")"
)

_DEFAULT_REGISTRY = Path("docs/design_base_registry.yaml")


@dataclass
class CheckResult:
    ok: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def extend_errors(self, items: list[str]) -> None:
        self.errors.extend(items)
        if items:
            self.ok = False


def _strip_comment(line: str) -> str:
    in_single = False
    in_double = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            return line[:i].rstrip()
    return line.rstrip()


def _parse_scalar(raw: str) -> Any:
    text = raw.strip()
    if not text:
        return ""
    if (text.startswith('"') and text.endswith('"')) or (
        text.startswith("'") and text.endswith("'")
    ):
        return text[1:-1]
    if text in {"true", "True"}:
        return True
    if text in {"false", "False"}:
        return False
    if text == "{}":
        return {}
    if text == "[]":
        return []
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    return text


def load_simple_yaml_mapping(path: Path) -> dict[str, Any]:
    """Load a restricted YAML mapping (2–3 levels, scalars only).

    Stdlib-only. Sufficient for design_base_registry.yaml; not a general YAML parser.
    """
    root: dict[str, Any] = {}
    stack: list[tuple[int, dict[str, Any]]] = [(-1, root)]

    for lineno, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = _strip_comment(raw_line)
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        if "\t" in line[:indent]:
            raise ValueError(f"{path}:{lineno}: tabs not allowed in indent")
        content = line.strip()
        if content.startswith("-"):
            raise ValueError(f"{path}:{lineno}: lists are not supported in Gate-0 registry")
        if ":" not in content:
            raise ValueError(f"{path}:{lineno}: expected key: value")

        key, _, rest = content.partition(":")
        key = key.strip()
        rest = rest.strip()

        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]

        if rest == "":
            child: dict[str, Any] = {}
            parent[key] = child
            stack.append((indent, child))
        else:
            parent[key] = _parse_scalar(rest)

    return root


_ROOT_FILES = frozenset(
    {
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "LICENSE",
        "pyproject.toml",
        "aci.toml",
        "aci.example.toml",
    }
)

_REPO_PATH_PREFIXES = (
    "docs/",
    "shared/",
    ".github/",
    "domains/",
    "examples/",
    "common/",
    "archive/",
)


def _looks_like_repo_path(token: str) -> bool:
    """Reject slashy prose (N/E/H, install/version) that is not a repo path."""
    if " " in token or ".." in token:
        return False
    if token in _ROOT_FILES:
        return True
    if any(token.startswith(prefix) for prefix in _REPO_PATH_PREFIXES):
        return True
    # Root-level file with a known text/code extension
    if "/" not in token and re.fullmatch(
        r"[A-Za-z0-9_.-]+\.(?:md|py|yml|yaml|toml|json|txt)", token
    ):
        return True
    return False


def extract_paths(value: str) -> list[str]:
    """Extract repository-relative path tokens from a filled value.

    Only tokens in ``see ...`` clauses are checked. Free prose may mention
    path-like words (e.g. "docs/tooling configs") without failing Gate-0.
    """
    if not value or not str(value).strip():
        return []
    text = str(value)
    # Collect spans after each 'see' until next period or end (semicolon-separated ok)
    spans: list[str] = []
    for m in re.finditer(r"\bsee\b\s+", text, flags=re.I):
        start = m.end()
        # stop at sentence end that is not part of a filename
        stop = len(text)
        for i in range(start, len(text)):
            if text[i] == "." and (
                i + 1 >= len(text) or text[i + 1] in " \n\t"
            ):
                stop = i
                break
        spans.append(text[start:stop])
    if not spans:
        return []
    found: list[str] = []
    for span in spans:
        for match in _PATH_TOKEN_RE.finditer(span):
            token = match.group("path").rstrip("/")
            if not _looks_like_repo_path(token):
                continue
            if token not in found:
                found.append(token)
    return found


def _parse_due(due_raw: str) -> date | None:
    text = str(due_raw).strip()
    if not text:
        return None
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    try:
        return date.fromisoformat(text[:10])
    except ValueError:
        return None


def check_registry(
    registry_path: Path,
    repo_root: Path,
    *,
    today: date | None = None,
) -> CheckResult:
    result = CheckResult(ok=True)
    today = today or date.today()

    if not registry_path.is_file():
        result.extend_errors([f"registry file missing: {registry_path}"])
        return result

    try:
        data = load_simple_yaml_mapping(registry_path)
    except ValueError as exc:
        result.extend_errors([f"registry parse error: {exc}"])
        return result

    categories = data.get("categories")
    if not isinstance(categories, dict):
        result.extend_errors(["top-level 'categories' mapping is required"])
        return result

    missing = [c for c in REQUIRED_CATEGORIES if c not in categories]
    if missing:
        result.extend_errors([f"missing required categories: {', '.join(missing)}"])

    extra = sorted(set(categories) - set(REQUIRED_CATEGORIES))
    if extra:
        result.warnings.append(
            "extra categories (allowed, not Gate-0-required): " + ", ".join(extra)
        )

    for cat_id in REQUIRED_CATEGORIES:
        if cat_id not in categories:
            continue
        result.extend_errors(
            check_slot_entry(cat_id, categories[cat_id], repo_root, today=today)
        )

    # Promoted slots (Gate-R): same silence rules once registered.
    promoted = data.get("promoted_slots")
    if promoted is not None:
        if not isinstance(promoted, dict):
            result.extend_errors(["promoted_slots must be a mapping of slot_id -> entry"])
        else:
            for slot_id, entry in promoted.items():
                result.extend_errors(
                    check_slot_entry(
                        f"promoted_slots.{slot_id}", entry, repo_root, today=today
                    )
                )

    return result


def check_slot_entry(
    prefix: str,
    entry: Any,
    repo_root: Path,
    *,
    today: date,
) -> list[str]:
    """Validate one registry slot (category or promoted)."""
    errors: list[str] = []
    if not isinstance(entry, dict):
        return [f"{prefix}: must be a mapping with state/value/reason"]

    state = str(entry.get("state", "")).strip()
    if state not in ALLOWED_STATES:
        return [
            f"{prefix}: state must be one of {sorted(ALLOWED_STATES)}, got {state!r}"
        ]

    if state == "filled":
        value = entry.get("value")
        if value is None or str(value).strip() == "":
            errors.append(f"{prefix}: filled requires non-empty value")
            return errors
        for rel in extract_paths(str(value)):
            target = (repo_root / rel).resolve()
            try:
                target.relative_to(repo_root.resolve())
            except ValueError:
                errors.append(f"{prefix}: path escapes repo root: {rel}")
                continue
            if not target.exists():
                errors.append(f"{prefix}: indexed path does not exist: {rel}")

    elif state == "na":
        reason = entry.get("reason")
        if reason is None or str(reason).strip() == "":
            errors.append(f"{prefix}: na requires non-empty reason")

    elif state == "deferred":
        owner = entry.get("owner")
        due_raw = entry.get("due")
        reason = entry.get("reason") or entry.get("exit")
        if owner is None or str(owner).strip() == "":
            errors.append(f"{prefix}: deferred requires owner")
        if due_raw is None or str(due_raw).strip() == "":
            errors.append(f"{prefix}: deferred requires due (YYYY-MM-DD)")
        else:
            due = _parse_due(str(due_raw))
            if due is None:
                errors.append(
                    f"{prefix}: deferred due is not a parseable date: {due_raw!r}"
                )
            elif due < today:
                errors.append(
                    f"{prefix}: deferred due expired ({due.isoformat()} < {today.isoformat()})"
                )
        if reason is None or str(reason).strip() == "":
            errors.append(
                f"{prefix}: deferred requires reason or exit (unblock condition)"
            )

    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Gate-0 Base Registry structural check (fail on silence / bad index)."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("."),
        help="repository root (default: cwd)",
    )
    parser.add_argument(
        "--registry",
        type=Path,
        default=None,
        help=f"registry path relative to root (default: {_DEFAULT_REGISTRY})",
    )
    parser.add_argument(
        "--as-of",
        type=str,
        default=None,
        help="override 'today' for deferred expiry checks (YYYY-MM-DD)",
    )
    args = parser.parse_args(argv)

    root = args.root.resolve()
    registry = (root / (args.registry or _DEFAULT_REGISTRY)).resolve()
    as_of = date.fromisoformat(args.as_of) if args.as_of else None

    result = check_registry(registry, root, today=as_of)

    for warning in result.warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    if result.ok:
        print(f"Gate-0 PASS: {registry.relative_to(root) if registry.is_relative_to(root) else registry}")
        return 0

    print(f"Gate-0 FAIL: {registry}", file=sys.stderr)
    for err in result.errors:
        print(f"  - {err}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
