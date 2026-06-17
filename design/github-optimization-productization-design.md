# GitHub Optimization Productization Design

Status: Complete

## GOP-T1 Surface Separation

### Start Conditions

- this shelf has only one long checklist note

### Read

- `README.md`
- the current local placement and installation rules that govern shared-tool adoption

### Write

- `README.md`

### Do

- split the guidance into root files, `.github/` files, GitHub settings, and optional growth items
- define a minimum baseline for pre-public repositories

### Accept

- a reader can identify placement by section, not by inference

## GOP-T2 Reusable Templates

### Read

- current `README.md`

### Write

- `templates/README.md`
- template files under `templates/`

### Do

- provide reusable starter templates for the highest-signal common files
- keep each template generic and root or `.github/` placement aware

### Accept

- a project maintainer can tell which template maps to which path

## GOP-T3 Reusable Checklists

### Write

- `checklists/README.md`
- checklist files under `checklists/`

### Do

- separate local pre-public checks from GitHub settings checks
- separate minimum required items from optional growth items

### Accept

- a maintainer can walk through public-prep checks without rereading the long essay

## GOP-T4 Application Rules

### Read

- the current local installation rule for shared-tool adoption
- the current shared entry surface that routes readers to this tool

### Write

- `README.md`
- the shared entry surface that routes readers to this tool

### Do

- define that this tool applies only after repository-local placement rules are explicit
- define what can be installed to root
- define what belongs under `.github/`

### Accept

- the tool does not encourage ad hoc file placement

## GOP-T5 Summary And Management

### Write

- a durable productization summary note

### Do

- record what changed
- record where project application should be managed locally

### Accept

- the next installer can use the tool without reconstructing intent from chat
