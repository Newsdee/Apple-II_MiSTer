# WOZ Disk Support — Toggle Merge

WOZ `.woz`-image floppy support (from `Apple-II-Verilog_MiSTer/rtl/woz/`,
proven in the `unit_tests/level_2b` Verilator + Quartus builds) merged into
this project as **file variants + a project-file toggle**. No in-flight file
is modified: the Disk II build (`Apple-II.sv` + `rtl/apple2_top.v`) is
byte-unchanged.

## Files

| File | Role |
|---|---|
| `Apple-II_woz.sv` | WOZ variant of the `emu` wrapper (copy of `Apple-II.sv` + delta below) |
| `rtl/apple2_top_woz.v` | WOZ variant of the machine top (copy of `rtl/apple2_top.v` + delta below) |
| `rtl/woz/` (6 files) | The WOZ stack, byte-identical copies from `Apple-II-Verilog_MiSTer/rtl/woz/` |
| `rtl/woz_bram.vhd` | Fallback explicit-altsyncram `woz_bram` (copy from `unit_tests/level_2b/mister/rtl/`). **Not registered** — the Verilog `woz_bram.sv` inferred fine in the level_2b fitter. Register this (and unregister `rtl/woz/woz_bram.sv`) only if a fitter run ever fails to infer the `.sv`. |
| `toggle_woz.ps1` | Flips `files.qip` + `Apple-II.qsf` between the two disk variants |

## The WOZ delta (what the variants change vs the Disk II originals)

### `rtl/apple2_top_woz.v` (vs `rtl/apple2_top.v`)
1. Port list: the 12 `TRACK1*/TRACK2*` track-bus ports are replaced by 17
   WOZ SD ports: `SD_LBA0/1[31:0]`, `SD_RD0/1`, `SD_WR0/1`, `SD_ACK0/1`,
   `SD_BUFF_DIN0/1[7:0]`, `SD_BUFF_ADDR[8:0]`, `SD_BUFF_DOUT[7:0]`,
   `SD_BUFF_WR`, `IMG_MOUNTED0/1`, `IMG_READONLY`, `IMG_SIZE[63:0]`.
2. `disk_ii disk(...)` (which internally instantiates `drive_ii` x2 on the
   track bus) is replaced by `disk_ii_woz disk(...)` — 31/31 ports, 1:1.
   `.WE(cpu_we)`, `.RESET(reset)`, `.DD_RESET(reset_cold)` (cold reset
   re-seats the drives; warm reset leaves them spinning).
3. WOZ exposes only `D1/D2_ACTIVE` — `D1/D2_MOTOR_ON`, `D1/D2_IO_ACTIVE`,
   `D1/D2_STEP_ACTIVE`, `D1/D2_TRACK_ZERO_STEP` are tied to 0. `DISK_READY`
   input kept in the port list, unused.
4. **60 Hz IRQ added** (level_2/level_2b pattern): one 16-cycle pulse per
   VBL rising edge in the 14 MHz domain, ANDed into the core's `IRQ_n`.
   The ROM's 60 Hz handler keeps the OS 1-second counter that the DOS 3.3
   boot path waits on; without it the boot hangs. The Disk II variant does
   NOT have this (pre-existing main-project behavior — if the save-state
   workstream needs DOS 3.3 to boot there too, it needs the same block).

### `Apple-II_woz.sv` (vs `Apple-II.sv`)
1. `CONF_STR`: `S0,WOZ,Drive 1` / `S2,WOZ,Drive 2` (was `S0/S2,NIBDSKDO PO `).
   Channel 2 is drive 2 (channel 1 stays the HDD). `OQR` Write Protect is
   unchanged (`status[26]/[27]` -> `D1_WP/D2_WP`).
2. `P3o12` "Disk drive sound" OSD option removed; the `floppy_sound`
   instance is kept but fully tied off (`enable=0`, all motion inputs 0) —
   the flux drives expose no motor/step signals. Re-enabling later means
   restoring the 8 input connections + the option line.
3. `floppy_track` x2 removed: hps_io SD channel 0 -> drive 1, channel 2 ->
   drive 2, wired straight into the `apple2_top_woz` SD ports (the WOZ
   speaks the hps_io streaming protocol natively; `sd_blk_cnt` is left
   unconnected = 0 = single-block requests, which is all the WOZ issues).
4. `disk_mount[x]` latch kept (the WOZ takes `IMG_MOUNTED` as a LEVEL:
   `img_size != 0` while mounted). `DISK_CHANGE` removed (no change line on
   the WOZ path).
5. Drive LED overlay: activity = `sd_rd|sd_wr` per channel (was
   `D1/D2_IO_ACTIVE`); motor stays `D1/D2_ACTIVE`.
6. HDD (channel 1) and everything else (keyboard, video, audio, save-state,
   mouse, slots 4/5) are unchanged.

### Save state
No interaction: the save-state scope (see `SAVESTATE_INTEGRATION_PLAN.md`)
explicitly excludes the disk path, and both variants inherit the in-flight
save-state wiring unchanged. A loaded state does not restore WOZ drive
state (same known v1 limitation as the level_2 work).

## Toggling

```powershell
cd E:\MiSTer\Apple-II_FPGAdev\Apple-II_MiSTer
.\toggle_woz.ps1 woz     # switch the project to WOZ disk mode
.\toggle_woz.ps1 diskii  # switch back to Disk II (.nib) mode
```

The script rewrites the two bannered source blocks in `files.qip` and
`Apple-II.qsf` (Quartus must not be running; it rewrites the qsf). After
toggling, run Analysis & Synthesis to prove binding, then a full compile.

## Re-syncing the variants (drift management)

`Apple-II.sv` and `rtl/apple2_top.v` are edited by the in-flight save-state
work. When they change, regenerate the variants:

```powershell
copy /y Apple-II.sv Apple-II_woz.sv
copy /y rtl\apple2_top.v rtl\apple2_top_woz.v
```

...then re-apply the delta above (it is small and fully documented in this
file). The delta is a `diff` of a few hundred lines; keep this document's
delta list in sync with whatever you re-apply. Once save-state lands and
stabilizes, the end-state option is to collapse the two variants into the
single files behind a `USE_WOZ` parameter — not done yet on purpose (the
save-state session owns those files right now).

## Validation status

- WOZ stack: proven in `unit_tests/level_2b` (Verilator boots DOS 3.3 from
  `.woz`; Quartus Fitter + Assembler green, `level2b.rbf`, 30% ALM).
- Variants: Verilator `--lint-only` (both files, all Verilog deps) shows
  **zero new errors** vs the Disk II baseline — the only delta is the
  removed `floppy_track` `dpram` instance. Remaining lint messages are
  pre-existing harness artifacts (VHDL modules `hdd`/`dpram`/`ssc_rom`,
  generated `pll_0002`, Verilator case-sensitivity on `MOCKINGBOARD` etc.).
- `disk_ii_woz` instance: 31/31 ports, 1:1 match (verified by script).
- `apple2_top_woz` instance in the wrapper: every connected pin exists in
  the port list; only `ioctl_wait` unconnected (same as the Disk II
  wrapper).
- **Quartus A&S / full compile / hardware: NOT YET RUN** — the project is
  currently registered in Disk II mode; toggle to WOZ and compile.

## Hardware test (when the WOZ RBF is built)

1. Mount a `.woz` on Drive 1 (OSD -> Mount -> Drive 1).
2. Cold reset; DOS 3.3 should boot (needs the 60 Hz IRQ, which the WOZ
   variant provides).
3. Drive 1 LED should dim while the motor runs, flash on I/O.
4. OSD "Write Protect" -> "Drive 1" should block writes.
5. Drive 2 (channel 2) and the HDD (channel 1) must still work.
