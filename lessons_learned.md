# Lessons Learned

This file records repository-specific practices discovered while developing the
video filters, drive indicators, and floppy sound support. Read this before
editing source files or preparing a pull request.

## Editing and Line Endings

The upstream repository contains a mixture of LF, CRLF, and mixed-EOL files.
The repository uses `text=auto`, while the installed Git configuration has
`core.autocrlf=true`. A normal editor rewrite can therefore make Git report
nearly every line as changed.

- Preserve the existing bytes and line endings of untouched lines.
- Do not normalize an entire source file as incidental cleanup.
- Avoid PowerShell 5.1 `Get-Content | Set-Content` rewrites. They can change
  line endings and can corrupt UTF-8 text without a BOM.
- For scripted edits, read and write explicitly as UTF-8 without a BOM:

  ```powershell
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
  [IO.File]::WriteAllText($path, $text, $utf8)
  ```

- When editing a mixed-EOL file programmatically, preserve each existing line
  ending and insert only the required lines.
- After every edit, compare normal and whitespace-insensitive statistics:

  ```text
  git diff --numstat
  git diff --numstat --ignore-all-space
  git diff --check
  ```

  The first two results should agree closely. A large difference usually means
  line-ending or whitespace churn rather than functional work.
- Quartus can rewrite `Apple-II.qsf`. Treat this as generated tool churn unless
  the project settings were intentionally changed. Do not include it in a
  source-only contribution by accident.

## Git and Contribution Workflow

- Keep experimental work on a feature branch.
- To contribute one clean commit, create a branch from `upstream/master` and
  use `git merge --squash` or recreate the functional diff there.
- Review staged files and statistics before committing.
- Preserve untracked RBF files, screenshots, and design notes with a stash when
  switching to a clean contribution branch.
- Use `git push --force-with-lease` when replacing a previously published
  squashed commit. Do not use an unrestricted force push.
- After resetting to `upstream/master`, create a new child commit. Do not amend
  the upstream tip itself.
- Verify a contribution branch with:

  ```text
  git rev-list --count upstream/master..HEAD
  git diff --check upstream/master..HEAD
  git diff --stat upstream/master..HEAD
  ```

## Validation Workflow

- Run editor diagnostics immediately after the first functional edit.
- Use Quartus Analysis and Synthesis to validate mixed VHDL/SystemVerilog
  interfaces and source registration.
- Reports are written under `output_files/`; the root project directory may not
  contain the current reports.
- Check `output_files/Apple-II.map.summary` for the current timestamp and a
  successful result. Old fitter, assembler, or timing reports do not validate
  a new map-only run.
- A complete testable RBF requires fitting and assembly, not only
  `quartus_map`.
- Hardware behavior remains the final validation for video alignment, display
  safe areas, audio level, and perceptual effects.

## Virtual Keyboard Development

The MiSTer and Verilator projects intentionally keep byte-identical copies of
the keyboard behavior and renderer. Every functional keyboard change must be
applied to both files in the same edit:

```text
Apple-II_MiSTer_newsdee/rtl/virtual_keyboard_controller.sv
Apple-II-Verilog_MiSTer/rtl/virtual_keyboard_controller.sv

Apple-II_MiSTer_newsdee/rtl/virtual_keyboard_overlay.sv
Apple-II-Verilog_MiSTer/rtl/virtual_keyboard_overlay.sv
```

Do not update only the currently open project. After editing, verify each pair
with `diff -u`; no output is the expected result:

```bash
diff -u Apple-II_MiSTer_newsdee/rtl/virtual_keyboard_controller.sv \
  Apple-II-Verilog_MiSTer/rtl/virtual_keyboard_controller.sv
diff -u Apple-II_MiSTer_newsdee/rtl/virtual_keyboard_overlay.sv \
  Apple-II-Verilog_MiSTer/rtl/virtual_keyboard_overlay.sv
```

Project wrappers are intentionally different. MiSTer wires OSD status through
`Apple-II_MiSTer_newsdee/Apple-II.sv`; simulation wires GUI settings through
`Apple-II-Verilog_MiSTer/verilator/sim.v` and `sim_main.cpp`. Keep behavioral
logic in the shared controller/overlay files and integration logic in these
wrappers.

### Keyboard State and Controls

- MiSTer `status[42]` is the source of truth for whether the keyboard is
  displayed. Selecting `Virtual keyboard: On` must display it immediately.
- F10, Escape, and the MiSTer `Keyboard On` controller button emit
  `enabled_toggle`; the wrapper writes the inverse back through `status_in` and
  asserts `status_set`. This works while the OSD menu is closed.
- `status[41:40]` stores the independent keypad visibility level: 100%, 75%,
  50%, or 25%.
- Joystick bit 4 selects a key, bit 5 sends the Apple II back key, bit 6 toggles
  the keyboard, bit 7 cycles its opacity, bit 8 moves the keyboard, bit 9 sends
  Return, and bit 10 sends Space. Return and Space work whether the overlay is visible or hidden: they
  emit one key-down event, stay held, and emit one key-up event without repeat.
  Held D-pad directions and bit 5 use the same
  millisecond-based staged repeat timing; only D-pad navigation snaps to an edge.
- Navigation snap must use visual key alignment, not raw column-number reuse.
  Rows are staggered and detached controls use high column numbers.
- Right snap stops at the keyboard's visual edge: Del, Return, Right Shift, or
  Up arrow. Vertical snap follows the same irregular neighbor links as repeated
  one-key movement, including detached controls.
- Add special vertical transitions before generic row movement. The bottom row
  does not share a one-to-one column layout with the letter rows.

### Renderer Geometry

- Key rectangles and hit testing are the same logic. Whenever a key moves or
  changes width, update `key_left`, `key_width`, and the surrounding range test
  together.
- Ordinary rectangular keys remove their four extreme corner pixels. The
  L-shaped Return key has custom geometry and is excluded from this mask.
- The recessed well and row separators must use the same horizontal bounds.
  Keep visible left and right gaps between the well border and key edges.
- CMD, running-man, and diamond controls form a detached 40-pixel-wide column.
  Center the whole column in the area to the right of the recessed well.
- Running-man frames `$46` and `$47` use a special two-glyph placement. Their
  visible bitmap edges include blank columns, so inspect the ROM data before
  changing spacing.
- `screen_comparison/virtual_keyboard_layout_preview.svg` is hand-authored, not
  generated. Update it whenever renderer geometry changes and validate it as
  XML. The SVG is a preview; the SystemVerilog remains authoritative.

### Font ROM and Simulation

- MiSTer uses the 8192-byte `rtl/roms/video2.mif`. Verilator uses the flattened
  `verilator/rtl/roms/video2.hex` with the same 13-bit banked address layout.
- Verilator runtime paths are relative to the `verilator` directory. ROM files
  required by `$readmemh` must be under `verilator/rtl/roms`.
- Build and smoke-test from MSYS2 UCRT64:

  ```bash
  export PATH=/ucrt64/bin:$PATH
  cd /e/MiSTer/Apple-II_FPGAdev/Apple-II-Verilog_MiSTer/verilator
  make -j2
  ./obj_dir/Vemu.exe --smoke-test
  ```

- A running `Vemu.exe` locks the linker output on Windows. Stop it before
  rebuilding. A passing smoke test must include `keyboard_opened=1` and
  `keyboard_closed=1`.
- The smoke test starts with keyboard visibility Off so F10 proves both setting
  updates: Off to On/open, then On to Off/closed.

## Video Pipeline

- RGB and blanking must be treated as related but distinct timing paths.
  Advancing both by the same number of clocks does not move content within the
  visible area.
- Carry active/blanking metadata alongside registered RGB stages instead of
  guessing delay taps later.
- Keep line-buffer addresses aligned with the RGB sample they describe.
- Put status overlays between the native core RGB output and `video_mixer`.
  This keeps coordinates in native resolution and lets MiSTer scale the result.
- Keep overlay position, size, spacing, colors, and activity hold duration as
  compile-time parameters.
- The nominal active area is approximately 560 by 192. Leave a safe margin for
  displays that crop edges.
- Disk motor and disk transfer are different events:
  - `D1_ACTIVE` and `D2_ACTIVE` represent selected-drive motor state, including
    delayed spin-down.
  - `D1_IO_ACTIVE` and `D2_IO_ACTIVE` represent controller transfer accesses.
  - Host `sd_rd` and `sd_wr` represent image/track transfers, not Apple II byte
    reads and writes.

## Floppy Sound

The abandoned sound implementation generated a one-bit PWM carrier and fed it
into a sample-oriented audio bus. Its fixed `+22` mixer bias guaranteed a
nonzero PWM duty even while idle, causing constant background noise.

- Do not inject PWM into the 10-bit core audio sample path.
- Do not replace the Apple speaker signal with floppy sound.
- Generate a resettable sample contribution and mix it additively.
- The floppy sound sample must be exactly zero while disabled and after motor
  and click envelopes have stopped.
- Reusable concepts from the old implementation are:
  - phase-edge detection for head-step clicks;
  - an LFSR for low-level motor texture;
  - short, bounded decay envelopes.
- Unsafe concepts are:
  - a fixed nonzero output bias;
  - a permanently running PWM carrier;
  - unreset state;
  - treating a static Apple speaker level as a continuing sound event.
- Use wider intermediate arithmetic and saturation when adding floppy audio to
  the Apple speaker and Mockingboard samples. Narrow unsigned addition can wrap
  and create severe distortion.
- Validate at minimum:
  - disabled sound is digitally silent;
  - enabled but idle sound is digitally silent;
  - both drives produce motor and step sounds;
  - clicks decay to zero;
  - existing speaker and Mockingboard audio remain present;
  - mixed peaks saturate instead of wrapping.

## Enhancement Notes

- Keep rendering, event generation, and audio generation in separate modules.
  The drive overlay should not know Disk II controller internals, and the sound
  module should consume explicit motor/step/activity events.
- Prefer exact controller events over inferred activity. For example, export a
  one-cycle phase-step pulse from `disk_ii.vhd` rather than reconstructing it
  from unrelated top-level signals.
- Add read/write texture only after motor noise and step clicks are quiet and
  calibrated on hardware. Frequent byte-level events can easily become a
  constant buzz.
- Add abstractions only when they form a useful ownership boundary. The
  standalone drive overlay and floppy sound modules are justified because both
  are expected to grow independently.
- Preserve existing status bits when widening or reconstructing `status_in`.
  New OSD controls above bit 31 require a 64-bit status bus and correct upper
  slice forwarding.

## VHDL/Verilog Equivalence Verification (2026-08-29)

Per-module differential harnesses live in
`../Apple-II-Verilog_MiSTer/module_tests/<name>/` (GHDL golden vs Verilator
candidate, identical procedural stimulus, cycle-by-cycle CSV comparison,
coverage gates, `-CompareOnly` recheck). The roster is
`module_tests/README.md`; the crash-recovery plan is
`E:\MiSTer\Apple-II_FPGAdev\subagent_plan.md`.

### Results so far

- PASS: disk_ii, dpram, virtual_keyboard_overlay, video_generator,
  timing_generator (NTSC+PAL, VBLANK low/high ratio gate 2.743/1.600 proves
  the 511->V_RESET wrap), keyboard, hdd (rows=6416 fields=102387
  gate_checks=63).
- DIVERGENCE (expected, real RTL difference): `apple2_font_rom` — on every
  new!=old ioctl write cycle, `glyph_data` differs for that one cycle:
  golden shows the NEW value (continuous assign from write-first `q` in
  spram), candidate shows the PRE-WRITE value (registered
  `glyph_data <= font_rom[rom_addr]` reads pre-edge memory). 36/37 writes
  diverge exactly one cycle; all 38,052 other fields match; 64/64 readbacks
  ok. One-line candidate fix pending user decision:
  `glyph_data <= ioctl_wr ? ioctl_data : font_rom[rom_addr];`
- `vga_controller` — two real differences confirmed by inspection (harness
  in progress): (1) palette download beat 4: golden latches
  `BUFFER_COLx <= palette_rgb_in` (OLD value = {d0,d1,d2}) while the
  candidate latches `{palette_rgb_in[23:8], ioctl_data}` (NEW value =
  {d0,d1,d3}); (2) the candidate wraps `color_addr` after beat 2
  (`color_addr < 2'b10`) = 3 beats/color, the golden after beat 3
  (`color_addr < "11"`) = 4 beats/color — under the documented 4-beat host
  protocol the candidate palette is shifted one beat from color 1 on.
  The `timing_active_delay` chains are NOT a difference: golden
  `s(0 to 13) <= s(1 to 13) & x` is a true 14-stage shift (input enters
  index 13, exits index 0) and both sides yield raw_active(n-15).
- via6522: PASS (built by a separate agent session 2026-08-29).
- CPU work (t65/R65C02) DEFERRED per user: both Verilog CPUs stay wired in
  `apple2.v` (T65=cpu 0, R65C02=cpu 1); full-core apple2 equivalence is
  unattainable until the CPU pair is certified (known T65/t65 boot
  divergence at cycle 358).

### GHDL 6.0.0 quirks (all verified with minimal repros)

1. Shorthand entity instantiation `x : work.foo` is rejected — generate a
   parse-normalized golden copy adding the explicit `entity` keyword.
2. `to_hstring` pads to the full nibble width — match with zero-padded %0NX
   in the Verilog CSV writer.
3. NO hierarchical instance selection at all — trace PORTS ONLY.
4. NO `--generic` option on -e/-r — multi-phase harnesses need generated TB
   copies with different generic defaults in separate workdirs.
5. STRICT case coverage: a case on std_logic_vector/unsigned must cover
   every value of the base range (std_logic has 15 values 'U'..'-');
   Quartus is lenient. Convert vector cases to
   `case to_integer(<expr>)` with integer choices in the golden copy
   (behavior-identical; hdd and vga_controller golden copies use this).
6. Array element access with computed indices (to_integer) is broken:
   two processes both accessing one array with computed indices lose the
   writes entirely; in one process, any second element access (even a plain
   `buf(0)` read) makes computed-index reads stale. A single process whose
   accesses are ALL computed-index works (the hdd golden copy merges
   sec_storage into cpu_interface on this basis). `to_integer(U)` returns 0
   with a metavalue warning (no exception).
7. `end process <label>;` for an UNLABELED process is rejected — strip the
   end label in the golden copy (vga_controller has 4).
8. File objects: `file f : text open write_mode is NAME;` (NAME a constant)
   at declaration; no open/close statements; a variable named `line`
   collides with the textio type.

### PowerShell 5.1 traps (harness scripts)

- `[Math]::BitAnd` does not exist — use the `-band` operator.
- `[int]1.5` rounds to 2 (round-to-even) — use `[Math]::Floor` before
  shifting (a flaky `($i/2)%2` produced a write address with the wrong
  bit position and a confusing readback failure).
- Inside double-quoted strings, `$var:` parses as a drive reference —
  write `$($var):`.
- `$((x + $y))` — the inner variable needs its `$`.
- `$obj.$var` (dynamic member) is valid in expression context only.
- Integer division `/` returns a double when not exact — cast at the use
  site; parameter typed `[int]` converts (truncates) automatically.

### VHDL notes

- `s(0 to 13) <= s(1 to 13) & x` IS a true shift chain (input enters index
  13, propagates toward 0) — verified empirically; do not "simplify" it.
- In a clocked process, the last assignment to a signal in the same delta
  wins (golden vga_controller assigns `ioctl_wait <= '1'` then `'0'` in the
  same cycle -> net '0').
- Metavalue arithmetic: U+1 = U (counters stay U until a reset path
  executes) — vga_controller schedules active lines BEFORE the 40-VBL
  stretch so the golden's U vcount resets to 0 and VGA_VS can assert at
  vcount 33/36.
- A module with no reset port: the first trace sample (posedge+1ns) is
  already post-edge, so initial-state metavalue runs are shorter than
  expected (apple2_font_rom had 0 ignored metavalue fields, not 1).

### Harness etiquette

- `module_tests/README.md` is co-edited by concurrent agent sessions —
  re-read it immediately before editing (an edit can fail on an
  externally changed line).
- Never modify RTL in either repo; golden-copy transformations are
  strictly-verified string replacements (occurrence counts + length
  check) and must be behavior-identical.
- A divergence matching the plan's predicted signature is a SUCCESS for the
  harness: report first-divergence + full characterization, do not fix RTL.

## NSC (No-Slot Clock) port — 2026-08

### Verilator build quirks (MSYS2 ucrt64, v5.050 rev vUNKNOWN-built20260702)

- Tasks MUST be closed with an explicit `endtask`. `task ... ; ... end`
  fails with "syntax error, unexpected end" in this build (empty or not);
  `task void` is also rejected. Functions with `endfunction` are fine.
  (Found via minimal repros while building the NSC unit TB.)
- Standalone executable builds need `--binary` (plain invocation + manual
  make no longer works). Set `VERILATOR_ROOT=C:/msys64/ucrt64/share/verilator`
  or verilator looks for verilated_std.sv at a mangled mixed-separator path.
- Working pattern:
  `"C:/msys64/ucrt64/bin/verilator_bin.exe" --timing --binary -Wno-fatal \
   -Wno-lint --top-module tb -o v_tb tb.sv dut.sv`

### Hex-literal bit order (serial protocol comparison)

- When comparing a serial bit stream to a hex constant, write the bytes out
  explicitly from bit 0 up. The RIGHTMOST byte of `64'h5CA33AC55CA33AC5` is
  0xC5 = bits[7:0]. An earlier read assumed bits[7:0] were 0x5C and nearly
  flagged a false unlock-pattern mismatch between the stock NSC driver and
  AppleTini's module (they in fact match exactly).

### Stock NSC driver protocol (verified from SMT NS.CLOCK.SYSTEM source)

- Probe order: slot 3 ($C3xx) first, then slots 1,2,4,5,6,7, then internal
  $C8xx. Unlock writes go to base+{0,1} (A2=0, A0 = data bit); read-out at
  base+4 (A2=1), data bit in bit 0 of the read byte.
- Driver's byte table is read BACKWARDS (`DSUnlk = * - 1`, `ldx #8`, X counts
  down) → bytes written are C5,3A,A3,5C x2, LSB-first per byte — identical to
  bits 0..63 of 64'h5CA33AC55CA33AC5.
- Re-unlock is required after every 64-bit read-out (register disables itself).

### AppleTini no_slot_clock FSM notes

- `UPDATE_PUB` holding itself until the centisecond tick counter wraps again
  is INTENTIONAL pacing (one carry evaluation per tick window), not a
  stuck-state bug. Do not "fix" it.
- INC_HOUR is correct 24-hour logic: x9→x+1:00 only increments hour_hi
  (no day rollover); only 23→00 takes INC_DAY.

### Pre-existing clock_card.v bugs (superseded by nsc_ticker.sv)

- Hour wrap condition `HOURS_ONES==9 || (HOURS_ONES==3 && HOURS_TENS==2)`
  also wrapped at 09→10 and 19→20, advancing the DATE three times per day.
- No month-length handling: days ran past 31/30/28 into invalid values.
- nsc_ticker.sv fixes both (wrap only at 23→00; month lengths + leap year).

### Core address decode facts needed for slot ROM-window peripherals

- $C1xx,$C2xx,$C4xx-$C7FF → ioselect(n) when CXROM=0 (default).
- $C3xx → motherboard ROM shadow unless C3ROM soft switch is set (default 0).
- $C8xx-$CFFF → IO_STROBE when CXROM=C8ROM=0; a read of $C3xx while C3ROM=0
  sets C8ROM=1 (existing coupling quirk).
- $Dxxx → all motherboard ROM in this core (no D-range slot IO mirror).
- PHASE_ZERO_R (PHI0_EN_R) is the established "sample bus once per CPU
  access" strobe (see softswitches process); use it for level-held selects.
