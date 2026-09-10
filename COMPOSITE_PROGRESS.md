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
- [ ] **M2** — write `rtl/video/video_pipeline.sv` (switch + presets + mux).
- [ ] **M3** — wire `apple2_top_woz.v`: swap `vga_controller tv(...)` for
      `video_pipeline vp(...)`, add `use_composite` / `comp_preset[1:0]` inputs.
- [ ] **M4** — wire `Apple-II_woz.sv`: add the `P2O12` preset OSD option; drive
      `use_composite=status[4]`, `comp_preset=status[2:1]`.
- [ ] **M5** — verification (Verilator lint / targeted smoke with
      `use_composite=0` → behavior identical to pre-change); update this doc.

## Open / for the user

- Quartus A&S + full compile (user runs; see AGENTS.md).
- Hardware check of each preset + the RGB↔Composite toggle.
