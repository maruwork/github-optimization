# Audit Completion Definition

Status: Active

## Purpose

Define what `complete` means for an audit performed with this shelf.

Completion here means **equilibrium**:

- the audit has a real stopping condition
- no required audit work remains open for the chosen mode and phase
- remaining work, if any, belongs to fixing the target repository rather than continuing the audit

This definition exists so the shelf has an ending state rather than an endless review loop.

## Core Rule

An audit is complete when required evidence, required judgment, and required output records are all closed for the selected audit mode.

Completion is **not** the same thing as reaching maximum coverage or collecting ever more evidence.
Coverage records matter, but they are part of the closure conditions, not the definition of completion itself.

An audit may therefore be complete with a final result of `pass`, `blocked`, `waived`, or an allowed Tier 2 defer.

## Completion Conditions

### 1. Read scope is closed

- `G-21` read log exists
- read exceptions are explicitly listed, or `none`
- read coverage is recorded

### 2. Evidence scope is closed

- machine evidence bundle is attached
- every scored local, hosted, and quickstart claim points to an explicit transcript row
- evidence index is filled for scored claims

### 3. Judgment scope is closed

- every required gate row for the chosen mode is scored, or explicitly marked `n/a` with reason where allowed
- provisional machine states such as collector `review` are not left hanging; the report resolves them into gate judgment or cites an allowed defer / waiver path
- if Tier 2 is deferred, the required defer record exists and the selected mode allows that defer

### 4. Output scope is closed

- final label is assigned
- required supporting records exist when invoked by the judgment
- every `blocked` row has a fix task

### 5. Hidden unfinishedness is absent

- unresolved ambiguity is written explicitly as note, defer, waiver, or accepted-risk record
- nothing required is left implicit in agent memory or raw tool output alone

## What Does Not Count As Complete

The audit is **not** complete merely because:

- `run-full-audit.*` exited `0`
- machine evidence was collected
- the report scaffold exists
- coverage improved
- most gates are filled

The target repository may still need substantial fixes and the audit may still be complete.
What matters is whether the audit has reached a regulation-valid stopping state.

## Practical Test

Ask this question:

> If another reviewer reads the report and cited transcripts, is any required audit step still missing before the final label can be assigned or defended?

If the answer is `yes`, the audit is not complete.
If the answer is `no`, the audit has reached equilibrium and is complete.
