#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Design methodology ops check.

Implements mechanical slices for Gate-0..3 and Gate-R, plus Seams + Residual.

PASS is not zero defects. Also distinguishes:
- format/gate structure
- substance (rejects bootstrap stub registries)

Canonical methodology docs live in:
  common/pj-design_metho/design_methodology_seams.md
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from datetime import date
from pathlib import Path
from typing import Any

_TOOLS = Path(__file__).resolve().parent
_GATE0_PATH = _TOOLS / "gate0_registry_check.py"


def _load_gate0():
    spec = importlib.util.spec_from_file_location("gate0_registry_check", _GATE0_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


gate0 = _load_gate0()

DEFAULT_REGISTRY = Path("docs/design_base_registry.yaml")
DEFAULT_SEAMS = Path("docs/design_seam_review.yaml")
DEFAULT_RESIDUALS = Path("docs/design_residuals.yaml")
DEFAULT_GATE_R = Path("docs/design_gate_r_log.yaml")

REQUIRED_SEAMS = ("S1", "S2", "S3", "S4", "S5")
# Defined in design_methodology_seams.md (Seam review status vocabulary).
SEAM_STATUSES = frozenset(
    {"open", "mitigated", "residual", "na", "monitored", "accepted"}
)

_ORACLE_MACHINE = re.compile(
    r"\b(machine|mechanized|auto(?:mated)?|native|external-analyzer|test|ci)\b",
    re.I,
)
_ORACLE_HUMAN = re.compile(
    r"\b(human|manual|sign-?off|review-required|judgment|owner)\b",
    re.I,
)
_MONITOR = re.compile(
    r"\b(monitor|canary|alert|metric|rum|observ|watch|threshold|sla|slo)\b",
    re.I,
)
_AMPLIFY = re.compile(
    r"\b(amplif|self-?train|retrain|feedback loop|endogenous|online learn)\b",
    re.I,
)

# Phrases emitted by bootstrap_project.write_artifacts — not project substance.
_BOOTSTRAP_PHRASES = (
    "design truth owners must not be silently duplicated",
    "machine checks where tests/ci exist; human judgment for design quality and product sign-off",
    "composition of modules/docs is project-specific; interaction range is not claimed exhaustive",
    "runtime and dependency assumptions live in project docs and tooling configs where present",
    "unknown slots remain until gate-r promotion",
    "operators and implementers of this repository; see authority docs if present",
    "bootstrap_stub",
)


def _has_test_surface(repo_root: Path) -> bool:
    if (repo_root / "shared" / "tests").is_dir():
        return True
    if (repo_root / "tests").is_dir():
        return True
    for p in repo_root.rglob("test_*.py"):
        # skip vendor/node_modules
        parts = set(p.parts)
        if parts & {"node_modules", ".venv", "venv", "site-packages", "__pycache__"}:
            continue
        return True
    for p in repo_root.rglob("*_test.py"):
        parts = set(p.parts)
        if parts & {"node_modules", ".venv", "venv", "site-packages", "__pycache__"}:
            continue
        return True
    return False


def _has_ci_surface(repo_root: Path) -> bool:
    wf = repo_root / ".github" / "workflows"
    if not wf.is_dir():
        return False
    return any(wf.glob("*.yml")) or any(wf.glob("*.yaml"))


def check_bootstrap_substance(registry_data: dict[str, Any]) -> list[str]:
    """Fail substance when registry is still a bootstrap stub."""
    errors: list[str] = []
    meta = registry_data.get("meta")
    if isinstance(meta, dict):
        if meta.get("bootstrap") not in (None, "", False, "false", "False"):
            errors.append(
                "Substance: meta.bootstrap is set — registry is a bootstrap stub, "
                "not project-specific substance (remove bootstrap and rewrite slots)"
            )
        if str(meta.get("quality", "")).strip().lower() == "format-only":
            errors.append(
                "Substance: meta.quality=format-only — not substance-pass"
            )

    categories = registry_data.get("categories")
    if not isinstance(categories, dict):
        return errors

    hits = 0
    for cat_id, entry in categories.items():
        if not isinstance(entry, dict):
            continue
        blob = " ".join(
            str(entry.get(k, "")) for k in ("value", "evidence", "reason")
        ).lower()
        for phrase in _BOOTSTRAP_PHRASES:
            if phrase in blob:
                hits += 1
                break
    if hits >= 3:
        errors.append(
            f"Substance: {hits} categories still use bootstrap generic wording "
            "(rewrite with project-specific design content)"
        )
    return errors


def check_gate1(registry_data: dict[str, Any], repo_root: Path) -> list[str]:
    errors: list[str] = []
    categories = registry_data.get("categories")
    if not isinstance(categories, dict):
        return ["Gate-1: categories missing"]

    for cat_id, entry in categories.items():
        if not isinstance(entry, dict):
            continue
        state = str(entry.get("state", "")).strip()
        if state != "filled":
            continue
        evidence = entry.get("evidence")
        if evidence is None or str(evidence).strip() == "":
            errors.append(f"Gate-1 {cat_id}: filled requires non-empty evidence")
        else:
            for rel in gate0.extract_paths(str(evidence)):
                target = (repo_root / rel).resolve()
                if target.exists():
                    continue
                errors.append(f"Gate-1 {cat_id}: evidence path missing: {rel}")

    oracle = categories.get("G.oracle")
    if isinstance(oracle, dict) and str(oracle.get("state", "")).strip() == "filled":
        value = str(oracle.get("value", ""))
        has_m = bool(_ORACLE_MACHINE.search(value))
        has_h = bool(_ORACLE_HUMAN.search(value))
        if not (has_m or has_h):
            errors.append(
                "Gate-1 G.oracle: value must mention machine and/or human judgment assignment"
            )
        elif has_m and not has_h:
            if not re.search(
                r"only\s+machine|machine\s+only|no human|all[- ]machine", value, re.I
            ):
                errors.append(
                    "Gate-1 G.oracle: name human-judgment path or state machine-only explicitly"
                )
        elif has_h and not has_m:
            if not re.search(
                r"\ball[- ]human\b|human\s+only|only\s+human", value, re.I
            ):
                errors.append(
                    "Gate-1 G.oracle: name machine path or state human-only explicitly"
                )

    for need in ("G.invariant", "G.compose"):
        entry = categories.get(need)
        if not isinstance(entry, dict):
            errors.append(f"Gate-1 {need}: missing")
            continue
        if str(entry.get("state", "")).strip() != "filled":
            continue
        if not str(entry.get("value", "")).strip():
            errors.append(f"Gate-1 {need}: filled value empty")

    return errors


def check_gate2(registry_data: dict[str, Any], repo_root: Path) -> list[str]:
    """Gate-2: merge-ready verification surface for invariant/compose/env.

    Mechanical slice only:
    - G.invariant / G.compose / G.env are present and not silent keys
    - repo has tests and/or CI workflows, OR each filled slot declares verification:
    """
    errors: list[str] = []
    categories = registry_data.get("categories")
    if not isinstance(categories, dict):
        return ["Gate-2: categories missing"]

    for cat in ("G.invariant", "G.compose", "G.env"):
        entry = categories.get(cat)
        if not isinstance(entry, dict):
            errors.append(f"Gate-2 {cat}: missing (required for merge gate)")
            continue
        state = str(entry.get("state", "")).strip()
        if state not in gate0.ALLOWED_STATES:
            errors.append(f"Gate-2 {cat}: invalid state {state!r}")

    has_tests = _has_test_surface(repo_root)
    has_ci = _has_ci_surface(repo_root)
    surface_ok = has_tests or has_ci

    # Per-slot explicit verification override when no global surface
    explicit = 0
    for cat in ("G.invariant", "G.compose"):
        entry = categories.get(cat)
        if not isinstance(entry, dict):
            continue
        if str(entry.get("state", "")).strip() != "filled":
            continue
        ver = entry.get("verification") or entry.get("verification_means")
        if ver is not None and str(ver).strip() != "":
            explicit += 1

    if not surface_ok and explicit < 2:
        errors.append(
            "Gate-2: no test surface (tests/ or test_*.py) and no CI workflows "
            "(.github/workflows), and G.invariant/G.compose lack verification: fields"
        )

    # G.env must be artifacted (filled with value, or na/deferred with reason)
    env = categories.get("G.env")
    if isinstance(env, dict) and str(env.get("state", "")).strip() == "filled":
        if not str(env.get("value", "")).strip():
            errors.append("Gate-2 G.env: filled requires value (env contract artifact)")

    return errors


def check_gate3(registry_data: dict[str, Any], repo_root: Path, *, today: date) -> list[str]:
    """Gate-3: release readiness mechanical slice.

    - no expired deferred (also Gate-0)
    - G.env / G.feedback / G.ops present
    - if feedback is amplifying, require monitoring language
    """
    errors: list[str] = []
    categories = registry_data.get("categories")
    if not isinstance(categories, dict):
        return ["Gate-3: categories missing"]

    for cat in ("G.env", "G.feedback", "G.ops"):
        entry = categories.get(cat)
        if not isinstance(entry, dict):
            errors.append(f"Gate-3 {cat}: missing")
            continue
        state = str(entry.get("state", "")).strip()
        if state not in gate0.ALLOWED_STATES:
            errors.append(f"Gate-3 {cat}: invalid state {state!r}")
        if state == "deferred":
            due = gate0._parse_due(str(entry.get("due", "")))
            if due is not None and due < today:
                errors.append(f"Gate-3 {cat}: deferred due expired ({due.isoformat()})")

    fb = categories.get("G.feedback")
    if isinstance(fb, dict) and str(fb.get("state", "")).strip() == "filled":
        value = str(fb.get("value", ""))
        if not value.strip():
            errors.append("Gate-3 G.feedback: filled value empty")
        else:
            # Affirmed amplifying loop (not "none" / "no … amplifying") requires monitoring.
            negated = re.search(
                r"\b(none|no|without|not)\b.{0,60}\b(amplif|endogenous|self-?train|retrain|feedback)",
                value,
                re.I,
            )
            if (
                not negated
                and _AMPLIFY.search(value)
                and not _MONITOR.search(value)
            ):
                errors.append(
                    "Gate-3 G.feedback: amplifying/feedback loop declared but no "
                    "monitoring/canary/metric language"
                )

    # promoted deferred slots also must not be expired (gate0 covers; double-check promoted)
    promoted = registry_data.get("promoted_slots")
    if isinstance(promoted, dict):
        for sid, entry in promoted.items():
            if not isinstance(entry, dict):
                continue
            if str(entry.get("state", "")).strip() != "deferred":
                continue
            due = gate0._parse_due(str(entry.get("due", "")))
            if due is not None and due < today:
                errors.append(
                    f"Gate-3 promoted_slots.{sid}: deferred due expired ({due.isoformat()})"
                )

    return errors


def check_seams(seams_path: Path) -> list[str]:
    errors: list[str] = []
    if not seams_path.is_file():
        return [f"Seams: missing review artifact {seams_path}"]
    try:
        data = gate0.load_simple_yaml_mapping(seams_path)
    except ValueError as exc:
        return [f"Seams: parse error: {exc}"]

    seams = data.get("seams")
    if not isinstance(seams, dict):
        return ["Seams: top-level 'seams' mapping required"]

    for sid in REQUIRED_SEAMS:
        if sid not in seams:
            errors.append(f"Seams: missing {sid}")
            continue
        entry = seams[sid]
        if not isinstance(entry, dict):
            errors.append(f"Seams {sid}: must be a mapping")
            continue
        status = str(entry.get("status", "")).strip().lower()
        if status not in SEAM_STATUSES:
            errors.append(
                f"Seams {sid}: status must be one of {sorted(SEAM_STATUSES)}, got {status!r}"
            )
        note = entry.get("note") or entry.get("evidence")
        if note is None or str(note).strip() == "":
            errors.append(f"Seams {sid}: note (or evidence) required")

    return errors


def check_residuals(residuals_path: Path, repo_root: Path) -> list[str]:
    errors: list[str] = []
    if not residuals_path.is_file():
        return [f"Residual: missing {residuals_path}"]
    try:
        data = gate0.load_simple_yaml_mapping(residuals_path)
    except ValueError as exc:
        return [f"Residual: parse error: {exc}"]

    statement = data.get("statement")
    if statement is None or str(statement).strip() == "":
        errors.append("Residual: statement required (honest bound on completeness)")

    claimed = data.get("claimed_complete")
    if claimed is True or str(claimed).strip().lower() in {"true", "yes", "1"}:
        errors.append(
            "Residual: claimed_complete must not be true "
            "(methodology forbids claiming zero-defect completeness)"
        )
    if claimed is None and "claimed_complete" not in data:
        errors.append("Residual: claimed_complete field required (must be false)")

    see = data.get("see") or data.get("evidence")
    if see is None or str(see).strip() == "":
        errors.append("Residual: see/evidence path required")
    else:
        raw = str(see).strip()
        paths = gate0.extract_paths(
            raw if re.search(r"\bsee\b", raw, re.I) else f"see {raw}"
        )
        if not paths:
            segments = [s.strip() for s in raw.replace("see ", "").split(";") if s.strip()]
            ok_any = False
            for seg in segments:
                token = seg.split()[0].strip()
                if (repo_root / token).exists():
                    ok_any = True
                    break
            if not ok_any:
                errors.append(f"Residual: cannot resolve any evidence path in {raw!r}")
        else:
            for rel in paths:
                if not (repo_root / rel).exists():
                    errors.append(f"Residual: path missing: {rel}")

    return errors


def check_gate_r(
    gate_r_path: Path,
    registry_data: dict[str, Any],
) -> list[str]:
    errors: list[str] = []
    if not gate_r_path.is_file():
        return [
            f"Gate-R: missing log {gate_r_path} "
            "(create with entries: {{}} if no recirculations yet)"
        ]

    try:
        data = gate0.load_simple_yaml_mapping(gate_r_path)
    except ValueError as exc:
        return [f"Gate-R: parse error: {exc}"]

    entries = data.get("entries")
    if entries is None:
        return ["Gate-R: top-level 'entries' mapping required (may be empty {})"]
    if not isinstance(entries, dict):
        return ["Gate-R: entries must be a mapping id -> record"]

    promoted = registry_data.get("promoted_slots")
    if promoted is not None and not isinstance(promoted, dict):
        errors.append("Gate-R: registry promoted_slots must be a mapping")
        promoted = {}
    elif promoted is None:
        promoted = {}

    for eid, rec in entries.items():
        prefix = f"Gate-R {eid}"
        if not isinstance(rec, dict):
            errors.append(f"{prefix}: must be a mapping")
            continue
        status = str(rec.get("status", "")).strip().lower()
        if status not in {"open", "closed"}:
            errors.append(f"{prefix}: status must be open|closed")
            continue

        for req in ("summary", "seams", "basic"):
            if rec.get(req) is None or str(rec.get(req)).strip() == "":
                errors.append(f"{prefix}: field '{req}' required")

        basic_raw = str(rec.get("basic", "")).strip().lower()
        if basic_raw not in {"yes", "no", "true", "false"}:
            errors.append(f"{prefix}: basic must be yes|no")

        if status != "closed":
            continue

        if basic_raw in {"yes", "true"}:
            slot_id = rec.get("promoted_slot")
            if slot_id is None or str(slot_id).strip() == "":
                errors.append(
                    f"{prefix}: closed+basic requires promoted_slot id in registry"
                )
            else:
                sid = str(slot_id).strip()
                if sid not in promoted:
                    errors.append(
                        f"{prefix}: promoted_slot {sid!r} not in registry.promoted_slots"
                    )
            example = rec.get("fill_example")
            if example is None or str(example).strip() == "":
                errors.append(f"{prefix}: closed+basic requires fill_example")
        else:
            if rec.get("not_basic_reason") is None or str(
                rec.get("not_basic_reason")
            ).strip() == "":
                errors.append(
                    f"{prefix}: closed+not-basic requires not_basic_reason"
                )

    return errors


def run_all(
    root: Path,
    *,
    registry_rel: Path = DEFAULT_REGISTRY,
    seams_rel: Path = DEFAULT_SEAMS,
    residuals_rel: Path = DEFAULT_RESIDUALS,
    gate_r_rel: Path = DEFAULT_GATE_R,
    today: date | None = None,
    require_substance: bool = False,
) -> tuple[bool, list[str], list[str]]:
    """Return (ok, errors, notes).

    Default ok = format/gates only. Substance (bootstrap/project-specific wording)
    is optional via require_substance=True — project-owned, not methodology CI.
    """
    today = today or date.today()
    errors: list[str] = []
    notes: list[str] = []

    registry_path = root / registry_rel
    g0 = gate0.check_registry(registry_path, root, today=today)
    if not g0.ok:
        errors.extend([f"Gate-0: {e}" for e in g0.errors])
    else:
        notes.append("Gate-0 PASS")
    notes.extend([f"Gate-0 warning: {w}" for w in g0.warnings])

    if registry_path.is_file():
        try:
            registry_data = gate0.load_simple_yaml_mapping(registry_path)
        except ValueError as exc:
            registry_data = {}
            errors.append(f"registry parse: {exc}")
    else:
        registry_data = {}

    g1 = check_gate1(registry_data, root)
    if g1:
        errors.extend(g1)
    else:
        notes.append("Gate-1 PASS")

    g2 = check_gate2(registry_data, root)
    if g2:
        errors.extend(g2)
    else:
        notes.append("Gate-2 PASS")

    g3 = check_gate3(registry_data, root, today=today)
    if g3:
        errors.extend(g3)
    else:
        notes.append("Gate-3 PASS")

    s_err = check_seams(root / seams_rel)
    if s_err:
        errors.extend(s_err)
    else:
        notes.append("Seams PASS")

    r_err = check_residuals(root / residuals_rel, root)
    if r_err:
        errors.extend(r_err)
    else:
        notes.append("Residual PASS")

    gr_err = check_gate_r(root / gate_r_rel, registry_data)
    if gr_err:
        errors.extend(gr_err)
    else:
        notes.append("Gate-R PASS")

    if require_substance:
        sub = check_bootstrap_substance(registry_data)
        if sub:
            errors.extend(sub)
        else:
            notes.append("Substance PASS (optional check; not methodology default)")
    else:
        notes.append("Substance not required (project-specific; methodology default is format/gates)")

    return (len(errors) == 0, errors, notes)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Design methodology gates 0-3 + R, seams, residual. "
            "Default = format/gates only. Substance is optional (--require-substance). "
            "Not a zero-bug guarantee."
        )
    )
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--seams", type=Path, default=DEFAULT_SEAMS)
    parser.add_argument("--residuals", type=Path, default=DEFAULT_RESIDUALS)
    parser.add_argument("--gate-r", type=Path, default=DEFAULT_GATE_R)
    parser.add_argument("--as-of", type=str, default=None)
    parser.add_argument(
        "--require-substance",
        action="store_true",
        help="also fail on bootstrap stubs / generic wording (project-specific; off by default)",
    )
    parser.add_argument(
        "--format-only",
        action="store_true",
        help="deprecated alias: same as default (substance off). Kept for old CI scripts.",
    )
    args = parser.parse_args(argv)

    root = args.root.resolve()
    as_of = date.fromisoformat(args.as_of) if args.as_of else None
    # Default: format/gates. Substance only if explicitly requested.
    require_substance = bool(args.require_substance) and not bool(args.format_only)
    ok, errors, notes = run_all(
        root,
        registry_rel=args.registry,
        seams_rel=args.seams,
        residuals_rel=args.residuals,
        gate_r_rel=args.gate_r,
        today=as_of,
        require_substance=require_substance,
    )

    for n in notes:
        print(n)
    if ok:
        mode = "format+substance" if require_substance else "format/gates"
        print(
            f"Design methodology ops PASS ({mode}: "
            "Gate-0/1/2/3 + Seams + Residual + Gate-R)"
        )
        print("Not claimed: perfect design, zero bugs, exhaustive discovery.")
        return 0

    print("Design methodology ops FAIL", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
