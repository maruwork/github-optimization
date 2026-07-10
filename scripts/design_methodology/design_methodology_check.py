#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Design methodology ops check 窶・achievable layer beyond \"zero bugs\".

Runs the operational stack that *is* possible:

1. Gate-0  窶・known basic slots not silent (delegates to gate0_registry_check)
2. Gate-1  窶・thin mechanical slice (evidence + oracle assignment shape)
3. Seams   窶・known failure modes named and reviewed (artifact present)
4. Residual窶・honest \"not proof of absence\" declaration
5. Gate-R  窶・closed findings recirculated into registry when marked basic

Does **not** claim perfect design or zero defects.
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
SEAM_STATUSES = frozenset(
    {"open", "mitigated", "residual", "na", "monitored", "accepted"}
)

# Gate-1: oracle text must assign at least one machine path and one human path,
# or explicitly state all-machine / all-human with that word.
_ORACLE_MACHINE = re.compile(
    r"\b(machine|mechanized|auto(?:mated)?|native|external-analyzer|test|ci)\b",
    re.I,
)
_ORACLE_HUMAN = re.compile(
    r"\b(human|manual|sign-?off|review-required|judgment|owner)\b",
    re.I,
)


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
                # evidence may be prose; only fail when it looks like a path
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
        elif has_m and not has_h and not re.search(r"\ball[- ]machine\b", value, re.I):
            # Allow machine-only if explicit; otherwise prefer both named
            if "human" not in value.lower() and "sign" not in value.lower():
                # soft: require human keyword OR explicit all-machine
                if not re.search(r"only\s+machine|machine\s+only|no human", value, re.I):
                    errors.append(
                        "Gate-1 G.oracle: name human-judgment path or state machine-only explicitly"
                    )
        elif has_h and not has_m and not re.search(
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
            # na/deferred ok if reason present (Gate-0 already checked)
            continue
        if not str(entry.get("value", "")).strip():
            errors.append(f"Gate-1 {need}: filled value empty")

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
        if sid == "S5" and status not in {"na", "monitored", "residual", "open", "accepted", "mitigated"}:
            errors.append(f"Seams S5: invalid status {status!r}")

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
        errors.append("Residual: see/evidence path to known-limits or disclosure required")
    else:
        raw = str(see).strip()
        # Accept "see a; b", bare "a; b", or a single path.
        paths = gate0.extract_paths(raw if re.search(r"\bsee\b", raw, re.I) else f"see {raw}")
        if not paths:
            # single path or non-indexed prose: require at least one existing segment
            segments = [s.strip() for s in raw.replace("see ", "").split(";") if s.strip()]
            ok_any = False
            for seg in segments:
                # first path-looking token in segment
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
    """Validate recirculation log. Empty log is OK; closed+promote must bind slots."""
    errors: list[str] = []
    if not gate_r_path.is_file():
        return [
            f"Gate-R: missing log {gate_r_path} "
            "(create with entries: {} if no recirculations yet)"
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

        # Closed records must finish recirculation decision.
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
            # not basic: must say why not promoted
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
) -> tuple[bool, list[str], list[str]]:
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
            errors.append(f"registry parse for Gate-1/R: {exc}")
    else:
        registry_data = {}

    g1 = check_gate1(registry_data, root)
    if g1:
        errors.extend(g1)
    else:
        notes.append("Gate-1 PASS (thin mechanical slice)")

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

    return (len(errors) == 0, errors, notes)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Achievable design methodology checks "
            "(Gate-0/1, seams, residual honesty, Gate-R). Not a zero-bug guarantee."
        )
    )
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--seams", type=Path, default=DEFAULT_SEAMS)
    parser.add_argument("--residuals", type=Path, default=DEFAULT_RESIDUALS)
    parser.add_argument("--gate-r", type=Path, default=DEFAULT_GATE_R)
    parser.add_argument("--as-of", type=str, default=None)
    args = parser.parse_args(argv)

    root = args.root.resolve()
    as_of = date.fromisoformat(args.as_of) if args.as_of else None
    ok, errors, notes = run_all(
        root,
        registry_rel=args.registry,
        seams_rel=args.seams,
        residuals_rel=args.residuals,
        gate_r_rel=args.gate_r,
        today=as_of,
    )

    for n in notes:
        print(n)
    if ok:
        print(
            "Design methodology ops PASS "
            "(known basics + named seams + residual honesty + recirculation log)"
        )
        print("Not claimed: perfect design, zero bugs, exhaustive discovery.")
        return 0

    print("Design methodology ops FAIL", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

