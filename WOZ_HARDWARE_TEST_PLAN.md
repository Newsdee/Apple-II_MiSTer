# WOZ Side-by-Side Hardware Test Plan

## Goal

Build one known-good Disk II RBF and one WOZ RBF from the same source revision, then compare them on MiSTer hardware without merging the two disk implementations or changing save-state scope.

This document is a plan only. The project currently remains in Disk II mode; do not run `toggle_woz.ps1` or edit `files.qip`/`Apple-II.qsf` while Quartus is compiling.

## Fixed Boundaries

- Disk II build: `Apple-II.sv`, `rtl/apple2_top.v`, `rtl/disk_ii.v`, `rtl/drive_ii.v`, and `rtl/floppy_track.sv`.
- WOZ build: `Apple-II_woz.sv`, `rtl/apple2_top_woz.v`, and the six files under `rtl/woz/`.
- Save states continue to exclude floppy-controller, drive, track-buffer, mounted-image, and WOZ flux state.
- Keep the current single-slot F5-load/F6-save behavior for both variants.
- Do not add SD save-state persistence or the deferred four-slot UI during WOZ validation.
- Keep HDD on image channel 1. WOZ Drive 1 uses channel 0 and Drive 2 uses channel 2.

## Phase 1: Preserve the Disk II Baseline

1. Let the current Disk II full compile finish without modifying active project files.
2. Confirm successful map, fit, timing, and assembly reports under `output_files/`.
3. Record the Quartus version, revision, fitter seed, report timestamps, ALMs, registers, memory bits/M10Ks, and worst timing slack.
4. Preserve the generated Disk II RBF under a distinct test name containing `diskii` and the build date.
5. Boot that RBF on hardware and perform a short control test: NIB boot, Drive 1 read, optional write on a disposable image, Drive 2, HDD, keyboard, video, audio, and F5/F6 save/load.

The Disk II result is the control. Do not rebuild it after WOZ edits and treat the later build as equivalent without recording that distinction.

## Phase 2: Resynchronize the WOZ Variants

Use `WOZ_MERGE.md` as the authoritative list of intentional differences. Preserve those differences while bringing shared wrapper and machine-top behavior forward.

Known current drift to resolve:

- `Apple-II_woz.sv` still contains the older inline F5/F6 filter. Replace that block with the same `savestate_hotkeys` instance used by `Apple-II.sv`.
- Verify the WOZ wrapper still matches the Disk II wrapper for manager ports, main/aux/Saturn RAM split, DDR bridge, CPU locking, `HDMI_FREEZE`, status handling, virtual keyboard, video, and audio outside the documented WOZ delta.
- Verify `rtl/apple2_top_woz.v` still matches `rtl/apple2_top.v` for save-state ports and words 8/9, `machine_ce`, `cpu_frozen`, CPU selection, speaker averaging, and all non-disk logic.
- Confirm both variants use the shared current `rtl/video_generator.v`; ROM contents and registered ROM output must not be restored by save state.

Do not blindly overwrite either WOZ variant. Compare first, reapply only shared changes, and retain the documented WOZ ports, drive activity, media-channel wiring, and disabled floppy-sound behavior. (The 60 Hz IRQ is no longer part of the variant - removed 2026-09-10 as a hardware-verified video fix.)

## Phase 3: Pre-Compile Checks

1. Run the focused `savestate_hotkeys` test after the wrapper resync.
2. Run Verilator lint on `Apple-II_woz.sv`, `rtl/apple2_top_woz.v`, and the WOZ stack.
3. Check that the `disk_ii_woz` instance and module port lists still match exactly.
4. Confirm `files.qip` and `Apple-II.qsf` are still in Disk II mode before invoking the toggle.
5. Run `git diff --check`, compare normal and whitespace-insensitive diff statistics, and run the workspace EOL guard.

## Phase 4: Switch and Compile WOZ

Close Quartus before toggling because Quartus can rewrite `Apple-II.qsf`.

```powershell
Set-Location E:\MiSTer\Apple-II_FPGAdev\Apple-II_MiSTer
.\toggle_woz.ps1 woz
```

After the toggle:

1. Verify both `files.qip` and `Apple-II.qsf` select `Apple-II_woz.sv`, `rtl/apple2_top_woz.v`, and all six WOZ files.
2. Verify Disk II, `drive_ii`, and `floppy_track` are not registered.
3. Run Analysis and Synthesis first. Stop on new binding, inferred-memory, width, latch, multiple-driver, or ROM initialization warnings.
4. If mapping passes, run the full Quartus compile.
5. Confirm fitter, timing, assembler, and RBF timestamps are from this run.
6. Preserve the generated RBF under a distinct test name containing `woz` and the same comparison date.
7. Record resource and timing deltas against the preserved Disk II baseline. Compare parent hierarchy rows carefully; do not sum parents with children.

## Phase 5: Hardware Matrix

Test with disposable writable images where writes are involved.

1. Cold boot a known DOS 3.3 WOZ image in Drive 1. **PASS (2026-09-10 hardware retest)**: boots to the READY. prompt with the 60 Hz pulse removed - the earlier one-second-wait hang hypothesis was a red herring (the original Sep 9 hang was a disk-transport bug, fixed in the woz01->woz04 iterations; the core does not model the 60 Hz heartbeat but the boot path does not need it). Repeat 2-3 cold boots to confirm repeatability, and verify the screen stays clean during and after boot.
2. Confirm Drive 1 reads and that its LED distinguishes motor-active from host transfer activity as documented.
3. Write a file, reboot or remount, and verify persistence when the image is writable.
4. Enable Drive 1 write protection and prove the same write is blocked.
5. Repeat mount/read/write-protect checks for Drive 2 on channel 2.
6. Mount and boot an HDD on channel 1 to prove the WOZ channel reassignment did not disturb it.
7. Exercise warm reset and cold reset; verify warm reset does not unexpectedly reseat a spinning WOZ drive and cold reset does.
8. Check keyboard, virtual keyboard, video modes, palettes, Apple speaker, and Mockingboard for wrapper regressions.
9. With Saturn disabled, test F6 save and F5 load. Confirm the Apple machine state returns but WOZ drive position/controller state does not; this is the accepted v1 limitation.
10. With Saturn enabled, confirm save/load requests are rejected without corrupting machine or RAM state.
11. Test repeated mounts and swaps, read-only images, empty Drive 2, and a WOZ image that previously exercised weak-bit or timing-sensitive behavior in the level-2b harness.

## Phase 6: Return to Disk II

Close Quartus, then restore the project source selection:

```powershell
Set-Location E:\MiSTer\Apple-II_FPGAdev\Apple-II_MiSTer
.\toggle_woz.ps1 diskii
```

Verify both source lists contain the Disk II files and no `rtl/woz/` assignment. Do not delete either preserved RBF. The two named images are the side-by-side hardware artifacts.

## Acceptance Criteria

- Disk II behavior remains unchanged in its preserved baseline RBF.
- WOZ Drive 1 and Drive 2 boot, read, and honor write protection.
- Writable WOZ changes persist to a disposable image.
- HDD channel 1 remains operational.
- No new correctness-relevant Quartus warnings appear.
- Full WOZ compile has nonnegative timing slack and produces an RBF.
- F5/F6 save states behave consistently in both wrappers within the documented exclusion of disk state.
- Resource and timing deltas are recorded from current fitter reports.
- The project is returned to the desired source mode after testing, with that mode explicitly verified.

## Deferred Work

- Standard MiSTer Main SD persistence for the single save-state slot.
- Four save-state slots and NES-style keyboard/OSD/gamepad controls.
- Folding Disk II and WOZ into one parameterized wrapper after both variants are stable.
- WOZ floppy sound, which requires explicit motor/step events rather than inferred host-transfer activity.