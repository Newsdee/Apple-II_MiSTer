# Gray Seam Removal Plan

## Goal

Add an optional sharper color video stage to `vga_controller.vhd`. The stage
should remove isolated neutral pixels at stable black/white transitions while
preserving Apple II color detail, monochrome output, line-buffer alignment,
and active-video timing.

The first FPGA version will implement only the conservative behavior from
`suppressBlackWhiteSeams()` in
[`../../apple2ntsc/apple2_palgen/palgen.js`](../../apple2ntsc/apple2_palgen/palgen.js).
The JavaScript preview currently also runs `suppressNeutralSeams()`; that
broader pass is intentionally deferred until the conservative implementation
has been compared against representative captures.

## Decisions

- [x] Insert cleanup after Edwards/palette RGB generation and before the
  vertical-comb line RAM.
- [x] Use a five-sample horizontal window with the center delayed by two dots.
- [x] Keep the two-dot delay active when cleanup is off. The menu option only
  selects corrected or unchanged center RGB, so toggling it cannot move the
  picture horizontally.
- [x] Gate replacement with delayed `COLOR_LINE`, not only `SCREEN_MODE`, so
  monochrome and non-Edwards paths remain untouched.
- [x] Carry a valid bit for every window sample. Require all five samples to
  be valid before replacement, preventing decisions across line boundaries.
- [x] Continue shifting during blanking so active pixels 558 and 559 can leave
  the two-dot pipeline unchanged.
- [x] Use MiSTer status bit 4 for the option. It is unused; bits 5 through 31
  are already assigned.
- [x] Default the option to Off.

## Pixel Classification

Use integer luma consistent with the existing vertical comb:

```text
Y = (306 * R + 601 * G + 117 * B + 512) / 1024
saturation = max(R, G, B) - min(R, G, B)
```

For window samples `left2, left, center, right, right2`, replace `center` only
when all of these conditions hold:

- `center.saturation <= 10`
- `36 <= center.Y <= 220`
- The edge is either two stable black samples followed by two stable white
  samples, or the reverse.
- Stable black immediate sample: saturation `< 14` and luma `< 28`.
- Stable black outer sample: saturation `< 14` and luma `< 36`.
- Stable white immediate sample: saturation `< 14` and luma `> 226`.
- Stable white outer sample: saturation `< 14` and luma `> 218`.

Choose the immediate left or right RGB sample whose luma is closest to the
center. Resolve equal distances to the left, matching the JavaScript code.

## Pipeline

```text
VIDEO/shift register
  -> Edwards/palette raw_rgb
  -> five-sample seam window (fixed two-dot delay)
  -> previous-line RGB RAM
  -> vertical chroma comb
  -> VGA RGB
```

Propagate RGB, active, horizontal address, vertical blank, `COLOR_LINE`, and
other mode metadata through explicit registered stages. Do not infer blanking
alignment by changing `de_delayed` tap numbers without a waveform check.

The delayed center address must remain in `0..559` whenever the seam-stage
active signal is asserted. The line RAM must read and write the same delayed
horizontal address.

## Menu Wiring

- [x] Add this Audio & Video menu entry to `../Apple-II.sv`:

  ```systemverilog
  "P2O4,Sharper color video,Off,On;",
  ```

- [x] Connect `.GRAY_SEAM_FIX(status[4])` on the `apple2_top` instance.
- [x] Add `GRAY_SEAM_FIX : in std_logic` to `apple2_top.vhd`.
- [x] Forward `GRAY_SEAM_FIX` through the `vga_controller` instance.
- [x] Add `GRAY_SEAM_FIX : in std_logic` to `vga_controller.vhd`.
- [x] Confirm keyboard-driven `status_in` updates preserve bit 4. The current
  `status[18:0]` slice already does so.

## Implementation Tasks

### 1. Fixed-Latency Pass-Through

- [x] Add the five-sample RGB and metadata window.
- [x] Produce the unchanged center pixel after exactly two dots.
- [x] Delay active, address, VBL, and mode metadata by the same amount.
- [x] Feed the delayed center into the existing vertical-comb input.
- [ ] Verify output is unchanged apart from the intentional fixed latency.
- [x] Align `VGA_HBL` with the complete seam plus comb pipeline.

### 2. Conservative Cleanup

- [x] Calculate luma, saturation, black class, and white class once per new
  sample and shift that metadata with RGB.
- [x] Implement the exact black/white predicates above.
- [x] Implement nearest-immediate-neighbor replacement.
- [x] Require the menu enable, delayed `COLOR_LINE`, and five valid samples.
- [x] Keep unchanged center RGB for every rejected candidate.

### 3. Verification

- [x] Run VHDL/SystemVerilog diagnostics after each edit.
- [x] Compile the Quartus project successfully.
- [x] Confirm the inferred line RAM remains bounded to addresses `0..559`.
- [ ] Review timing and resource reports, especially multiplier/DSP and M10K
  use.
- [ ] Test menu Off and On, including switching while video is active.
- [ ] Compare hardware output against the JavaScript conservative pass.

## Directed Test Cases

- [ ] `black black gray white white` replaces gray with the nearer neighbor.
- [ ] `white white gray black black` handles the reverse edge.
- [ ] Equal luma distance selects the left neighbor.
- [ ] A gray run is unchanged.
- [ ] A colored transition is unchanged.
- [ ] A candidate with only one stable sample on either side is unchanged.
- [ ] First two and last two active pixels are passed through unchanged.
- [ ] No cleanup decision crosses an HBL boundary.
- [ ] B&W, green, and amber screen modes are unchanged.
- [ ] Monochrome text lines in color screen mode are unchanged.
- [ ] Custom palettes remain stable; document if their black/white levels fall
  outside the JavaScript thresholds.
- [ ] The first active line after VBL bypasses vertical combining as before.
- [ ] Vertical comb reads line `n - 1` at the same delayed `x` written by line
  `n`.
- [ ] RGB and `VGA_HBL` begin and end on the same delayed active boundary.

## Deferred Work

- [ ] Evaluate `suppressNeutralSeams()` only after the conservative pass is
  validated on text, Batman, Karateka, and other known seam-heavy screens.
- Treat broader neutral-seam suppression as a separate project. Implement and
  validate it first as a standalone synthetic Verilog core, without connecting
  it to the Apple II video pipeline. Its dedicated plan must cover directed
  pixel-window tests, representative frame/capture comparisons, pipeline
  latency, resource use, and timing. Only after that core is proven should full
  FPGA integration and hardware validation begin.
- [ ] If exact JavaScript-preview matching is required, account for the JS
  two-dot downsample before comparing thresholds and output pixels.
- [ ] Consider a dedicated simulation testbench that asserts address, valid,
  and blanking invariants automatically.

## NTSC Vertical Comb OSD Toggle

- [x] Widen the local status bus to 64 bits and preserve bits 32 through 63 in
  keyboard-driven `status_in` updates.
- [x] Add `P2o0,NTSC vertical comb,On,Off`, using status bit 32 with On as the
  default.
- [x] Forward the runtime enable through `apple2_top` to `vga_controller`.
- [x] Keep the line RAM and registered comb stage active in both modes so the
  RGB and blanking latency cannot change when toggled.
- [x] Average adjacent-line luma when the lines differ by at most 48 levels,
  suppressing artifact-color stripes while preserving hard horizontal edges.
- [x] Remove the compile-time output mux and always use `filtered_rgb` and
  `filtered_active` at the VGA outputs.
- [x] Pass Quartus analysis and synthesis with the 560x24 `OLD_DATA` line RAM
  still inferred.
- [ ] Test On/Off switching on hardware while color video is active.

## Progress Log

- 2026-08-11: Reviewed the active VGA pipeline and JavaScript reference.
  Selected conservative black/white cleanup, fixed two-dot latency, delayed
  `COLOR_LINE` eligibility, and MiSTer status bit 4. No HDL changes yet.
- 2026-08-11: Wired the Off/On menu option through `apple2_top`, implemented
  the conservative five-sample cleanup before the vertical comb, and replaced
  guessed HBL delay taps with active signals registered alongside RGB. Editor
  diagnostics pass.
- 2026-08-11: Quartus 17.0 analysis and synthesis succeeded. The 560x24
  previous-line RAM still infers with `OLD_DATA`; synthesis reports 22,262
  registers, 3,065,492 memory bits, and 45 DSP blocks. Full fit, timing, and
  hardware comparison remain open pending the manual compilation.
- 2026-08-11: Added a default-on NTSC vertical comb OSD toggle on status bit
  32. Both toggle states retain the comb pipeline latency; Quartus analysis
  and synthesis succeeded with 0 errors and unchanged line-RAM inference.
- 2026-08-11: Strengthened the comb for Karateka's striped floor by averaging
  luma as well as chroma for similar adjacent lines; differences above 48 keep
  current-line luma to protect hard edges. Renamed the seam option to
  `Sharper color video`. Quartus analysis and synthesis succeeded.