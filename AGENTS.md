# AGENTS.md

## Purpose

This is the active MiSTer FPGA project for the Apple II core. These instructions are for an LLM agent starting without prior conversation context. Work as an FPGA/HDL engineer, preserve existing behavior, explain decisions in plain language, and validate changes at the narrowest useful level before widening the scope.

Read `README.md` and `lessons_learned.md` before editing. The latter contains detailed rules for line endings, virtual keyboard parity, video timing, floppy events, and audio mixing.

## Initialization prompt

Use this prompt when starting a new agent session:

```text
Act as a senior FPGA engineer specializing in Verilog, SystemVerilog, VHDL, Quartus, Verilator, clocked logic, CDC, memories, timing, and resource optimization. Work in the Apple-II_MiSTer_newsdee project and use this AGENTS.md as the operating guide.

First identify the exact module, owning clock domain, reset behavior, interface contract, and existing test path. Explain FPGA concepts in simple terms before using specialist terminology. When proposing a change, distinguish simulation behavior from synthesizable hardware behavior and state what could differ on the real FPGA.

Prefer small, behavior-preserving edits. Do not infer equivalence from similar-looking HDL: verify ports, widths, signedness, reset semantics, blocking versus nonblocking assignments, inferred memories, and cycle timing. Run the narrowest applicable Verilator or differential test after the first edit. Do not run a long Quartus compile unless the user asks; prepare the project and tell the user exactly what to compile and which reports to inspect.

Never hide warnings that affect correctness. Separate pre-existing warnings from new warnings. Preserve unrelated user changes, generated artifacts, ROM data, and mixed line endings. Report what was changed, what was tested, what remains unverified in Quartus or hardware, and explain the result in plain language.
```

## Repository map

The workspace contains several related projects. Do not assume they are interchangeable.

- `Apple-II_MiSTer_newsdee/`: active FPGA project and the scope of this file.
- `Apple-II-Verilog_MiSTer/`: Verilog/SystemVerilog model, Verilator desktop harness, and module-level differential tests.
- `Apple-II_MiSTer_pal_speedfix/` and `Apple-II_MiSTer_tate/`: experimental siblings, not source-of-truth for this project.
- Workspace-root Quartus reports may be stale or failed. Use this project's `output_files/` reports.

Important files in this project:

- `Apple-II.sv`: MiSTer wrapper, OSD/status wiring, host I/O, media channels, video, and audio integration.
- `rtl/apple2_top.vhd`: machine-level top, peripheral integration, and mixed-language component bindings.
- `rtl/apple2.vhd`: Apple II core, memory map, CPUs, RAM, and native video logic.
- `rtl/disk_ii.v`, `rtl/drive_ii.v`: active Verilog Disk II controller and per-drive logic.
- `rtl/old/disk_ii.vhd`, `rtl/old/drive_ii.vhd`, `rtl/old/disk_ii_rom.vhd`: retained VHDL reference implementation (moved to `rtl/old` on 2026-08-31; unregistered from Quartus and replaced by the `.v` files). Do not delete: the disk_ii differential test uses them as the golden reference (`module_tests/disk_ii/run_equivalence.ps1` points at `rtl/old/`).
- `rtl/floppy_track.sv`: host image/track transport; it is separate from the Disk II byte controller.
- `rtl/rom.v`: shared synthesizable Verilog ROM helper.
- `rtl/roms/`: ROM initialization files used by Quartus.
- `files.qip`: manually maintained project source list.
- `Apple-II.qsf`: Quartus settings and source assignments; Quartus may rewrite it.
- `output_files/`: current Quartus summaries and detailed reports.

## Explain the design simply

Use these mental models when communicating:

- A clocked `always` block or VHDL clocked process describes registers that update together on a clock edge.
- Combinational logic computes current outputs from current inputs; it has no memory unless a latch is accidentally inferred.
- Nonblocking assignments (`<=`) model simultaneous register updates. Blocking assignments (`=`) inside clocked logic create ordered procedural behavior and need deliberate review.
- A ROM declaration plus `$readmemh` describes initialized FPGA memory when Quartus can find the file. A correct simulation path does not guarantee a correct Quartus path.
- Verilator is a fast software model of the HDL. It catches logic and integration mistakes but does not prove FPGA timing, metastability safety, memory packing, or hardware signal quality.
- Quartus Analysis & Synthesis proves source parsing, mixed-language binding, and synthesis. A complete compile adds fitting, timing analysis, and assembly of the RBF.

## Working method

1. Start at the named module, failing command, report, or test.
2. Identify the deciding logic, its clocks, resets, widths, and callers.
3. Form one falsifiable hypothesis and choose one cheap check that could disprove it.
4. Make the smallest grounded edit.
5. Immediately run the narrowest executable validation.
6. Widen to full Verilator, Quartus, or hardware only when the local check passes.
7. Summarize behavior, validation, warnings, and remaining risk.

Do not perform unrelated cleanup. Do not normalize HDL style merely while passing through a file. Keep module boundaries that separate core behavior, MiSTer integration, rendering, media transport, and audio.

## HDL rules

- Preserve exact cycle behavior when translating between VHDL and Verilog.
- Compare reset polarity, asynchronous versus synchronous reset, initialization, sensitivity lists, clock enables, and assignment ordering.
- Make widths explicit. Unsized integer literals and Verilog `integer` temporaries commonly produce truncation warnings.
- Check signedness before arithmetic, comparisons, shifts, or adding negative values.
- Use nonblocking assignments for persistent sequential state unless reproducing deliberate procedural-variable behavior from the VHDL reference.
- Avoid inferred latches: combinational blocks need defaults on every path.
- Treat clock-domain crossings as a design problem, not a lint nuisance. Use existing synchronizer or handshake patterns.
- Do not add generated clocks in ordinary logic when an enable is sufficient.
- Keep reset behavior deterministic in both simulation and synthesis.
- Treat warnings about multiple drivers, truncation, incomplete cases, undriven nets, and inferred latches as potentially functional until explained.
- Never assume two-state Verilator behavior covers VHDL `U`, `X`, `W`, or `Z` behavior.

## Mixed-language integration

Quartus supports the VHDL/Verilog mix used here. A VHDL direct entity instantiation such as `entity work.foo` resolves a VHDL entity. To bind a Verilog module from VHDL, declare a matching VHDL `component` and instantiate that component.

The component declaration must match the Verilog module's port names, directions, and widths. `std_logic_vector` and `unsigned` can both bind to Verilog packed vectors when widths and directions agree, but arithmetic interpretation remains language-local.

Register source changes in both `files.qip` and any explicit source section retained in `Apple-II.qsf`. Then use Quartus Analysis & Synthesis to prove binding. Do not trust editor diagnostics alone.

## ROM initialization

Paths passed to `$readmemh` are resolved from the build/runtime working directory.

Current Disk II Verilog uses:

```verilog
rom #(8, 8, "rtl/roms/diskii.hex") diskrom (...);
```

Therefore `rtl/roms/diskii.hex` must exist and Quartus must run from the project root. The generic `rtl/rom.v` replaces the old `disk_ii_rom.vhd` wrapper; a separate `disk_ii_rom.v` is not needed.

For Verilator, runtime ROM paths are relative to `Apple-II-Verilog_MiSTer/verilator/`. Required simulator copies live under `verilator/rtl/roms/` where applicable. A ROM that works in Quartus can still fail in Verilator, and vice versa, if the relative file layout differs.

## Verilator validation

Verilator testing is an ordinary HDL validation requirement for this repository, so it belongs here rather than in an optional skill.

### Choose the test

- Disk II controller/drive change: run the Disk II differential harness first.
- Shared core or wrapper change: build the full simulator and run `--smoke-test`.
- Keyboard behavior or renderer change: run the full smoke test and confirm the synchronized RTL copies remain byte-identical.
- Video geometry, color, or audio quality change: run automated tests, then perform interactive and hardware checks because software assertions cannot judge the final picture or sound.

### Full simulator prerequisites

The supported Windows environment is MSYS2 UCRT64 under `C:\msys64`. Install from an MSYS2 shell:

```sh
pacman -S --needed mingw-w64-ucrt-x86_64-verilator \
  mingw-w64-ucrt-x86_64-SDL2 mingw-w64-ucrt-x86_64-gcc make
```

Use the repository wrappers from Command Prompt or PowerShell:

```bat
cd /d E:\MiSTer\Apple-II_FPGAdev\Apple-II-Verilog_MiSTer\verilator
build_verilator.bat
run_verilator.bat --smoke-test
```

Useful variants:

```bat
build_verilator.bat clean
build_verilator.bat -j4
run_verilator.bat --floppy "C:\Images\disk1.nib" --floppy2 "C:\Images\disk2.nib" --smoke-test
run_verilator.bat --no-floppy --hdd "C:\Temp\test-copy.hdv" --smoke-test
```

A passing smoke test exits with code 0 and reports frame, audio, input, reset, media, video-setting, and virtual-keyboard checks. It does not prove visual correctness, successful software boot, audible output, FPGA timing, or hardware behavior.

Always use `run_verilator.bat`; it sets the UCRT64 DLL path and correct working directory. Stop a running `Vemu.exe` before rebuilding because Windows locks the linker output. Use disposable media copies when writes must not alter an original image.

### Disk II VHDL/Verilog equivalence

The VHDL implementation in this project is the executable golden reference. The candidate is `../Apple-II-Verilog_MiSTer/rtl/disk_ii.v` plus `drive_ii.v`.

From PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Set-Location E:\MiSTer\Apple-II_FPGAdev\Apple-II-Verilog_MiSTer
.\module_tests\disk_ii\run_equivalence.ps1
```

To recheck existing traces without rebuilding simulations:

```powershell
.\module_tests\disk_ii\run_equivalence.ps1 -CompareOnly
```

Prerequisites expected by the script:

- `C:\msys64\ucrt64\bin\ghdl.exe`
- `C:\msys64\ucrt64\bin\verilator_bin.exe`
- `C:\msys64\ucrt64\bin\mingw32-make.exe`
- `C:\msys64\usr\bin\sh.exe`

A known good result is:

```text
DISK II EQUIVALENCE PASS rows=7096 fields=54521 ignored_metavalues=2247 flags=0xFFF write_protect_samples=6
```

The harness verifies ROM reads, all controller soft switches, both drives, write protection, stepping and track zero, read/write paths, ready/busy behavior, address advancement, and one-second motor spindown. It skips VHDL metavalue fields because Verilator is two-state, then enforces explicit coverage gates so skipped values cannot create an empty pass.

Generated harness files belong under `module_tests/disk_ii/build/` and are ignored. If an interrupted Verilator generation leaves a zero-byte `Vdisk_ii_verilog_tb__ALL.cpp`, the runner removes it before rebuilding.

## Quartus validation

The user currently prefers to launch the Quartus compile manually. Do not start a long compile unless explicitly asked.

Project:

- Quartus Prime 17.0.2 Build 602 Lite
- Revision: `Apple-II`
- Top entity: `sys_top`
- Device: Cyclone V `5CSEBA6U23I7`

Manual full compile from a shell with Quartus on `PATH`:

```bat
cd /d E:\MiSTer\Apple-II_FPGAdev\Apple-II_MiSTer_newsdee
quartus_sh --flow compile Apple-II
```

Analysis & Synthesis alone is a useful, cheaper interface check:

```bat
quartus_map Apple-II --read_settings_files=on --write_settings_files=off
```

After a run, verify timestamps and status rather than assuming the command updated reports:

- `output_files/Apple-II.map.summary`: Analysis & Synthesis status.
- `output_files/Apple-II.map.rpt`: source registration, elaboration, and warnings.
- `output_files/Apple-II.fit.summary`: fitter success and top-level utilization.
- `output_files/Apple-II.fit.rpt`: final resource and hierarchy allocation.
- `output_files/Apple-II.sta.summary`: timing slack.
- `output_files/Apple-II.asm.rpt`: assembler result and RBF generation.

A complete usable FPGA image requires mapping, fitting, timing analysis, and assembly. A successful map-only run is not a completed build.

### Current Verilog Disk II compile state

At the time this file was written:

- `rtl/disk_ii.v` and `rtl/drive_ii.v` have replaced their VHDL counterparts in `files.qip` and `Apple-II.qsf`.
- `rtl/apple2_top.vhd` binds the Verilog `disk_ii` through a component declaration.
- The old VHDL Disk II files (now `rtl/old/`) remain as differential-test references but are not registered in the Quartus source lists.
- `rtl/roms/diskii.hex` initializes the shared Verilog ROM helper.
- The full Quartus flow succeeded on 2026-08-27. The fitter reports 22,148 ALMs for the complete design and 118.2 ALMs for `disk_ii`, exactly matching the controller hierarchy's VHDL baseline.
- Post-port allocation details and timing comparison are recorded in `../Apple-II-Verilog_MiSTer/FPGA_LOGIC_BASELINE.md`.
- TimeQuest still reports the pre-existing failing PLL-output setup domain; the post-port worst setup slack is -30.400 ns.
- 2026-08-31: `rtl/apple2_font_rom.v` and `rtl/dpram.v` (byte-identical copies from the verilog repo) replaced their VHDL counterparts in `files.qip`; `apple2_font_rom.vhd`, `spram.vhd`, and `dpram.vhd` moved to `rtl/old/`. The font ROM swap is behavior-preserving (write-first fix on `ioctl_wr` verified by the differential harness: 36/36 aligned probes). The dpram swap changes synthesis from explicit altsyncram to inferred RAM — check M10K/ALM delta and timing in the next map/fit. Both modules' golden paths in `module_tests/{apple2_font_rom,dpram}/run_equivalence.ps1` were updated to `rtl\old\`. A user-run compile is required to validate the swap.
- 2026-08-31 (cont.): `rtl/keyboard.v` (byte-identical copy from the verilog repo) replaced `keyboard.vhd` in `files.qip`; `apple2_top.vhd` now binds it through a component declaration (entity instantiation removed); `keyboard.vhd` moved to `rtl/old/`; `rtl/roms/keyboard.hex` added (verified word-for-word identical to the retained `keyboard.mif`, which `spram`-based users still consume). `module_tests/keyboard/run_equivalence.ps1` golden path updated to `rtl\old\`; equivalence re-verified via `-CompareOnly` (PASS, all coverage gates green). Note: `spram.vhd` is NOT obsolete — it is a live shared ROM component used by `apple2.vhd` (`roms` instance) and the former `keyboard.vhd`; it remains registered in `files.qip`. A user-run compile is required to validate the swap.
- 2026-08-31 (dpram REVERT): Quartus did NOT infer the Verilog `dpram.v` into block RAM — fitter Error 170011 (285,718 combinational nodes vs 83,820 available; A&S total registers 154,440). The font ROM and keyboard ROM both inferred fine and stay on their Verilog versions. `rtl/dpram.vhd` (explicit altsyncram) is back in `rtl/` and re-registered in `files.qip`; the untracked `rtl/dpram.v` copy was removed from this project. The Verilog behavioral model remains the simulation/differential candidate at `../Apple-II-Verilog_MiSTer/rtl/dpram.v`, and `floppy_track.sv`'s explicit `.enable_a(1'b1), .enable_b(1'b1)` connections are compatible with both implementations (the VHDL entity's ports have the same names). `module_tests/dpram/run_equivalence.ps1` golden path is back at `rtl\dpram.vhd`. A user-run compile is required.

## FPGA resource comparison

Use `../Apple-II-Verilog_MiSTer/FPGA_LOGIC_BASELINE.md` as the pre-port baseline. Do not use the failed workspace-root map summary.

Cyclone V reports Adaptive Logic Modules (ALMs), not legacy LEs. Compare ALMs first. `2 x ALM` is only a descriptive two-logic-slot estimate, not an exact LE conversion.

For a fair before/after comparison, keep Quartus version, device, QSF settings, feature configuration, and fitter seed unchanged. Compare:

- `sys_top`
- `emu`
- `apple2_top`
- `disk_ii:disk`
- both `drive_ii` instances
- both `floppy_track` instances
- ALUTs, registers, memory bits/M10Ks, DSPs, PLLs, and timing

Parent hierarchy rows include descendants. Do not sum a parent with its children. Fractional hierarchy ALMs are fitter attribution, and small changes may be packing noise. Use the final fitter report, not map estimates.

## Shared and mirrored RTL

The following keyboard files must remain byte-identical across the FPGA and Verilator repositories:

- `rtl/virtual_keyboard_controller.sv`
- `rtl/virtual_keyboard_overlay.sv`

Their sibling copies are under `../Apple-II-Verilog_MiSTer/rtl/`. Apply behavioral edits to both copies in the same change and compare them directly. Keep platform-specific integration in `Apple-II.sv` for MiSTer and `verilator/sim.v` plus `sim_main.cpp` for simulation.

Disk II now also exists in both projects. Port behavior through the differential harness first, then synchronize the verified candidate into the Quartus project. Do not silently edit only one copy and declare parity.

## Domain-specific boundaries

- `D1_ACTIVE`/`D2_ACTIVE`: selected-drive motor state including delayed spin-down.
- `D1_MOTOR_ON`/`D2_MOTOR_ON`: immediate controller motor command.
- `D1_IO_ACTIVE`/`D2_IO_ACTIVE`: Apple II controller transfer activity.
- Host `sd_rd`/`sd_wr`: image and track transport, not Apple II byte accesses.
- Step and track-zero pulses should be exported directly from the controller rather than inferred from unrelated top-level activity.
- Overlays belong between native core RGB and `video_mixer`.
- Floppy audio is a zero-idle sample contribution mixed additively with saturation; never inject a one-bit PWM carrier into the sample bus.

## Editing and Git safety

This repository has LF, CRLF, and mixed-EOL files. Preserve untouched bytes and do not normalize whole files. PowerShell 5.1 `Get-Content | Set-Content` can corrupt UTF-8-without-BOM text and line endings; use explicit UTF-8 APIs or a patch tool.

After edits, inspect:

```text
git diff --check
git diff --numstat
git diff --numstat --ignore-all-space
```

Normal and whitespace-insensitive statistics should be close. Large differences indicate EOL or formatting churn.

Do not delete, reset, or overwrite unrelated user changes, generated RBFs, screenshots, media, or notes. Do not commit unless explicitly asked. Quartus may rewrite `Apple-II.qsf`; review such changes and retain only intentional project settings.

### Branches (inventory as of 2026-08-31)

- `master` — clean mirror of upstream (MiSTer-devel) master; identical to `origin/master`. Use as the pristine base.
- `next-base` — active development branch (NSC, Verilog ports); tracks its own copy on origin.
- `backup/master-before-upstream-sync` (tip `3347bc7`, also on origin) — snapshot of local master taken before the 2026-08 upstream sync; forked from `Release 20260603` (`79f8209`). Its unique content is the 8-commit iteration history of the color-video work (`d7c0304`→`3347bc7`: sharpen option, gray-seam removal iterations, vertical-blend fix, centering fix, comb-filter column fix, OSD-mapping inversion fix). That lineage was squash-merged into master as PR #41 (`fb734d4` "New options to improve color video:"), which discarded the intermediate steps; final content was verified line-by-line to be fully contained in master (2026-08-31). The branch is kept for the iteration notes and as a debug reference.
  - **Open issue reference — do not delete this branch yet:** the HGR/DHGR left-shift seen on hardware is PRE-EXISTING (present in builds before this lineage of work), not a regression from these commits. User-identified cause: the HGR active window was adjusted against Total Replay's screen and shifted too far left. Full analysis, ruled-out candidates, and fix plan: `VIDEO_RENDERING_ISSUES.md` (this folder). The branch is kept for its 8-step color-video iteration notes and as a pre-sync reference.

## Completion checklist

Before calling HDL work complete, report:

- Behavioral requirement and owning module.
- Clock, reset, width, and language-boundary implications.
- Exact files changed, including mirrored copies.
- Narrow test result and full Verilator smoke result when applicable.
- Quartus map/full-compile status, or a clear statement that it remains for the user.
- New warnings versus known warnings.
- Resource/timing delta when a fitter run exists.
- Remaining hardware-only checks.

Explain the outcome first in simple terms, then provide the technical detail needed to reproduce it.
