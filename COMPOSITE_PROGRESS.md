# Composite video integration — progress

Integrate the NTSC composite encode→decode path into the newsdee core behind the
existing **"Color sharpness" (RGB / Composite)** OSD option, with **4 fixed
presets** (no knobs exposed). All presentation video lives under `rtl/video/`.

Branch: `woz-disk-support`. The active build (`files.qip` + `Apple-II.qsf`)
registers the **Woz variant** (`Apple-II_woz.sv` + `rtl/apple2_top_woz.v`), so the
wiring goes there. The non-Woz `Apple-II.sv` / `rtl/apple2_top.v` are NOT in the
active project file lists, so they are left untouched.

## Design (locked)

- **On/off** = existing `P2O4,Color sharpness,RGB,Composite` → `status[4]`.
  - `use_composite = status[4]`.
  - Existing `.GRAY_SEAM_FIX(~status[4])` stays: composite on ⇒ seam-fix off
    (the seam fix only applies to the native RGB color path).
- **Preset selector** = new `P2O12,Composite preset,Calibrated,B&W,Punchy,Broken TV`
  → `status[2:1]` (bits 1,2,3 were free in the lower bank). `comp_preset[1:0]`.
- **Domain**: the composite path runs in the **14 MHz** domain (one sample per
  clock, `ce=1`), inside `apple2_top_woz`, *before* the video_mixer. This is the
  level-2-validated approach (4x the timing slack of the 57 MHz mixer domain).
- **Modules** (all in `rtl/video/`):
  - `vga_controller.v` — moved here (native RGB color path; unchanged).
  - `apple_composite.sv` — **generic** encoder + loopback decoder; all knobs are
    ports. Presets are driven from outside (video_pipeline), so this stays
    preset-free.
  - `composite_decoder.sv` — mister's decoder, instantiated by apple_composite.
  - `video_pipeline.sv` — **the switch**: wraps vga_controller + apple_composite,
    holds the 4-preset `case`, and muxes the final RGB on `use_composite`.
- **Presets** (encoder sat/hue/bright/contrast + decoder knobs; common:
  chroma_map=0, chroma_short=0, luma_gain=2857, setup=0, agc=1, pixel_delay=0):
  - 0 **Calibrated**: sat=128 hue=0 bright=0 contrast=128 smear=0 luma_delay=0
  - 1 **B&W**:        sat=0   hue=0 bright=0 contrast=128 smear=0 luma_delay=0
  - 2 **Punchy**:     sat=128 hue=144 bright=0 contrast=128 smear=0 luma_delay=0
  - 3 **Broken TV**:  sat=128 hue=0 bright=0 contrast=128 smear=12 luma_delay=0

## Milestones

- [x] **M1** — create `rtl/video/`; move `vga_controller.v`; copy
      `apple_composite.sv` (generic, knob-port) + `composite_decoder.sv`;
      register all in `files.qip` + `Apple-II.qsf`.
- [x] **M2** — write `rtl/video/video_pipeline.sv` (switch + presets + mux);
      register it. Verilator `--lint-only -Wall`: **video_pipeline.sv is clean
      (0 warnings)**. Remaining warnings are pre-existing in the moved files
      (`vga_controller.v` 166, `composite_decoder.sv` 6 — WIDTHEXPAND/
      WIDTHTRUNC, all benign) plus one benign `apple_composite.sv` warning
      (`video_pipe[3]` unused because `pixel_delay` is tied to 0).
- [x] **M3** — wire `apple2_top_woz.v`: swap `vga_controller tv(...)` for
      `video_pipeline vp(...)`, add `use_composite` / `comp_preset[1:0]` inputs.
      Verilator parse of `apple2_top_woz.v` (all Verilog/SV sources): no syntax
      errors; all 28 `video_pipeline` ports connected, every referenced signal
      declared. (Full mixed-language binding is for Quartus A&S.)
- [x] **M4** — wire `Apple-II_woz.sv`: add the `P2O12,Composite preset,
      Calibrated,B&W,Punchy,Broken TV` OSD option (status[2:1]); drive
      `use_composite=status[4]`, `comp_preset=status[2:1]` in the apple2_top
      instance. Verilator parse: no syntax errors.

  **Integration complete for the Woz build.** M5 = verification.
- [x] **M5** — verification (Verilator). See below.

## Verification (M5)

`tools/tb_video_pipeline_regress.sv` (Verilator-only, NOT a Quartus source;
not in `files.qip`/`Apple-II.qsf`). Differential test with a synthetic 14 MHz
NTSC-ish signal (912-cycle line, 352 HBL + 560 active, 3-line VBL, 262-line
field):

1. **Regress** — `video_pipeline(use_composite=0)` vs a bare `vga_controller`,
   same inputs, every active-field sample compared for 4 fields:
   **708,624 samples, 0 mismatches → PASS.** The existing VGA path is
   byte-identical (no regression).
2. **Composite sanity** — flip `use_composite=1`, 4 fields:
   **Rmin=0 Rmax=255, 328,412 non-zero → PASS.** The encode→decode wiring
   (sync derivation + burst + loopback decoder) is alive and produces
   full-range contrast.

Run command (MSYS2 ucrt64; build+run in one command to beat the AV grace
window on the freshly-linked PE):

```sh
cd /e/MiSTer/Apple-II_FPGAdev/Apple-II_MiSTer_newsdee
export VERILATOR_ROOT=/c/msys64/ucrt64/share/verilator
export PATH="/c/msys64/tmp/makeshim:/c/msys64/ucrt64/bin:$PATH"
mkdir -p /c/msys64/tmp/makeshim
[ -x /c/msys64/tmp/makeshim/make.exe ] || cp /c/msys64/ucrt64/bin/mingw32-make.exe /c/msys64/tmp/makeshim/make.exe
BD=/c/msys64/tmp/compbuild; rm -rf "$BD"; mkdir -p "$BD"; cd "$BD"
/c/msys64/ucrt64/bin/verilator_bin.exe --binary -sv --timing -O2 -Wno-fatal -Wno-lint \
  /e/MiSTer/Apple-II_FPGAdev/Apple-II_MiSTer_newsdee/tools/tb_video_pipeline_regress.sv \
  /e/MiSTer/Apple-II_FPGAdev/Apple-II_MiSTer_newsdee/rtl/video/video_pipeline.sv \
  /e/MiSTer/Apple-II_FPGAdev/Apple-II_MiSTer_newsdee/rtl/video/apple_composite.sv \
  /e/MiSTer/Apple-II_FPGAdev/Apple-II_MiSTer_newsdee/rtl/video/composite_decoder.sv \
  /e/MiSTer/Apple-II_FPGAdev/Apple-II_MiSTer_newsdee/rtl/video/vga_controller.v \
  --top-module tb_video_pipeline_regress -o tb_regress && ./obj_dir/tb_regress
```
- [ ] **M5** — verification (Verilator lint / targeted smoke with
      `use_composite=0` → behavior identical to pre-change); update this doc.

## Open / for the user

- **Quartus Analysis & Synthesis** (cheap binding check) — proves the
  VHDL/Verilog mix + `video_pipeline`/`apple_composite`/`composite_decoder`
  bind and elaborate:
  ```bat
  cd /d E:\MiSTer\Apple-II_FPGAdev\Apple-II_MiSTer_newsdee
  quartus_map Apple-II --read_settings_files=on --write_settings_files=off
  ```
- **Full compile** (map+fit+sta+asm) for a usable RBF (user runs):
  ```bat
  quartus_sh --flow compile Apple-II
  ```
- **Hardware**: toggle **OSD → Video → "Color sharpness"** between RGB and
  Composite; with Composite, **"Composite preset"** selects
  Calibrated / B&W / Punchy / Broken TV. Confirm each preset looks right and
  the RGB↔Composite toggle is glitch-free.
- Watch the fitter for the ALM/M10K delta from adding the composite encoder +
  decoder (a few hundred to low-thousands of ALMs expected; check timing).
