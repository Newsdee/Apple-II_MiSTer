# AGENTS.md - working agreements for this repo

## miosd policy (STRICT - do not change miosd by default)

The shared miosd tree (e.g. `../Main_MiSTer_clean_disk_order`) is shared by
ALL cores. Do NOT modify it except for very special circumstances. When a
change is genuinely required, it must be addressed **independently of core
changes** (its own task/commit, reviewed on its own merits) - e.g. Apple-II
floppy-disk special handling (WOZ passthrough, CRC refresh).

Rationale: miosd changes ship to every core and are expensive to maintain
across upstream re-bases. Whenever the sys/miosd protocol permits, core
behavior MUST be achieved with core-only (RTL/confstr) changes.

### Precedent: "Savestates to SDCard" toggle (status bit 45)

Gated **HDL-side** (NES idiom - the NES core gates F5/F6 via `allow_ss` +
menumask bit 7), NOT miosd-side:

- `Apple-II.sv` wires `ss_sd_enabled = status[45]` into the
  `savestate_manager.allow_save_state` gate and into `savestate_ui.allow_ss`
  (which drives menumask bit 7, graying the F5/F6 OSD lines when Off).
- With the toggle Off the manager rejects F5/F6 and never bumps the slot
  counter word; stock miosd only writes a `.ss` file when the counter
  changes, so **unmodified miosd never writes anything**.
- The miosd a2 call site stays at stock `process_ss(name)`. (A 2026-09-18
  experiment gated it miosd-side via `user_io_status_get("D", 1)`; that
  delta was REVERTED under this policy. Post-mortem: the first version used
  lowercase `"d"`, which `user_io_status_bits` silently parses as 0 -
  option chars are 0-9/A-V only, +32 comes from `ex=1`.)

See `docs/SAVESTATE_INTEGRATION_PLAN.md` for the full design record.

## Building miosd in this environment (WSL Ubuntu 20.04)

The repo Makefile expects the Armbian SDK toolchain name (`arm-none-linux-gnueabihf`,
which defaults to Cortex-A9 **with NEON**). This box only has Ubuntu's
`arm-linux-gnueabihf` (g++ 9.4), whose default armv7 target has **no NEON**.
That matters: upstream `scaler.cpp` has a latent bug — `limit` is declared
only in the `#if __ARM_NEON` branch (line ~165) but referenced by the scalar
fallback (line ~340), so a no-NEON build fails to compile. Build with the
explicit Cortex-A9+NEON hard-float profile:

```bash
wsl bash -c 'make -C /mnt/e/MiSTer/Apple-II_FPGAdev/Main_MiSTer_clean_disk_order \
  -B BASE=arm-linux-gnueabihf \
  CC="arm-linux-gnueabihf-gcc -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard"'
```

(`-B` = full rebuild so VDATE is consistent; it keeps the previous
`bin/MiSTer_apple2_*` artifacts for rollback. Then copy `bin/MiSTer` to
`bin/MiSTer_apple2_<YYMMDD>` per the flashing convention. MSYS note: wrap in
`wsl bash -c '...'` or Git Bash rewrites `/mnt/e/...` paths.)

