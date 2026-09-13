# Composite video — progress / handoff

Last updated: 2026-09-13. Branch `woz-disk-support` (FPGA repo `Apple-II_MiSTer/`),
verilog repo `Apple-II-Verilog_MiSTer/` on `master`.

**Status in one paragraph:** the NTSC composite encode→decode path is integrated,
GUI-testable, and its color chirality is settled by experiment AND FIXED: the
bench decoder's decoded chroma is the **conjugate** of textbook (I,Q), so **"I
mirroring" is the correct fix** — now applied in the FPGA pipeline as a 1-bit
`i_mirror` flag (`chroma_map` reduced from a 2-bit map to this flag: 1 = I-mirror
fix, 0 = normal/upstream; the Q-mirror/swap values were experimental and dropped).
The one-line **brightness sign-extension bug fix is VERIFIED (probe) and ported**
to the FPGA CRLF copy. The decoder now carries the knob set + `rot_mag2`
first-line fix + the **v4 split-notch comb** (`comb_en`) in all copies. The GUI
hue-range experiment (95–127 window) was made and then **reverted** because the
user needs a different hue per graphics mode; the user is testing and will report
measured values.

---

## DONE — brightness sign-extension fix (verified + ported 2026-09-12)

**All 5 remaining steps below are COMPLETE** (probe `+BRIGHT` added; +BRIGHT=0/32/−32
verified: g=170/202/138 — the −32 case is the falsifiable tell, old code clamped to
255; lint clean of new warnings; ported to the FPGA CRLF copy byte-safe; GUI smoke
28/28 with unchanged determinism hash). Retained below as the verification record.

**Bug (user-observed):** GUI brightness slider (−128..+127, "signed offset")
jumps to very positive values on the negative side: **−1 behaves as +255**.

**Root cause:** `composite_decoder.sv` line 615 (all copies) was:

```verilog
wire signed [20:0] y_adj = y_g + 21'sd128 + $signed({4'b0, bright});
```

`{4'b0, bright}` **zero-extends** the 8-bit port, so `$signed` sees
`bright=8'hFF` (GUI −1) as **+255**, `8'h80` (−128) as +128. Positive values
(0x01..0x7F) happened to work, which is why the bug hid. Port contract (comment
line 61) is 8-bit **two's-complement, 0 = none** — so the intended semantics is
the signed slider; the GUI was right, the RTL sign extension was wrong.

**Fix (one token):** `$signed({4'b0, bright})` → `$signed(bright)`
(contextual 21-bit sign extension; `8'hFF` → −1).

**State per copy:**

| Copy | Fix | Verified |
|---|---|---|
| `Apple-II-Verilog_MiSTer/vga_color_test/rtl/composite_decoder.sv` (bench, LF) | ✅ applied | ✅ probe: +BRIGHT=−32 → g=138 (old code clamped to 255) |
| `Apple-II-Verilog_MiSTer/unit_tests/level_2/mister/composite_decoder.sv` (probe DUT, LF) | ✅ synced byte-identical to bench | ✅ (probe source of the run) |
| `Apple-II_MiSTer/rtl/video/composite_decoder.sv` (FPGA, **CRLF**) | ✅ ported (byte-safe sync from bench; comb WIP preserved) | ✅ EOL-stripped identical to bench |

**Remaining steps (exact):**

1. **Probe: add a `+BRIGHT` plusarg.** `tb_mister_mirror_probe.sv` currently
   hardwires `.bright(8'd0)` (line 108). Pattern (next to the existing
   `HUE8`/`COMB_ON` plusargs, lines 88–94):

   ```systemverilog
   logic [7:0] bright8 = 8'd0;
   int b;
   initial if ($value$plusargs("BRIGHT=%d", b)) bright8 = b[7:0];
   ```

   and change `.bright(8'd0)` → `.bright(bright8)`. Negative plusarg values wrap
   into two's-complement 8-bit exactly as the port expects (−32 → `8'hE0`).
2. **Build + run** (fresh link each time to beat the AV grace window; see
   "Commands" below). Expected on the probe tone (baseline hue=0, comb off,
   line 0 decodes `rgb=(0,170,255)`, g=170):
   - `+BRIGHT=0` → bit-identical baseline (g=170) — identity preserved.
   - `+BRIGHT=32` → g ≈ 170+32 (before clipping; read the exact delta from the run).
   - `+BRIGHT=-32` → g ≈ 170−32. **With the old code this clamps to white
     (g=255)** — the falsifiable tell.
3. **Lint** bench decoder + `apple_composite` pair (command below).
4. **Port to the FPGA CRLF copy** — byte-safe path only (see recipe below):
   `perl :raw` single-line replacement of line 615; then verify 667/667 CR count,
   `tr -d '\r'` content-identical to bench, `bash eol_guard.sh` clean,
   `git diff --stat` = +1/−1 on that file.
5. **GUI rebuild + `--smoke-test`** — expect 28/28 and the **same determinism
   hash** (default `bright=0` is unchanged by the fix).

**User question resolved:** "shouldn't it just be 0–255?" — **No.** The design
intent (documented in the port comment) is a signed offset with **0 = none**
(the FPGA pipeline presets drive `bright=0` meaning "no change"); contrast uses
the different 128=unity convention on purpose. Fixing the sign extension makes
the existing −128..127 GUI slider correct as-is. If the user later prefers a
0–255 "128 = none" UI, that is a semantics change (RTL + all presets + GUI) and
should be a conscious decision, not a default.

---

## DONE — horizontal luma sharpen + comb-gate (2026-09-13)

Experimental, **off by default** (no OSD knob exposed in the core; `p_luma_sharpen=0`
in all presets). Two changes, both gated by `color_line` so the color-killed
(monochrome) path stays bit-identical:

- **Horizontal luma unsharp** (`luma_sharpen[3:0]`, 0=off): a 1-tap unsharp mask
  `y + amt*(y - y[-1])` on the final luma, counteracting the decoder's horizontal
  subcarrier-reject low-pass (the "softness"). One register of history (no line RAM);
  vertical sharpen is deliberately out of scope. Clamped back to 18-bit luma range
  before the `<<8`, so the I/Q mix datapath is untouched.
- **Comb gated by `color_line`**: the two-line chroma comb (`comb_en`, driven by the
  existing "vertical blend" OSD option) is now `(comb_en && color_line)` — on
  color-killed lines there is no chroma to blend, so it is disabled there.

Bench: GUI slider + `--comp-luma-sharpen`/`--comp-color-line` CLI; verified
(color-on 0-vs-8 differ, color-off 0-vs-8 identical = gate works); smoke 28/28,
hash unchanged (default off). FPGA: decoder/wrapper/pipeline wired (CRLF, `perl
:raw`); regression 708,624/0 (native path unchanged) + composite contrast. NOTE: the
FPGA decoder keeps its 8-bit `phase` optimization (Quartus 10030) — it is NOT
byte-identical to the bench (24-bit `phase`); behavior-identical for SPC=4.

---

## DONE — composite hue-adjust OSD knob + base hue rework (2026-09-13)

The composite hue is now **base 112 + a temporary 5-bit OSD adjust** (0-31),
effective range 112-143. Mirrors a real display's hue control: the user
dials the color in on the OSD (or previews it on the bench GUI first).

- **Base hue 144 -> 112** in all four presets (`video_pipeline.sv`).
- **New OSD option `P2oPT,Comp Hue Adj`** = `status[61:57]` (5 bits, 32 values
  0-31), at the high end of the status word next to the temp `P2oUV` Comp
  H-Shift. **Temporary — remove with the H-Shift when done.**
- **Effective hue = `p_hue + comp_hue_adj`** (`video_pipeline.sv`), wired
  Apple-II.sv -> apple2_top.v -> video_pipeline -> apple_composite.
- The bench `--comp-hue` slider already previews any hue, so the value can be
  dialed in on the GUI before setting the OSD knob.

Regression: 708,624/0 (native path unchanged) + composite contrast + stall-hold
(hue preserved). EOL clean (numstat == EOL-insensitive numstat). NOTE: hue is
phase-dependent on the input signal; the "correct" value is set on hardware
(Jungle Hunt green ~144 => knob ~32) or on the bench with a correctly-phased
test image.

---

## DONE — OSD reorg: display options on page 0 + gray-out by Display Type (2026-09-13)

Consolidated the color/display OSD options on the top-level page and made the
palette / TV-preset options gray out when they don't apply to the active
Display Type. All edits are OSD-menu-only (`Apple-II.sv` CONF_STR + one
`status_menumask` bit); **status bits and signals are unchanged**.

**Page 0 (top level), final order:**
1. `Display Type` — RGB Monitor / Color TV  (`P0O4`, status[4]; was "Color sharpness" on page 2)
2. `RGB palette` — NTSC //e / IIgs / AppleWin / Custom  (`OOP`->`P0OOP`, status[25:24]; was "Color palette")
3. `Color TV Preset` — Calibrated / Eyeballed / Punchy / Muted  (`P0O12`, status[2:1]; moved from page 2, was "Composite preset")

**Moved to Audio & Video (page 2)** to free the main panel: `Display Mode`
(Color/B&W/Green/Amber, `P2OJK`, status[20:19]; was "Display") and `Custom
Palette` (function, `P2FC2`).

**Gray-out (MiSTer OSD D/d flag + `status_menumask`):**
- `status_menumask` bit 0 (free; savestate owns 7-8) = `status[4]` (Display Type).
- `RGB palette` prefixed `D0` -> grayed in Color TV mode; `Color TV Preset`
  prefixed `d0` -> grayed in RGB Monitor mode.
- The D/d flag goes **first on the line, before the `P0` token** (the
  verified-correct position; a misplaced flag silently shifts the whole page —
  see `docs/SAVESTATE_INTEGRATION_PLAN.md`).
- Caveat: D/d is a miosd (host) feature — not simulatable in Verilator; needs a
  Quartus recompile + hardware look to confirm the gray-out.

**Preset values (hardware-tuned; bench GUI buttons match `sim_gui.cpp`):**

| Preset | Sat | Hue | Bright | Contrast |
|--------|-----|-----|--------|----------|
| Calibrated | 80 | 115 (112+3) | -14 | 177 |
| Eyeballed | 51 | 128 | +10 | 170 |
| Punchy | 100 | 130 | +9 | 255 |
| Muted | 80 | 112 | -5 | 190 |

EOL clean (numstat == EOL-insensitive numstat). Tools: `tools/fix_osd_reorg.pl`,
`tools/fix_osd_move_page2.pl`, `tools/fix_osd_menumask.pl`, `tools/fix_hue_adj.pl`.

---

## DONE — savestate-LOAD hue fix: hs-fall re-anchor of composite phases (2026-09-13)

**Symptom (user-reported, woz22 board):** every F5 (savestate LOAD) rotated the
composite hue by an arbitrary quarter (0/90/180/270-degree subcarrier steps),
different each attempt. SAVE and OSD-pause were fine — the `01e9d48`
`machine_ce` gate (which freezes the pipeline during the stall) is intact and
works (TB phase 3 bit-exact).

**Root cause (second half of the same symptom class):** the encoder
`burst_cnt` (apple_composite.sv) and decoder `phase` (composite_decoder.sv)
free-run; their alignment to the core's HBL holds only by lockstep (line =
whole subcarrier cycles: 912 = 4*228). A LOAD resumes the machine from the
SAVED HBL position (timing-generator counters are restored), so the frozen
phases resume misaligned to the invariant by `(h_stall - h_resume) mod 4`
subcarrier samples -> phase-dependent hue rotation. The `01e9d48` gate removed
the in-stall drift (stall-duration component); the resume-time discontinuity
remained, and was only observable after the savestate DDR read fix landed.

**Fix (core-only, no miosd change):** re-reference both free-runs to the
measured invariant at every derived hs fall — the same edge `hcnt` resets on
(`hs_d && ~hs` in each module):

```verilog
// apple_composite.sv
localparam [1:0] BURST_PHASE_HS_FALL = 2'b11;
if (hs_d && ~hs) burst_cnt <= BURST_PHASE_HS_FALL;
else             burst_cnt <= burst_cnt + 2'd1;

// composite_decoder.sv
localparam [7:0] PHASE_AT_HS_FALL = 8'b1100_0000;
if (hs_d && ~hs_in) phase <= PHASE_AT_HS_FALL;
else                phase <= phase + PHASE_INC[23:16];
```

**Why the constants are board-correct:** measured in the pipeline TB
(`K_enc=3, K_dec=192={3,6'b0}`, constant over 6 lines, pair-offset asserted).
`tools/tb_hbl_pwrup.sv` (timing_generator alone, all inputs 0, Verilator
zero-init == Cyclone V power-up) shows the board's HBLANK: first line 909
cycles (HBLANK register rises at cycle 3), steady state re-grids onto
multiples of 912 from t=0, and 912 % 4 == 0 -> the board's steady-state
fall-edge phase equals the TB's. No preset re-tuning expected. In normal
operation the re-anchor writes the value the counter already holds, so it is
a bit-identical no-op (TB golden pixel R15 G72 Bff unchanged). Post-LOAD the
phases snap to the invariant at the next hs fall (<=1 line, imperceptible).

**TB (tools/tb_video_pipeline_regress.sv, extended):**
- phase 2.5: K-capture at the re-anchor edge (synchronous monitor — the edge
  where pre-edge `(hs_d && !hs)` holds; sample one edge later for the
  post-write value), constancy over 6 lines + `{K,6'b0}` pair check; phase-3
  pre-pixel asserted against the pre-fix golden (no-op proof).
- phase 4 (NEW, models a real LOAD): 12345-cycle `machine_ce=0` stall at
  field16/lcnt150/hcnt500, then the source counters jump to the saved
  position (lcnt170/hcnt701; mod-4 distance 3 = 270-degree misalignment),
  resume; asserts the first re-anchor edge after resume holds `k_inv` and the
  post-load pixel (lcnt180/hcnt600) is bit-identical to the clean pre-stall
  reference.
- RED (pre-fix): phase 4 FAIL — `k_after = k_inv+3` (270 degrees), pixel
  Re4 G10 Bff vs clean R15 G72 Bff. GREEN (post-fix): ALL PASS
  (phases 1-4, 708,624 baseline samples 0 mismatches, stall_changes=0).

**Lint:** no new warnings (HEAD 9 -> tree 8; remainder pre-existing width /
unused-bit notes in the luma path). EOL preserved (autocrlf checkout; diff
shows only the change hunks).

**Build/run (MSYS2):**

```sh
cd /e/MiSTer/Apple-II_FPGAdev/Apple-II_MiSTer
export VERILATOR_ROOT="C:/msys64/ucrt64/share/verilator"
export PATH=/c/msys64/tmp/makeshim:/c/msys64/ucrt64/bin:$PATH
export TMP=/c/msys64/tmp TEMP=/c/msys64/tmp TMPDIR=/c/msys64/tmp
rm -rf obj_dir_tb_vp && mkdir -p obj_dir_tb_vp
/c/msys64/ucrt64/bin/verilator_bin.exe --binary -sv --timing -O2 -Wno-fatal -Wno-lint \
  tools/tb_video_pipeline_regress.sv rtl/video/video_pipeline.sv \
  rtl/video/vga_controller.v rtl/video/apple_composite.sv rtl/video/composite_decoder.sv \
  --top-module tb_video_pipeline_regress -o tb_vp \
  --Mdir obj_dir_tb_vp/obj_dir && ./obj_dir_tb_vp/obj_dir/tb_vp.exe
```

**Not verified:** Quartus compile + board F5 (user). Expected: composite hue
now stable across savestate loads; RGB/other paths untouched (no ports or
instance changes; two always-block bodies only).

---

## Pending changes (not started)

1. **I-mirror chirality fix — DONE (2026-09-12), applied as the `i_mirror` flag.**
   Per the user's instruction, `chroma_map` (2-bit, 4 values) was reduced to a
   1-bit `i_mirror` flag (1 = I-mirror fix, 0 = normal/upstream) across all copies
   (bench decoder + probe DUT + bench wrapper/top/GUI/main.cpp + FPGA decoder/wrapper,
   and `video_pipeline.sv` now sets `p_i_mirror = 1'b1` common to all presets).
   Verified: probe `+I_MIRROR` changes the colors (negates I, rotates hue); FPGA
   regression test 708,624/0 mismatches (native path unchanged) + composite contrast;
   GUI smoke 28/28 with unchanged determinism hash (default `i_mirror=0` = old
   `chroma_map=0`). **Still open:** the Punchy preset's `p_hue=8'd144` was chosen
   under the OLD (unmirrored) convention and will look different after the fix —
   re-verify presets on hardware.
2. **Wire `comb_en` through the FPGA wrapper — DONE (2026-09-13).** The FPGA
   `apple_composite.sv` now has the `comb_en` port (driven by the existing
   "vertical blend" OSD option `NTSC_VERTICAL_COMB` in `video_pipeline.sv`), and
   the decoder gates it with `color_line` (see DONE section above).
3. **Per-graphics-mode hue presets (user is testing).** The single-hue knob
   cannot cover all Apple II graphics modes — the user found they need a
   different hue setting per mode and is measuring; expect a report with
   measured values. Likely outcome: mode-dependent `p_hue` in the pipeline
   (or new presets). Until then the GUI keeps the full 0–255 slider
   (the 95–127 "documented window" experiment was **reverted**; default 0).
4. **Quartus** (user's action per project convention): `quartus_map` binding
   check, then full compile when the pending RTL changes land.
5. **Hardware check** after both #1 and #2: color hue correctness per mode,
   stripe artifacts with comb on/off, glitch-free RGB↔Composite toggle.

---

## Where things are

| File | Role / state |
|---|---|
| `Apple-II-Verilog_MiSTer/vga_color_test/rtl/composite_decoder.sv` | **Forward-path decoder** (LF): knob set (incl. `i_mirror`) + rot_mag2 + v4 split-notch comb + bright fix + horizontal `luma_sharpen` + `color_line` + comb-gate. Source of truth for the port. |
| `Apple-II-Verilog_MiSTer/unit_tests/level_2/mister/composite_decoder.sv` | Probe DUT copy — byte-identical to bench (keep it synced after any decoder edit). |
| `Apple-II_MiSTer/rtl/video/composite_decoder.sv` | FPGA copy — **CRLF**. Has `luma_sharpen` + `color_line` + comb-gate (added via `perl :raw`). Keeps its 8-bit `phase` opt — **NOT byte-identical to bench** (phase width differs); behavior-identical for SPC=4. Edit via `perl :raw` only. |
| `Apple-II-Verilog_MiSTer/vga_color_test/rtl/apple_composite.sv` | Bench wrapper — has `comb_en` port + GUI-driven knobs. |
| `Apple-II-Verilog_MiSTer/vga_color_test/rtl/vga_color_test_top.sv` | Bench top — flat `COMPOSITE_*` inputs incl. `COMPOSITE_COMB_EN`. |
| `Apple-II-Verilog_MiSTer/vga_color_test/src/{vga_sim.h,vga_sim.cpp,sim_gui.cpp}` | GUI: knob state, flat-input drive, "Composite Knobs" window (checkbox "Comb (two-line average)"; hue slider full 0–255 again). |
| `Apple-II-Verilog_MiSTer/unit_tests/level_2/mister/tb_mister_mirror_probe.sv` | Mirror probe — `+COMB_ON`, `+HUE8=%d`, `+BRIGHT=%d`, `+I_MIRROR` plusargs, HSL readout, VERDICT logic. |
| `Apple-II_MiSTer/rtl/video/apple_composite.sv` | FPGA wrapper — has `i_mirror`, `comb_en` (→ NTSC_VERTICAL_COMB), `color_line`, `luma_sharpen` ports. |
| `Apple-II_MiSTer/rtl/video/video_pipeline.sv` | FPGA switch + 4 presets — `p_i_mirror=1'b1`, `p_luma_sharpen=0` (experimental, off), comb_en→NTSC_VERTICAL_COMB. |
| `Apple-II_MiSTer/rtl/video/v3/` | Untracked reference variants (`composite_decoder.sv` v3, `composite_decoder_v4.sv`). **Parked, not forward path** — the v4 split-notch delta is already integrated into the knob version; do not copy v4 wholesale (it lacks knobs + rot_mag2). |
| `Apple-II_MiSTer/COMPOSITE_PROGRESS.md` | This file. |

---

## Verified facts (do not re-derive)

**Probe verdict (definitive, `tb_mister_mirror_probe`, SPC=4):**
decoded (i,q) angle = **+ψ + const**, i.e. conjugated vs textbook (I,Q)
because the demodulator is `i_dem = cc·sin(ph), q_dem = cc·cos(ph)` →
`Z_decoded = j·A*/2`. "I mirroring" (negates I, now the `i_mirror=1` flag) composes
into a pure rotation. **The `i_mirror=1` fix is applied in the pipeline (2026-09-12).**
Baseline numbers (comb off, hue=0): line 0 (i,q)=(−3619,0) @180°,
rgb=(0,170,255); line 1 (1785,−3149) @299.5°; line 2 (1785,+3145) @60.4°.

**`rot_mag2` vs I-mirror — INDEPENDENT (proven, 2026-09-12):**
`div_den <= rot_mag2` (vs `mag2`) is a positive real scalar (sum of squares);
complex division by a positive real cannot conjugate, and in steady state
`rot_i²+rot_q² = ib²+qb²` so the two are numerically identical. Experiment
(temporary revert of the one line): lines 1–2 bit-identical either way (mirror
present in both); only line 0 differs — with `mag2` the previous (blank) line's
burst magnitude is 0 → divide-by-zero → `colour_ok=0` → grey line.
`rot_mag2` = first-line-after-reset fix; `i_mirror=1` = chirality fix.
Both needed; not "fixing a fix".

**Hue knob units (sweep-verified, 16+8 step sweeps):**
- Knob → I/Q plane rotation is **exactly 1:1 linear**: 256 steps = 360°
  (−22.5° per 16 steps, exact).
- Display HSL hue is a **nonlinear** function of I/Q angle (NTSC chroma→RGB
  ellipse). For the probe tone (ψ=0), display 75–105° ≈ knob 166–185.
- The old Apple monitor docs' **75–105° is subcarrier-wheel degrees** (their
  skew specs 107°/240° only make sense on a 360° wheel) → 30° span =
  21.3 knob steps (±10.7 around nominal 111, the user's empirical GUI anchor).
  **This window is now moot** — per-mode hue testing supersedes it; the GUI
  window was reverted.
- The 107° R-Y/B-Y skew is the old monitors' internal demod geometry; it does
  not enter any conversion for our textbook-matrix decoder.

**v4 split-notch comb (integrated, verified):**
`nd` chain ← `c16` (luma from this line only: `n_sum = c16 + c_del`);
`ndc` chain ← `cs` (chroma from 2-line average: `n_dif = cs − cc_del`).
Fixes v3's luma blur (coloured line over black: luma no longer averaged).
Verified: comb off = bit-identical to pre-comb baseline; comb on = luma
preserved (line 0 g=170 vs 106 under v3-comb), chroma = v3-comb values.
Cost: +2×16-bit registers (`ndc`); M10K line RAM unchanged. GUI checkbox added;
smoke 28/28 with unchanged determinism hash `97fde374dfcc4c49` (default comb off).

**RGB matrix is standard NTSC orientation** (verified). The `i_mirror` flag
(was `chroma_map`) and the whole `rtl/video/` tree are the user's own work (FPGA
repo commit 772672e).

**Environment quirks (all hit this session):**
- **AV kill:** freshly linked C++ PEs get killed after a hash-grace window
  (exit 1/127, zero output; copies to new names don't help; relinking buys a
  fresh window). Mitigation: **chain link + run in one command**, or relink to
  a new `.exe` name.
- **Verilator 5.050:** real `%` broken for negatives (use
  `t = t - 6.0*$floor(t/6.0)`-style mod); SV declarations must precede
  statements in a block; `--binary` (not `--exe`) for pure-SV testbenches.
- **MSYS:** native `mingw32-make` only (MSYS make strips TMP/TEMP from
  recipe children); export `TMP/TEMP/TMPDIR=/c/msys64/tmp` **inside** the MSYS
  shell; make shim `make.exe` copy at `/c/msys64/tmp/makeshim` for
  `--binary` link step.
- **CRLF safety:** FPGA decoder is all-CRLF; never run the edit tool on it —
  `perl :raw` byte-exact replacement, then verify CR count + EOL-stripped
  content diff + `bash eol_guard.sh`.
- Exes must run with CWD at the repo root whose `$readmemh` paths they use.

---

## Commands

**Mirror probe** (from MSYS2; fresh link each run):

```sh
cd /e/MiSTer/Apple-II_FPGAdev/Apple-II-Verilog_MiSTer/unit_tests/level_2/mister
export PATH=/c/msys64/tmp/makeshim:/c/msys64/ucrt64/bin:$PATH
export TMP=/c/msys64/tmp TEMP=/c/msys64/tmp TMPDIR=/c/msys64/tmp
rm -rf obj_dir_tb && mkdir obj_dir_tb
/c/msys64/ucrt64/bin/verilator_bin.exe --binary -sv --timing -O2 -Wno-fatal -Wno-lint \
  tb_mister_mirror_probe.sv composite_decoder.sv \
  --top-module tb_mister_mirror_probe -o tb_check \
  --Mdir obj_dir_tb/obj_dir && ./obj_dir_tb/obj_dir/tb_check.exe \
  +COMB_ON +HUE8=176 +BRIGHT=-32    # plusargs as needed
```

**GUI build + smoke** (28 checks; expect hash `97fde374dfcc4c49` while defaults
are unchanged):

```sh
cd /e/MiSTer/Apple-II_FPGAdev/Apple-II-Verilog_MiSTer/vga_color_test
export PATH=/c/msys64/tmp/makeshim:/c/msys64/ucrt64/bin:/usr/bin:$PATH
export TMP=/c/msys64/tmp TEMP=/c/msys64/tmp TMPDIR=/c/msys64/tmp
bash build.sh -j4
export PATH=/c/msys64/ucrt64/bin:$PATH
./obj_dir/Vvga_color_test_top.exe --smoke-test
```

**Lint (bench pair):**

```sh
cd /e/MiSTer/Apple-II_FPGAdev/Apple-II-Verilog_MiSTer
/c/msys64/ucrt64/bin/verilator_bin.exe --lint-only -sv -Wall \
  vga_color_test/rtl/composite_decoder.sv vga_color_test/rtl/apple_composite.sv
```

**FPGA decoder port recipe (byte-safe):**

```sh
cd /e/MiSTer/Apple-II_FPGAdev/Apple-II_MiSTer
perl -0777 -i -pe 's/\QOLDTEXT\E/NEWTEXT/' rtl/video/composite_decoder.sv
tr -cd '\r' < rtl/video/composite_decoder.sv | wc -c        # expect 667
diff <(tr -d '\r' < rtl/video/composite_decoder.sv) \
     <(tr -d '\r' < ../Apple-II-Verilog_MiSTer/vga_color_test/rtl/composite_decoder.sv) \
  && echo CONTENT-IDENTICAL
bash ../eol_guard.sh && git diff --stat rtl/video/composite_decoder.sv
```

---

## History (previous era, condensed)

M1–M5 (2026-09, Woz build): `rtl/video/` created; `vga_controller.v` moved
there; generic `apple_composite.sv` (knob ports) + `composite_decoder.sv`
registered in `files.qip`/`Apple-II.qsf`; `video_pipeline.sv` written (switch +
4 presets + mux, 14 MHz domain, 0 lint warnings); wired into
`apple2_top.v` + `Apple-II_woz.sv` (OSD: "Color sharpness" RGB/Composite =
`status[4]`; "Composite preset" Calibrated/B&W/Punchy/Broken TV = `status[2:1]`).
`tools/tb_video_pipeline_regress.sv`: 708,624 samples 0 mismatches (RGB path
byte-identical) + composite sanity (full-range contrast) PASS.
Preset table at the time: 0 Calibrated (hue 0), 1 B&W (sat 0), 2 Punchy
(**hue 144** — chosen pre-I-mirror, needs re-check), 3 Broken TV (smear 12);
common chroma_map=0, luma_gain=2857, setup=0, agc=1.
