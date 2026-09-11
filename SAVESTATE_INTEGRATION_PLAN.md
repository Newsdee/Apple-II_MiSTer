# Production Save-State Integration Plan

## Status

Save-state support is wired end-to-end in the MiSTer wrapper (manager, DDR, hotkeys, OSD page, feedback) and verified at the module level. Remaining: Quartus Analysis & Synthesis on the updated source, full compile, and hardware validation.

Completed 2026-09-10 (OSD integration, Phase 5):

- `rtl/savestate_ui.sv` (new): NES-style UI controller. Tracks `status[47:46]` slot selection (held while busy), converts the OSD `rG`/`rH` command-line pulses and F5/F6 hotkeys into one-cycle manager requests, latches op type + slot at request time, and reports results from `ss_done`/`ss_error` on the hps_io `info` bus. Drives `status_menumask` bit 7 (availability) and holds bit 8 at 0 (orphaned while the SDCard line is removed).
- `rtl/savestate_manager_l1b.sv`: additive `error_code[1:0]` output (1 rejected, 2 invalid/empty, 3 incompatible). No other behavior change; level-1b harness re-passed with new code assertions.
- `rtl/savestate_ddr_l1b.sv`: additive `slot_sel[1:0]` input; address = BASE_ADDR + slot*0x10000 beats (512 KiB stride).
- `Apple-II.sv`: `Save States` OSD page (P5) after the Virtual keyboard page; `I,` info-string table; `status_menumask`/`info_req`/`info` connected on `hps_io`; `status_in` forces bit 45 (SD persistence) low with a one-shot startup clear; hotkey requests routed through the UI; `savestate_ui.sv` registered in `files.qip` and `Apple-II.qsf`.
- Validation: `L1B MANAGER PASS` (with error-code checks) and new `L1B UI PASS` (level-1b `ui` target); full wrapper Verilator lint clean (73 modules; framework-only pre-existing noise suppressed, VHDL/PLL stubs for that lint in `tools/lint_stubs_vhdl.v`).

Verified as of 2026-09-09:

- The focused manager harness in [Apple-II-Verilog_MiSTer/unit_tests/level_1b/tb_ss_manager.sv](../Apple-II-Verilog_MiSTer/unit_tests/level_1b/tb_ss_manager.sv) passes with fresh output:
  - `L1B MANAGER PASS save_writes=16411 load_reads=16397 ram_bytes=131072`
- This includes the manager-side `allow_save_state` rejection case and the 128 KiB RAM payload checks.
- The manager path is therefore proven for the atomic save/load sequence and the Saturn-disabled rejection policy at the coordinator level.
- The production wrapper now connects the manager to `apple2_top`, main/auxiliary RAM, and the MiSTer DDRAM port for the interim F5-load/F6-save slot-0 path.
- Quartus Analysis & Synthesis completed successfully on 2026-09-09 with 24,514 registers and 3,129,636 block-memory bits; the video ROM remains inferred as block memory.
- Remaining production gates are: full MiSTer OSD/key exposure, final core/smoke validation, and Quartus fit/timing/RBF reporting. The interim wrapper and DDR wiring are complete for slot 0.

Reference design: `MiSTer-devel/NES_MiSTer`, especially `NES.sv` and `rtl/savestate_ui.sv`.

## Interim Product Decision

Add four volatile DDR save-state slots with a small OSD integration before SD-card persistence:

- F5 loads the slot selected in the OSD;
- F6 saves the slot selected in the OSD;
- slots 1 through 4 map to internal slot indexes 0 through 3;
- each slot occupies 512 KiB within the existing 2 MiB `SS3E000000:200000` reservation;
- the OSD provides slot selection plus Save and Restore commands;
- the OSD shows the NES-style `Savestates to SDCard` option, but it is permanently disabled, visibly gray, and forced Off;
- successful completion reports `State N saved` or `State N loaded`; rejected and failed operations report an error instead of success.

Place a new `Save States` page immediately after the existing Virtual keyboard/joystick controls page in `CONF_STR`, so it appears directly below that page in the top-level OSD ordering. Use the same functional menu set as the NES core, with Apple-specific hotkey labels while the interim F5/F6 mapping remains active:

```text
Savestates to SDCard,Off,On     (disabled and forced Off)
Savestate Slot,1,2,3,4
Save state(F6)
Restore state(F5)
```

The current `hps_io.sv` supports both required mechanisms: `status_menumask[15:0]` for disabled entries and `info_req/info` for indexed OSD messages. Reserve one menu-mask bit that is always zero for `Savestates to SDCard`, and a separate availability bit for the slot selector and Save/Restore commands. The availability bit is true only when Saturn is disabled and no reset, download, or save-state transaction is active.

### Final status allocation (audit completed 2026-09-10)

The ND miosd fork (and upstream) maps uppercase - target firmware **v260823** (Release 20260823, `dfb4791`; confirmed on the user's hardware 2026-09-11) verified to have ALL of it: the 2022 128-bit status rework incl. d/h gating (`26e1ccc`) and a byte-identical 4-slot `process_ss` (local `Main_MiSTer` tree is `f8dc68e`, one release newer) `O` options to status bits 0-31 and lowercase `o` options to the same hex digit **plus 32** (bits 32-63); two hex digits form a contiguous range (first digit must be the lower bit). Command lines use `r`/`R` + bit: miosd pulses the bit high-then-low when the user selects the line. `H`/`h`/`D`/`d` flag + a bit read the core's `status_menumask` to hide/gray a line - **the flag must be FIRST on the line, before the `P<page>` token** (e.g. `d8P5oD,...`, `H8P5,...`); it is NOT consumed after the page token (verified in `Main_MiSTer/menu.cpp`: both parse passes run the d/h loop before the `P` check, and `user_io_hd_mask` takes the bit from the character after the flag; confirmed by shipping NES usage `d6P1O5` / `d7rA` / `H8P5`). A misplaced flag (e.g. `P5d8oD`) is silently dropped by the render pass (unknown option type `d` -> no line written, no entry counted) while the selection pass still counts the line as an entry -> every following line on the page is off by one: its toggle/status binding shifts to the wrong confstr entry (hardware: P5 slot selector "stuck at 1" with the malformed line present - woz06 and woz08 stuck, woz07 without any d flag worked; woz09 with the line removed: slot cycling confirmed on hardware - incident closed). The 2026-09-10 conclusion "miosd version / mishandles d prefix" was wrong: the feature exists, the token position was simply invalid. Info strings are the comma-separated fields of the CONF_STR line starting with `I,` (field 0 is the marker); miosd polls `info` (register 0x36, read-and-clear) and toasts field N when the core pulses `info_req` with index N.

Full bitmap audit of `Apple-II.sv` (word 0 = bits 0-31, word 1 = bits 32-63):

| Bits | Option | Usage |
|---|---|---|
| 0 | R0 | reset |
| 4 | P2O4 | color sharpness |
| 5 | P1O5 | CPU select |
| 6 | P3O6 | analog X/Y swap |
| 7-8 | P2O78 | stereo mix |
| 9-11 | P2O9B | scandoubler fx |
| 12-13 | P2OCD | aspect ratio |
| 14-15 | P2OEF | scale |
| 16 | P2OG | pixel clock |
| 17-18 | P3OHI | paddle as analog |
| 19-20 | OJK | display mode |
| 21 | P2OL | lo-res text |
| 22 | P1OM | PAL |
| 23 | P1ON | video ROM |
| 24-25 | OOP | color palette |
| 26-27 | OQR | write protect |
| 28-29 | P3OST | slot 4 |
| 30-31 | P3OUV | slot 5 |
| 32 | P2o0 | NTSC vertical blend |
| 33-34 | P3o12 | disk drive sound |
| 35 | P3o3 | disk LED overlay |
| 36-38 | P3o46 | analog X center |
| 39 | P3o7 | joystick mode |
| 40-41 | P4o89 | keypad visibility |
| 42 | P4oA | virtual keyboard |
| 43 | P4oB | joystick to keys |
| 44 | P1oC | **pause when OSD is open** (conflicts with the old tentative bit 44) |
| **45** | P5oD (REMOVED 2026-09-11) | Savestates to SDCard - line removed (the misplaced `P5d8oD` flag broke the slot selector on any miosd); bit stays reserved, `status_in` forces it low; re-add as `d8P5oD` (flag first) once a patched miosd runs |
| **46-47** | **P5oEF (new)** | Savestate Slot, 1-4 (index 0-3) |
| **48** | **P5 rG (new)** | Save state (F6) command line, un-gated (diagnostic strip `61e33d8`; `savestate_ui` still drives menumask bit 7 = allow_ss so a correctly-placed `d7` prefix can be restored later) |
| **49** | **P5 rH (new)** | Restore state (F5) command line, un-gated (same as rG) |

Free after allocation: word 0 bits 1-3, 10; word 1 bit 37 and bits 50-63.

`status_in` preserves every field and forces bit 45 low; a one-shot `status_set` pulse 16 cycles after reset clears a stale bit-45 from an old configuration. Command lines are pulsed by miosd (high-then-low on selection) and edge-detected in `savestate_ui`; they are not serialized.

Latch the selected slot when the manager accepts either a keyboard or OSD request. The active DDR address is:

```text
slot base = 29'h07C00000 + (selected_slot * 29'h00010000)
```

Changing the OSD selector while busy must not redirect an active transfer. The manager or bridge must expose the latched slot for feedback so the completion message names the slot actually used, not a newly selected slot.

**Implementation note (2026-09-10):** the latching lives in `savestate_ui` (`ss_slot` tracks the OSD selector only while `!ss_busy`; it feeds both the request latch and the DDR bridge), and the completion message uses the op/slot latched at request time. `DDRAM_ADDR` is in **64-bit beat** units (verified against Sorgelig's own comments in the NES `ddram.sv` and `arcade_video.v`: `0x06000000` beats = 0x30000000 bytes, `0x04800000` beats = 0x24000000 bytes), so `0x07C00000` beats is exactly byte `0x3E000000` - the advertised SS region.

The NES UI already demonstrates `info_req/info`, but its save/load message is request-oriented. Apple should improve this by generating the final message from `ss_done` and `ss_error`: latch operation type and slot at acceptance, then report success only when the manager completes without error. Include distinct messages for save success, load success, unavailable/rejected, invalid or empty slot, and incompatible CPU/header.

### Deferred NES-Control Parity

After the interim OSD path is proven:

1. Adapt the NES `savestate_ui.sv` keyboard controls: F1-F4 load and Alt+F1-F4 save.
2. Move the Apple reset shortcut from F2 to F5 when the F1-F4 mapping is enabled.
3. Add the NES-style gamepad modifier, left/right slot selection, and Start+Up/Down load/save chords.
4. Allow keyboard or gamepad slot changes to update `status[46:45]` through the composed `status_in/status_set` path.
5. Implement standard MiSTer Main SD persistence, then re-add the SDCard OSD option (correct `d8P5oD` form) and add the compatible size/generation header behavior.

Until that later phase, save states remain volatile across core reload or power-off.

**SD-persistence mechanics (verified in the miosd source, 2026-09-11; supersedes the 2026-09-10 note):** two local miosd trees checked — `Main_MiSTer` (upstream) and `Main_MiSTer_ND` (ND fork) at the workspace root.
- Header parse (upstream `user_io.cpp` `parse_config`, confstr field 1): `SS<base>:<size>` sets `ss_base`/`ss_size`; base must be in [0x20000000, 0x40000000) and base+size < 0x40000000. Our `SS3E000000:200000` passes.
- Trigger: `process_ss(name)` runs only when `ss_base && opensave` (`user_io.cpp:2198`). `opensave` is set in the confstr page parse (`menu.cpp` ~line 1995) **only for F lines with the `FS` prefix** (`F0` = plain load, `FS<n>` = load + opensave, `FC<n>` = load + store-name). **S lines (SD image mounts) never set it.** Our core has S0/S1/S2 and no F lines, so on EITHER stock build `process_ss` never fires and no `.ss` file I/O happens at all. The 09-10 note's "S flag in the file option (e.g. NES `FS,NESFDSNSF;`)" was exactly this FS prefix, misattributed to the SS header. (The 09-10 claim that miosd "writes 0xFFFFFFFF into the first DWORD of each slot" is also wrong: upstream memsets the whole region to 0 and sets the first DWORD to 1 after a file load.)
- Upstream `process_ss` (`user_io.cpp:1933`): on mount — for each of 4 slots at base+i*ss_size: zero `ss_size`, load `<game>_<i+1>.ss` into the slot (slot 0 also falls back to `<game>.ss`), first DWORD := 1. Polling (1 s timer): per mapped slot, if first DWORD != stored counter -> write the first `(second DWORD + 2)*4` bytes of the slot to `<game>_<i+1>.ss`; skipped when second DWORD == 0 or the byte size > ss_size. miosd shows a "Saving the state" info toast on write-back.
- ND fork `process_ss` (`Main_MiSTer_ND/user_io.cpp:1650`): legacy GBA-only variant — hardcoded base 0x3E000000, zeroes 16 x 1 MiB, loads one file (<= 1 MiB) into the first slot region, trigger `curcnt > ss_cnt` (monotonic), write-back capped at 512 KiB.
- Files: `<storage>/savestates/Apple-II/<basename>_<1-4>.ss` (CoreName = confstr field 0). Basename derivation (verified, `FileGenerateSavestatePath`, `file_io.cpp:808`): take the component after the last `/`, strip from the LAST `.` to end of name, append `_1..4.ss` (slot 0 additionally READS the legacy `<game>.ss` on load; writes are always `_1..4.ss`). Spaces, case, and extra dots in the name are preserved (only the final extension is cut). A file with no dot at all would be UB in that function - the OSD file browser always presents an extension, so this does not occur.
- Extension matrix (2026-09-11): standard `Apple-II.sv` S0/S2 = `.nib .dsk .do .po` (upstream-inherited list, sorgelig ef40bc8 2019), S1 = `.hdv`; woz `Apple-II_woz.sv` S0/S2 = `.woz` only, S1 = `.hdv` (both builds already expose `.hdv` on S1 - nothing to add; the shared S-line miosd patch covers S0/S1/S2 identically, so an .hdv mount triggers the same persistence). ROADMAP (user, 2026-09-11): the woz build will eventually also load `.dsk`/`.nib`/other formats, so the S-line filter lists grow toward the union {.nib,.dsk,.do,.po,.woz,.hdv}.
- **dsk->woz for the woz build (design 2026-09-11, FINAL):** miosd cannot see core build dates (RBF is opaque) - version flag = CONFSTR FEATURE LENGTH (user decision 2026-09-11). The new standard (woz-based) build will carry many more OSD/media features, so its confstr will be far larger than any old-generation build; the miosd patch gates the conversion on that. Mechanism (source-verified in v260823 `dfb4791`): `user_io_read_confstr()` reads register 0x14 until the first NUL into `static char cfgstr[1024*10]` (10 KiB - no saturation risk), so the patch (lives in user_io.cpp, where cfgstr is file-static) counts the `;`-separated fields (cheapest: count ';' in the file-static cfgstr, or the `user_io_get_confstr(n)` loop) - field count = feature count, robust to label text changes. Size ladder (measured 2026-09-11, fields = ; segments): latest RELEASE (20260603, commit `79f8209`, `releases/Apple-II_20260603.rbf`) = 45 fields / 901 bytes; current dev builds = standard 68 / 1778, woz 67 / 1725. The standard build is NOT the old build - it is already ahead of the latest release (savestate P5 page, virtual keyboard, etc. roughly double the confstr vs 901 B); the future woz-as-standard build will be larger still. Threshold: the cutoff must sit ABOVE the max of all pre-new builds (68 fields today - a lower cutoff, e.g. 55, would fire on the current standard build and hijack its working .dsk flow into .woz, which that build cannot consume) and BELOW the delivered new build's field count (measure at delivery; pick the midpoint). Gate at the mount-classification site (user_io.cpp ~2180): `a2_core && fields > 68 && dsk_ext` -> dsk->woz conversion hook beside `iigs_mount`, reusing the conversion machinery ALREADY in v260823 (PR #1011 `5ee7f9e` 2025-07-30, PR #1216 `f8a198e` 2026-06-15 - both ancestors of `dfb4791`: iigs_fmt/dsk2nib_lib/in-memory WOZ buffer/write-back). Pre-new builds (the release generation AND the current dev builds - all short confstr, and none able to consume .woz) keep the working `SD_TYPE_A2`/dsk2nib .dsk flow byte-for-byte unchanged - backward compat by construction. Upstream's locked decisions fit: native .woz byte-for-byte (copy protection), on-the-fly translation, no temp files. Rejected alternatives (recorded): (1) core rename `Apple-II-Woz` - user rejected: a new confstr name loses the existing miosd configs/savestates keyed by name; (2) runtime status bit in `status_in` (NES `increaseSSHeaderCount` idiom; hps_io 0x29 `status_req` readback via `check_status_change()` resync; bit 9 NOT free - `status[11:9]` field; first free bit 52) - superseded: the length flag is simpler, needs zero new RTL logic, and grows with the features for free; (3) confstr field-1 capability token - parse_config (user_io.cpp:700) advances ONLY via commas, so an unknown token as the LAST comma-separated element INFINITE-LOOPS stock miosd at boot (traced); only a MID-field token is safely skipped - fragile; (4) dedicated marker confstr field - the i>=2 parser is a pure prefix if-chain (unknown types fall through as no-op, verified inert in v260823) so it would work, but unnecessary once length is the flag. Note: with the name unchanged, standard and woz builds share `savestates/Apple-II/`; if the .ss layouts ever diverge, bump the manager's version byte so the load check rejects foreign states cleanly.
- Persistence is FORMAT-INDEPENDENT by construction: the .ss contents are machine state (CPU/RAM/PPU/Disk II controller + savestate register state) with no disk-format knowledge; the miosd patch and the core protocol words (items 2/3 above) never inspect the media format. The only format-dependent piece is the S-line confstr extension list (OSD browser filter) - a future confstr edit, not a persistence input. Cross-format name sharing is benign/desirable: `disk.nib` and `disk.woz` map to the same `disk_N.ss` (same logical disk -> shared state).
- NES precedent (local copy `NES_MiSTer/NES.sv` lines 71-72): header `NES;SS3E000000:200000,UART31250,MIDI;` + line `FS,NESFDSNSF;` (F-line with FS prefix -> opensave=1; exts .nes/.fds/.nsf) and NO S-lines — the game arrives via miosd file transfer. It also wires `.increaseSSHeaderCount(!status[44])`: a dedicated OSD line that increments the header count word, i.e. the user-toggled variant of the changing-first-DWORD protocol (our design auto-increments per save instead).

**What is missing for SD-card persistence (checklist, 2026-09-11):**
1. **miosd patch — the real blocker.** Neither stock build calls `process_ss` on an S-line (SD media) mount. Minimal upstream patch: set `opensave=1` for S lines too in the `menu.cpp` page parse (or add a distinct prefix, e.g. `SS0`, so only opted-in cores persist). The ND fork additionally needs the upstream 4-slot `process_ss` backported (or accept single-slot / <= 512 KiB / monotonic-counter behavior). The user must build + flash miosd. **Target RESOLVED 2026-09-11: v260823 (Release 20260823, `dfb4791`)** - verified to carry the modern 4-slot `process_ss` (byte-identical to the newer release), the `opensave`/`FS` mechanism, and d/h gating (a 2022 feature); the patch is exactly the S-line `opensave` trigger, no backport of anything. **v260823 patch spec (3 parts, ~6 lines, all stock idiom):** (a) new predicate in `user_io.cpp` modeled on `is_snes()`: `static int is_apple2_type = 0; char is_apple2() { if (!is_apple2_type) is_apple2_type = strcasecmp(orig_name, "Apple-II") ? 2 : 1; return (is_apple2_type == 1); }` - `orig_name` is confstr field 0, read at runtime by `user_io_read_core_name()`, and both the standard and woz builds report "Apple-II"; (b) declaration `char is_apple2();` in `user_io.h`; (c) at the S-line pick path `user_io.cpp:1006` (generic `else` branch), beside `user_io_file_mount(str, idx)`: `if (ss_base && is_apple2()) process_ss(str);` (`str` = media filename, `idx` = drive slot), plus `is_apple2_type = 0;` in the `user_io_read_core_name()` reset block. Core-name gating (miosd's stock per-core idiom - `is_snes`/`is_gba`/`is_minimig` and ~20 others) makes the patch fully inert on every other core; `ss_base` alone is only a soft gate (any core that declares an SS header). Not an F-line: F-line picks are one-shot file DOWNLOADS (`user_io_set_download`) - the NES/GBA ROM-copy transport, incompatible with our image-channel media (random access + write-back + .hdv size); a dummy F-line to fire `process_ss` would mis-name the .ss files (basename = dummy), DMA the dummy into core DDR, and re-zero all four slots on every pick.
2. **Manager protocol words (core RTL; can land now, inert without #1).** Slot word 0 must carry the protocol pair: first DWORD (bits 31:0) = changing per-save counter, second DWORD (bits 63:32) = used size in DWORD units. Today word 0 = `{MAGIC, 1, 0, USED_WORDS}`: the counter half is the static `0x00014000` (never changes -> no repeat write-back) and the size half = MAGIC -> `(size+2)*4` ~ 4.4 GiB > ss_size -> EVERY write-back would be skipped. Move MAGIC/version/CPU into slot word 1 and make `LOAD_HEADER1` a masked check (word 0: size field valid, counter ignored; word 1: magic + version + CPU).
3. **Counter-init edge.** miosd stores counter = 1 after loading a `.ss` file at mount. A core counter starting at 0 -> first save writes 1 -> `1 != 1` / `1 > 1` both false -> the first save would silently not persist. Scheme: 32-bit counter, init 1, pre-increment per save (first save = 2); safe under both `!=` (upstream) and `>` (ND) semantics.
4. **Slot stride = `ss_size`** — DONE 2026-09-11 (`savestate_ddr_l1b.sv`, 2 MiB = `:200000`; main-repo commit d798282).
5. **P5 "Savestates to SDCard" line - REMOVED 2026-09-11.** The line was removed from both wrappers: the misplaced `P5d8oD` flag broke the P5 slot selector on ANY miosd (grammar note above), and the grayed-out informational value was not worth the risk. Persistence is unconditional per mount once #1 lands. Note: v260823 already supports the d/h flag (2022 feature), so the line COULD be re-added now in the correct `d8P5oD` form (flag first) if the user wants the visible-grayed state back - optional; preferable to bundle it with a future compile. Alternatively wire a live status bit for an on/off switch in the patched miosd. `savestate_ui` keeps driving menumask bit 8 = 0 (orphaned, harmless).
6. **Validation.** TB: counter increments per save; size DWORD correct; masked load accepts differing counters and rejects `0xFFFFFFFF`/bad size. Hardware (patched miosd only): save -> `<game>_N.ss` appears (~128 KiB) and miosd toasts "Saving the state" ~1 s later; power-cycle -> file reloads at mount -> restore works; disk swap -> per-game files.
7. **Edge cases (document on enable):** ~1 s loss window before power-off (1 s poll); every mount zeroes all 4 slots (states are per-game); up to 4 x <= 2 MiB files per game. With two drives mounted (and once the woz build mixes formats across drives), the .ss basename follows the LAST-mounted media file (process_ss re-fires on every S-line mount: re-zero + reload).

## Agreed Scope

Save and restore only the base Apple IIe machine:

- selected CPU, including in-flight instruction and bus state;
- 64 KiB main RAM from `ram0[18'h00000:18'h0FFFF]`;
- 64 KiB auxiliary RAM from `ram1[16'h0000:16'hFFFF]`;
- Apple II soft switches, language-card state, data-path latches, speaker state, and machine timing/video pipeline state;
- wrapper state required for deterministic continuation, after explicitly classifying each wrapper register;
- selected CPU type and compatibility fields required to reject an incompatible load.

ROM contents and registered ROM outputs are not serialized. A load always uses the ROM currently installed in the core, including a custom video ROM loaded through `ioctl`.

The RAM payload remains exactly 128 KiB. The existing 15-bit 64-bit-word slot address is sufficient because the current layout uses words 0 through 16415.

## Explicit Exclusions

Do not serialize these devices or their memories:

- Saturn 128 KiB RAM card and all `ramcard` control registers;
- Disk II controller, drives, track buffers, and mounted media;
- HDD controller, buffers, and mounted media;
- Mockingboard;
- mouse cards;
- Super Serial Card;
- clock card and RTC;
- keyboard decoder, PS/2 transient state, and virtual-keyboard state;
- joystick, paddle, and gameport transient state;
- tape input;
- MiSTer OSD and framework state.

These devices remain live across a base-machine restore. This is an intentional v1 limitation. Software actively using an excluded peripheral is not guaranteed to resume coherently.

## Saturn Policy

Save states are unavailable whenever the Saturn card is installed in slot 5 (`saturn_5_inslot == 1`). This prevents capture of base RAM while omitting active expansion RAM and its bank-selection state.

Enforce this policy at three levels:

1. UI: pass an availability signal based on `!saturn_5_inslot`, no reset, and no active transaction to `savestate_ui`.
2. Menu: use `status_menumask` to disable or hide save/load entries while Saturn is installed.
3. Manager: reject save and load requests when Saturn is installed, even if a request bypasses the UI.

Prevent the Saturn configuration from changing during an active transaction. Prefer masking its OSD setting while busy. Independently latch the accepted Saturn-disabled condition and fail safely if it changes before completion.

A rejected command must provide MiSTer info feedback. It must not cold-reset or partially restore the machine.

## Ownership Boundaries

Keep responsibilities aligned with the current design:

- `Apple-II.sv`: MiSTer UI, status merging, slot selection, DDR bridge, save-state manager, and RAM arbitration.
- `rtl/apple2_top.v`: explicit machine-state forwarding, wrapper-owned machine state, `machine_ce`, and `cpu_frozen`.
- `rtl/apple2.v`, `rtl/timing_generator.v`, `rtl/video_generator.v`, and CPU modules: serialize only registers they own.
- `rtl/savestate_ui.sv`: NES-style keyboard, OSD, and optional gamepad command handling.

Do not use hierarchical references to inferred arrays or internal registers. Use explicit synthesizable ports. Keep MiSTer integration out of shared virtual-keyboard behavior modules.

## Phase 1: Reconcile and Harden the Engine

1. Promote the tested level-1b manager and DDR bridge into production-named RTL files.
2. Preserve the atomic sequence:
   - accept request;
   - wait for the selected CPU to reach a stable boundary;
   - freeze machine mutation through `machine_ce`;
   - wait for state to settle;
   - complete save or load transfers;
   - restore machine registers and CPU in the tested order;
   - resume execution.
3. Keep physical clocks running. Gate state mutation with enables rather than fabric-gated clocks.
4. Add Saturn availability input and manager-side rejection.
5. Validate the header before modifying live state:
   - magic;
   - format major and register-map revision;
   - used-word count;
   - selected CPU type;
   - required feature and memory-map bits.
6. Lock CPU selection and selected slot while busy.
7. Reject CPU-type mismatch without modifying RAM or registers.
8. Ensure reset cancels a transaction and releases the machine without applying a partial restore.

### State Ownership Audit

Before production wiring, classify every stateful register in these modules as serialized, derived, reset-on-load, external/peripheral, or irrelevant:

- `rtl/apple2.v`;
- `rtl/timing_generator.v`;
- `rtl/video_generator.v`;
- base-machine portions of `rtl/apple2_top.v`.

At minimum, review `flash_clk`, `power_on_reset`, reset pipeline state, speaker averaging state, pixel/video counters, and data latches. Paddle counters and excluded peripheral state must not be included merely because they live in `apple2_top.v`.

Document register-map changes and increment the format ABI for incompatible changes.

## Phase 2: Expose the Machine Boundary

Add explicit save-state ports to `apple2_top` and forward them to the Apple II core:

- `ss_addr[9:0]`;
- `ss_wdata[63:0]`;
- `ss_wren`;
- `ss_rdata[63:0]`;
- `machine_ce`;
- `cpu_frozen`.

Replace the current inactive state-port tie-offs inside `apple2_top`. Combine save-state stall with existing OSD and HDD wait behavior without changing normal cycle timing while save states are idle.

Wrapper-owned register words must use addresses not owned by `apple2`, return zero for other addresses, and join the read bus without multiple drivers.

## Phase 3: Production RAM Arbitration

The physical arrays contain:

- `ram0[0x00000:0x0FFFF]`: main system RAM, included;
- `ram0[0x10000:0x2FFFF]`: Saturn expansion RAM, excluded;
- `ram1[0x0000:0xFFFF]`: auxiliary system RAM, included.

Implement an explicit save-state RAM client in `Apple-II.sv`:

- bank 0 maps only to the low 64 KiB of `ram0`;
- bank 1 maps to `ram1`;
- no save-state address may reach Saturn RAM;
- save reads honor the inferred arrays' synchronous read latency;
- load writes pulse for exactly one clock per byte;
- reset has highest priority, followed by save-state load writes and then normal machine writes;
- normal RAM behavior remains unchanged while the manager is idle.

Add a simulation assertion proving that save-state accesses to `ram0` never select an address above `18'h0FFFF`.

## Phase 4: Four-Slot DDR Mapping

Advertise the standard MiSTer region in `CONF_STR`:

```systemverilog
"Apple-II;SS3E000000:200000,...;"
```

Use four fixed slots within the advertised SS region (4 x ss_size, 2 MiB each):

- framework byte base: `32'h3E000000`;
- direct 64-bit DDR base: `29'h07C00000`;
- slot stride: 2 MiB (matches the advertised `ss_size` = `0x200000`);
- direct slot stride: `29'h00040000` 64-bit beats;
- selected slot: 0 through 3;
- `DDRAM_BURSTCNT = 1`;
- `DDRAM_BE = 8'hFF`;
- one acknowledged 64-bit operation at a time.

The payload is approximately 128 KiB plus headers, well inside the 2 MiB slot stride. (The earlier draft's 512 KiB stride read `:200000` as the region total; the miosd source says `size` is per-slot - see the SD-persistence note above.)

Latch the selected slot when accepting a request. Changing the OSD selector while busy must not redirect an active transfer.

Add directed first/last-address tests for every slot and prove that ranges neither overlap nor exceed the declared region.

## Phase 5: Interim OSD and Feedback Integration

Keep `savestate_hotkeys.sv` responsible for consuming F5/F6 and forwarding all other filtered keyboard events. F5/F6 generate load/save requests for the currently selected OSD slot. Do not add Alt tracking or consume F1-F4 in this phase, so F2 remains the Apple reset shortcut.

Add the `Save States` OSD page after the existing Virtual keyboard/joystick page. Its slot selector, Save command, and Restore command use one availability mask; its `Savestates to SDCard` option uses an always-false mask so MiSTer renders it gray. Match the NES option names where behavior matches, but label the active Apple hotkeys accurately as F5/F6.

Connect `status_menumask`, `info_req`, and `info` explicitly on the `hps_io` instance. Add indexed strings to the `CONF_STR` information section for:

- active slot 1 through 4;
- state 1 through 4 saved;
- state 1 through 4 loaded;
- save states unavailable while Saturn is enabled;
- invalid or empty slot;
- incompatible save-state format or CPU.

Generate slot-selection feedback when the OSD selection changes. Generate operation results from manager completion, not merely from the request edge. `info_req` must return low between messages because `hps_io` captures its rising edge.

Audit the complete Apple II status bitmap before assigning final bits. Known conflicts prevent direct reuse of NES command bits:

- `status[42]`: virtual keyboard enable;
- `status[41:40]`: virtual keyboard transparency;
- `status[43]`: joystick-to-key enable.

Tentative allocation, subject to audit:

- `status[44]`: disabled SD-persistence setting, forced Off;
- `status[46:45]`: selected slot;
- `status[47]`: OSD Save command toggle;
- `status[48]`: OSD Restore command toggle.

Expose `Savestates to SDCard` only as a disabled preview in this phase. Do not connect it to state-machine behavior or imply that the direct-DDR region is persistent.

Compose rather than replace the existing `status_in` and `status_set` logic. Preserve every untouched upper and lower status field. Slot updates must coexist with video, palette, and virtual-keyboard updates in the same cycle using one combined next-status value and update pulse with explicit field-wise merging or priority.

Connect save-state information signals to `hps_io.info_req` and `hps_io.info`, arbitrating with any existing or later information sources.

Evaluate driving `HDMI_FREEZE` from the accepted transaction's freeze/busy state. It must not be used as the mechanism that freezes machine state.

## Phase 6: Availability and Error Behavior

Required behavior:

- Saturn off and manager idle: save-state controls enabled;
- Saturn on: controls disabled and commands manager-rejected with info feedback;
- busy: new commands ignored and slot/Saturn selection locked or safely latched;
- reset or download active: commands ignored;
- CPU mismatch or invalid header: load rejected before RAM or register writes;
- no valid state in a slot: load rejected without disturbing the machine.

## Validation Ladder

Run the narrowest applicable test immediately after each implementation slice.

1. Manager tests:
   - save/load ordering;
   - invalid header;
   - CPU mismatch;
   - Saturn rejection;
   - reset cancellation;
   - selected slot held while busy.
2. DDR bridge tests:
   - request/acknowledgement cooldown;
   - first/last address for all slots;
   - burst count and byte enables;
   - no overlap or out-of-range access;
   - selected slot remains latched while a transaction is busy.
3. OSD/UI tests:
   - slot values 1 through 4 select internal indexes 0 through 3;
   - F5/F6 and OSD Restore/Save commands use the selected slot;
   - each OSD command toggle generates exactly one request;
   - the SD-persistence entry is visible, gray, and cannot set `status[44]`;
   - Saturn, reset, download, and busy states disable the operational entries;
   - unrelated video, palette, and virtual-keyboard status bits survive OSD updates;
   - `info_req` pulses only after completion or rejection and returns low between messages;
   - success and error messages identify the latched operation and slot.
4. RAM tests:
   - exactly 65536 main and 65536 auxiliary bytes;
   - synchronous read latency;
   - byte-lane order;
   - no Saturn access;
   - unchanged normal path while idle.
5. Core differential test with save-state support idle to prove unchanged cycle behavior.
6. Save/load continuation scenarios for both 6502 and 65C02.
7. Full Verilator build and `--smoke-test`.
8. MiSTer wrapper lint and elaboration.
9. Quartus Analysis and Synthesis after source registration and interface wiring.
10. User-run full Quartus compile for fit, timing, and RBF generation.
11. Hardware tests covering all controls and slots, Saturn gating, repeated save/load, reset interactions, and expected non-restoration of peripherals.

Verilator does not prove FPGA timing, metastability safety, inferred-memory packing, or hardware signal quality. Report Quartus and hardware validation separately.

After every source edit:

```text
git diff --numstat
git diff --numstat --ignore-all-space
git diff --check
bash ../eol_guard.sh
```

Normal and whitespace-insensitive statistics must remain close. Preserve mixed line endings and avoid incidental `Apple-II.qsf` churn.

## Acceptance Gates

Production save states are complete only when:

- controls work through MiSTer OSD and keyboard;
- exactly 64 KiB main plus 64 KiB auxiliary RAM is serialized;
- Saturn RAM and controller state are never serialized;
- save/load is unavailable and manager-rejected while Saturn is enabled;
- invalid states cannot partially modify the machine;
- four slots map to non-overlapping DDR ranges;
- the `Save States` page appears below the virtual keyboard/joystick page;
- SD persistence is visibly disabled and remains Off;
- F5/F6 and OSD commands target the selected slot;
- success and failure feedback reflects manager completion;
- existing video, keyboard, virtual-keyboard, storage, and peripheral behavior is unchanged while idle;
- focused tests and full Verilator smoke pass;
- Quartus Analysis and Synthesis passes with no new correctness warnings;
- full compile and hardware status are reported explicitly.

## Implementation Order

1. Audit and freeze the production register map.
2. Harden manager policy and tests, including Saturn rejection.
3. Add four-slot DDR addressing and tests.
4. Add `apple2_top` state ports and idle-path equivalence validation.
5. Add production RAM arbitration and prove Saturn isolation.
6. Integrate manager and DDR in `Apple-II.sv`.
7. Integrate the interim four-slot OSD page, F5/F6 selected-slot behavior, status preservation, menu masks, and completion feedback.
8. Run full Verilator validation.
9. Register production sources and run Quartus Analysis and Synthesis.
10. Hand off the full compile and hardware checklist.
