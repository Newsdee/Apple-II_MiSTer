# Development Plan

Before editing or preparing a contribution, read
[Lessons Learned](lessons_learned.md). It documents this repository's mixed
line endings, safe diff workflow, Quartus validation process, video timing
constraints, disk event meanings, and audio requirements.

## Active Work

### Drive Status Overlay

- [x] Add a native-resolution overlay before `video_mixer`.
- [x] Add parameterized Drive 1, Drive 2, and HDD indicators.
- [x] Use dim/bright red for floppy motor/activity states.
- [x] Use dim/bright green for HDD mounted/activity states.
- [ ] Tune position, spacing, dimensions, colors, and hold time on hardware.
- [ ] Consider a small round mask after the 2x2 layout is finalized.

### Floppy Sound

- [x] Review the abandoned PWM implementation and identify the idle-noise bug.
- [x] Replace PWM injection with a resettable sample-based sound module.
- [x] Preserve and add to the Apple speaker and Mockingboard audio paths.
- [x] Export per-drive phase-step events from the Disk II controller.
- [x] Add low-level motor texture and bounded step-click envelopes.
- [x] Guarantee exact zero output while disabled or idle.
- [x] Use wider intermediate addition and saturation.
- [x] Complete Quartus Analysis and Synthesis successfully.
- [ ] Complete Quartus fitting and assembly for a test RBF.
- [ ] Test idle silence, Drive 1, Drive 2, speaker, and Mockingboard audio on
  hardware.
- [ ] Tune motor level, noise rate, click level, and decay duration.
- [ ] Evaluate optional read/write texture only after idle silence is proven.

### Apple-II Verilog Core Bring-Up

- [x] Identify stale source paths in `Apple-II-Verilog_MiSTer/files.qip`.
- [x] Restore automatic `build_id.v` generation in the Quartus flow.
- [x] Complete Quartus fitting, assembly, and timing analysis successfully.
- [x] Generate `Apple-II-Verilog_MiSTer/output_files/Apple-II.rbf`.
- [ ] Deploy the RBF to MiSTer and test boot, video, audio, keyboard, floppy,
  and HDD behavior.

### 65C02 (R65C02) Equivalence Harness

The 65C02 path (`R65Cx2.vhd` golden / `R65Cx2.sv` candidate, selectable via
the core's `cpu` input) has never been exercised by a harness; the apple2
harness drives T65 only. Plan: module_tests/r65c02/PLAN.md in
Apple-II-Verilog_MiSTer.

- [x] Census the candidate opcode table (63 non-NOP mnemonics; full C02
  stack set present; no STP/JAM, JMR, RMB/SMB, BBR/BBI).
- [x] Write the execution plan (module_tests/r65c02/PLAN.md).
- [ ] Create `r65c02_verilog_tb.sv` + `r65c02_vhdl_tb.vhd` (t65 trace schema
  plus SYNC/SYNC_IRQ; byte-identical stimulus; enable tied high).
- [ ] Generate the directed test program with per-mnemonic coverage and
  C02 stack-op value/flag round-trips.
- [ ] Phase A (reset, program, NMI/IRQ, park) green on both DUTs.
- [ ] Phase B (mid-stream reset; post-reset PC/SP sequence gate) green.
- [ ] Register in test_manifest.json, update roster to PASS, full suite
  green (14 tests).

### Verilator Simulation

- [x] Confirm the existing harness is derived from the JimmyStones Verilator
  template and already provides the required simulation-specific MiSTer
  wrapper.
- [x] Confirm a separate checkout of `alanswx/Verilator_Template` is not
  required.
- [x] Use the installed MSYS2 UCRT64 environment as the supported Windows
  build path.
- [x] Install `mingw-w64-ucrt-x86_64-verilator` and
  `mingw-w64-ucrt-x86_64-SDL2` with `pacman -S --needed`.
- [x] Add `bram.sv`, `ramcard.v`, `rom.v`, `timing_generator.v`, and
  `video_generator.v` to the Verilator Makefile RTL source list.
- [x] Remove the duplicate `sim_console.cpp`, stale `rtl/tv80` include path,
  and invalid `-Iimgui` include path from the Makefile.
- [x] Correct stale ImGui include paths in the C++ harness.
- [x] Replace the stale `verilate.sh` and add `build_verilator.bat` so
  `obj_dir` generation is reproducible from Windows.
- [x] Add `run_verilator.bat` with UCRT64 runtime setup and forwarded simulator
  arguments.
- [x] Add `--floppy`, `--floppy2`, `--hdd`, and `--no-floppy` media options,
  including startup failure when requested media cannot be opened.
- [x] Resolve platform-specific C++ issues such as portable local-time
  conversion and selecting SDL/OpenGL under MinGW.
- [x] Send sampled stereo audio to a bounded SDL2 playback queue.
- [x] Run Verilator lint on the complete Apple II RTL source list.
- [x] Run `make` from `Apple-II-Verilog_MiSTer/verilator` in an MSYS2 UCRT64
  shell to generate and build `obj_dir/Vemu.exe`.
- [x] Launch `./obj_dir/Vemu.exe` from the `verilator` directory so relative
  ROM paths and the bundled `floppy.nib` resolve correctly.
- [x] Add and pass a finite `--smoke-test` covering soft reset, PS/2 event
  delivery, rendered video frames, audio sampling/playback initialization,
  floppy reads, and HDD mounting.
- [x] Port the active enhanced VHDL VGA controller to Verilog for simulation,
  including four palettes, custom A2P download, sharper color transitions, and
  vertical chroma blending.
- [x] Add GUI controls and F8-F11 shortcuts for simulation video settings in
  place of the unavailable MiSTer OSD/status registers.
- [ ] Confirm a nonzero audible signal and software-visible keyboard input in
  an interactive simulation session.

## Deferred Video Work

- [Color Knobs Plan](color_knobs_plan.md): adjustable palette mathematics and
  fixed-point palette generation.
- [Gray Seam Removal Plan](rtl/gray_seam_removal_plan.md): sharper artifact
  color and vertical-comb implementation details and remaining validation.
- Consider an optional half-width virtual keyboard. Compress only horizontal
  key geometry and glyph columns while preserving the current height and
  8-pixel glyph rows. This should require modest coordinate/multiplexer logic
  with no additional RAM or DSPs, but spacing and synchronous font-ROM
  prefetch must be reviewed before implementation.

## Contribution Checklist

- [ ] Keep unrelated generated files and experiments out of the commit.
- [ ] Compare normal and whitespace-insensitive diff statistics.
- [ ] Run `git diff --check`.
- [ ] Run editor diagnostics on every touched HDL file.
- [ ] Run Quartus Analysis and Synthesis.
- [ ] Run fitter and assembler when producing an RBF.
- [ ] Confirm the contribution branch is based on current `upstream/master`.
- [ ] Verify hardware behavior before opening or updating a pull request.
