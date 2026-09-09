# Video rendering issues — investigation notes

Two open video issues, tracked together because they share the same pipeline
(`timing_generator.v` → `video_generator.v` → `vga_controller.vhd`).

Last updated: 2026-08-31.

---

## Issue 1: HGR/DHGR image shifted left (PRE-EXISTING)

### Symptom
The rendered image sits slightly too far left. Most noticeable in DHGR, but it
is present in **all display modes including B&W/Green/Amber** — i.e. it is a
geometric/window property, not a color-processing artifact.

### Status: geometry probe complete; HSHIFT knob implemented and verified (2026-08-31)
The per-mode geometry probe (`Apple-II-Verilog_MiSTer/module_tests/video_geometry/`,
see RESULTS.md) shows **no mode-specific centering difference exists in the
pipeline**: TEXT40/HGR/DHGR share identical line geometry, load phase, and bar
landing position (±1 sample of content-dependent jitter for DHGR MSB=1 bytes).
The shift is a single global offset. A runtime **H shift** OSD knob (status bits
[4:1], 0..15 samples) has been added to `vga_controller.v` and verified
cycle-accurate. Finding the right N on hardware is the remaining step.

**The shift is NOT a regression from the color-video work**
(`d7c0304..3347bc7`, PR #41). It was confirmed present in builds from before
that lineage of changes.

**Stated cause:** the active window for HGR was adjusted using Total Replay's
screen as the visual reference, and it was shifted too far to the left.

### Calibration context on record
The only Total-Replay-based window calibration in the project record is the
`vga_color_test` session of 2026-08-30
(`Apple-II-Verilog_MiSTer/vga_color_test/PROGRESS.md`):

- Measured DUT property: *"Data/window skew ~12 samples: the RGB data pipeline
  leads the timing window by ~12 cycles, so content fed at the falling edge
  appears ~12 samples early."*
- Feed alignment was tuned against Total Replay B&W (`--align` default **12**,
  `--phase` default **2**): *"offset 12 = perfect left edge but phase-0 colors;
  offset 14 = correct colors with the content 2 samples right of the window
  edge — the real core's actual phase."*
- Residual after alignment: 0.08% mismatch (90 px) vs the Total Replay source.
- **Verification tool:** `vga_color_test/tools/shift_check.py` measures the
  circular shift between a source PNG and a B&W PPM dump — use it to measure
  "how many pixels too far" and to validate any fix.

### What was ruled out as the adjustment (git-history checks, 2026-08-31)
| candidate | result |
|-----------|--------|
| `VGA_HSYNC=68` / `VGA_ACTIVE=282*2` / `VGA_FRONT_PORCH=130` in `vga_controller.vhd` | identical in **every** commit that touched the file (back to `887e25e`) |
| `VGA_HBL <= de_delayed(9) and de_delayed(17)` (the pre-PR#41 windowing expression) | tap positions never changed; expression comes from upstream commit `887e25e` (sorgelig, May 2020) |
| video delay/shift line in `Apple-II.sv` | none exists |
| the 8-commit color work itself | adds to but did not create the shift: `aae7150` moved output tap `next_rgb(2)`→`next_rgb(4)` (net 2 px left, all modes) and `d7c0304` introduced the `hcount < 560` active window |
| `WNDW_N` / H counter / `HBL = ~(H[5] | (H[3]&H[4]))` in `timing_generator.v` | faithful port of the original VHDL — no adjustment; active window = H ∈ [88..127] (40 RAS steps ≈ 560 cycles), identical in all modes |
| per-mode LDPS load phase (geometry probe) | TEXT40/HGR/DHGR(MSB=0): loads at lc ≡ 11 (mod 14), 65/line — identical; DHGR MSB=1: +1 cycle (T6); TEXT80: double rate (expected). No mode-specific centering offset |

### Open questions
1. **Which parameter is the "window" adjustment?** Remaining candidates:
   (a) the `vga_color_test` feed-alignment defaults (tester display only — if
   the shift is seen on hardware, this alone is not it);
   (b) a manual/uncommitted build adjustment made during that calibration era;
   (c) ~~`WNDW_N`-related gating~~ — checked: faithful VHDL port, ruled out.
2. **How many pixels too far left?** Measure with `shift_check.py` against the
   Total Replay B&W reference, or compare a hardware screenshot to a known-good
   build. The H shift knob makes this a direct on-hardware measurement.

### Fix plan (status 2026-08-31)
1. ~~Locate the window parameter~~ — all core-RTL window mechanisms ruled out;
   geometry probe proves the offset is global, not per-mode.
2. **Done:** runtime right-shift knob in `vga_controller.v`:
   - OSD item `P2O1234,H shift,Off,1,...,15;` → status bits [4:1] →
     `apple2_top.HSHIFT` → `vga_controller.HSHIFT`.
   - Implementation: 15-stage delay pipe on the packed raw pipeline
     (`raw_rgb/raw_bit/raw_settled/raw_hcount/raw_active/raw_vbl/
     raw_color_mode/raw_color_line`, 41 bits) before `seam_cleanup`; a mux
     selects stage N-1 for HSHIFT=N, and HSHIFT=0 bypasses the pipe entirely
     (bit-identical to the unshifted design).
   - Because data, active-window strobe, seam decisions, and line-RAM writes
     are all delayed together, the NTSC vertical comb stays self-consistent in
     color mode.
   - Verified with the geometry probe sweep (HGR): HSHIFT=0 reproduces the
     pre-change baseline exactly (vga_bar [273..315], vga_hbl_fall 22);
     HSHIFT=1/3/7/15 move vga_bar by exactly +1/+3/+7/+15 samples with
     hsync_rise (695), line period (911), and core-side vid_bar unchanged.
3. **Remaining:** user finds the correct N on hardware (Total Replay HGR/DHGR
   comparison); if the right edge then clips, readjust HBLANK/porch
   (`VGA_FRONT_PORCH` / HSYNC position) to make everything fit; validate with
   `shift_check.py` vs `assets/total_replay.png` and in all display modes.

### Pipeline latency reference (by inspection, from the earlier analysis)
| era | VIDEO→VGA_R latency |
|-----|---------------------|
| pre-PR#41 (`79f8209`) | 1 cycle |
| PR#41 tap-2 era (`d7c0304..85f1afc`) | 6 cycles |
| master / next-base (tap 4, after `aae7150`) | 4 cycles |

A fixed output delay shifts all modes equally — it cannot create a
mode-specific offset, but it does change absolute centering.

---

## Issue 2: B&W mode — Batman background shapes hidden (NEW, 2026-08-31)

### Symptom (user report)
Playing the Batman game: some **background shapes are hidden in B&W mode** but
show fine in **Amber or Green**.

### Why this is suspicious
On real Apple II hardware B&W/Green/Amber are all 1-bit displays: identical
video memory produces an identical on/off silhouette — only the phosphor tint
differs. Mode-dependent hiding of shapes is therefore a divergence from real
hardware **unless the game itself draws different content per mode**.

### Code analysis (master and next-base — identical here)
- `apple2_top.vhd:460`:
  ```vhdl
  COLOR_LINE_CONTROL <= (COLOR_LINE or (TEXT_COLOR and not TEXT_MODE))
                        and not (SCREEN_MODE(1) or SCREEN_MODE(0));
  ```
  → in B&W ("01"), Green ("10") and Amber ("11") the controller receives
  `COLOR_LINE = '0'` on **every** line.
- `vga_controller.vhd`, `COLOR_LINE='0'` path:
  ```vhdl
  if shift_reg(2) = '1' then
      -- B&W: X"FFFFFF"   Green: X"00C001"   Amber: X"FF8001"
  end if;
  -- else: keep base background (B&W X"000000", Green X"000F01", Amber X"200801")
  ```
- The on/off decision (`shift_reg(2)`) is **identical in all three modes** →
  for identical video memory, the current code produces an identical silhouette
  in B&W/Green/Amber. The LUT/artifact path (and its SCREEN_MODE independence)
  is never reached in these modes because COLOR_LINE is forced low.

### Candidate explanations (in order)
1. **Game-side behavior:** Batman may render different content when it runs in
   B&W (some games inspect $C051 and change patterns for contrast). If so, this
   is expected, not a core bug.
   *Definitive test:* run the same scene in B&W and Amber in the Verilator
   harness; dump screen RAM ($2000–$3FFF) both times; compare byte-for-byte.
   RAM differs → game behavior. RAM identical but output differs → core bug,
   then trace which pixel branch diverges (should be impossible per the code
   analysis above — if it happens, re-verify the COLOR_LINE forcing).
2. **Observation conditions:** different OSD settings (palette / sharpness /
   vertical blend) or a different build between the B&W and Amber observations.
3. **Older build:** if the observation was made on an RBF predating current
   master, re-test on a current build first.

### Next steps
- Reproduce in Verilator (a `batman.png` asset already exists under
  `Apple-II-Verilog_MiSTer/vga_color_test/assets/`; better: run the actual game
  from ROM if available).
- Screen-RAM comparison across modes is the first discriminating check.

---

## Files referenced
- `rtl/timing_generator.v` — HAL timing, LDPS_N/WNDW_N generation
- `rtl/video_generator.v` — CLK_7M shift register (VIDEO bit = 2×14M cycles in all modes)
- `rtl/vga_controller.vhd` — pixel_generator (LUT + rotation), seam_cleanup
  (window + tap), vertical_line_buffer, vertical_comb_filter; output =
  continuous assign from `filtered_rgb`
- `rtl/apple2_top.vhd:460` — COLOR_LINE forcing per SCREEN_MODE
- `Apple-II-Verilog_MiSTer/vga_color_test/` — PLAN.md / PROGRESS.md (Total
  Replay calibration record), `tools/shift_check.py`, `assets/total_replay.png`
- `backup/master-before-upstream-sync` — pre-sync reference (8 color commits)
