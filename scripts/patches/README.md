# patches/

Patches against the vendored Common Source Code Project core under `src/core/`.

The core is normally taken from upstream unmodified, and problems are absorbed
in the bridge or in the Nim application layer. A patch lands here only when a
defect is genuinely inside the core and cannot be reached from above. Every
patch must have a matching entry in `docs/dev/DevelopmentPlan.md` explaining
the defect, the evidence for it, and how it was verified.

Re-vendoring the core silently drops these patches, so run
`scripts/apply_core_patches.sh` after every re-import.

## Usage

```sh
scripts/apply_core_patches.sh          # apply every patch not yet applied
scripts/apply_core_patches.sh --check  # report status, change nothing
```

Both forms are idempotent: an already-applied patch is reported and skipped.

## Current patches

| Patch | Affects | Summary |
|---|---|---|
| `0001-x1-display-zpal-slot-routing.patch` | `src/core/vm/x1/display.cpp` | `get_zpal_num()` gated the 8 colour (ASIC palette RAM) fold on `hireso`, so in 200 lines / 80 columns a palette write could never reach the eight `zpal[]` corners the renderer actually reads. Seven of the eight graphics colours stayed at their identity values. Present in upstream and reproducible in the original Windows build. |
