# Joy-to-Key: repeat fix, bit-order fix, .a2k tooling — PROGRESS

Session: 2026-09-02/03. Target: the **newsdee** MiSTer RBF (user is testing that build).
Companion docs (feature design): `../Apple-II-Verilog_MiSTer/JOY_TO_KEY_PLAN.md`,
`../Apple-II-Verilog_MiSTer/JOY_TO_KEY_PROGRESS.md`.

This doc tracks the joy-to-key work across two rounds:
- **Round 1** (2026-09-02): the continuous-repeat bug + the `.a2k` file + editor tool.
- **Round 2** (2026-09-03): a hardware test exposed a **bit-order bug**; we also added
  two extra buttons (space/enter), moved the OSD option, added byte validation, and a
  CONF_STR map tool.

---

## 1. Bug A: continuous repeat after a joy key

**Symptom:** press a joystick button → one correct character, then the screen keeps
inserting *another* key continuously.

**Root cause:** in `rtl/keyboard.v` the joy branch sets `akd=1` (the "any key down"
C01X flag) but a synthetic joy key never produces a PS/2 key-up, so `akd` stays `1` and
the PS/2 auto-repeat engine re-asserts `key_pressed` every ~65 ms, streaming
`rom_out` (the last real key).

**Fix (both repos):** a joy key is a **one-shot**. Keep `akd=1` while pending (so C01X
delivers it), but clear `akd` the moment the OS reads it, and reset `rep_timer` on press:

```verilog
if (joy_key_press) begin
    joy_code_latched <= joy_key_code;
    joy_valid        <= 1'b1;
    key_pressed      <= 1'b1;
    akd              <= 1'b1;
    rep_timer        <= 23'd7000000;   // 0.5 s, like a real key-down
end
// Joy key is a one-shot: clear akd once read so the repeat engine stops.
if (reads == 1'b1 && joy_valid)
    akd <= 1'b0;
```

Safe because the OS reads **C000** (captures the joy code while `joy_valid=1`) *before*
**C01X** (which sets `reads` and clears `joy_valid`/`akd`). A held real PS/2 key still
repeats normally (its `akd` is set at key-down, cleared at key-up).

---

## 2. Bug B: directional mapping was reversed (found on hardware)

**Symptom (user, on the RBF):** Up→M, Down→J, Left→K (double), Right→I (double); fire1/2
→ U/O (no repeat). I.e. the D-pad letters were scrambled.

**Root cause (reviewer + code trace):** `joy_to_key.v` assumed `joy` bits 0–3 were
**up, down, left, right**, but `rtl/joystick_input.sv` drives them as
**right, left, down, up** (bit0=Right, bit1=Left, bit2=Down, bit3=Up; fire1=bit4,
fire2=bit5). The `DEF_MAP` and the comments/test all repeated the wrong assumption, so
the module test passed while the real wiring was scrambled.

**Fix (both repos):** corrected the bit order everywhere and set the default map to the
user's request (Up→I, Down→M, Left→J, Right→K, fire1→U, fire2→O):

| bit | button | default |
|---|---|---|
| 0 | right | 0x4B 'K' |
| 1 | left  | 0x4A 'J' |
| 2 | down  | 0x4D 'M' |
| 3 | up    | 0x49 'I' |
| 4 | fire1 | 0x55 'U' |
| 5 | fire2 | 0x4F 'O' |
| 6 | space | 0x00 (blank) |
| 7 | enter | 0x00 (blank) |

The module test now has a **Phase 0** that checks the default map after reset — the exact
check that would have caught this. The HTML editor and the test were corrected to the same
order. ("IJKM" is just the letter set; the user does not require a specific direction
assignment beyond the table above.)

---

## 3. Two extra buttons (space, enter)

`joy` is now **8 bits** (was 6). The two new gamepad buttons are `joy[6]` (space) and
`joy[7]` (enter), both **blank by default** and overridable from the `.a2k`. Enter is the
last button (bit 7). Files touched:
- `rtl/joy_to_key.v` (both repos): `joy` [5:0]→[7:0], edge detect + priority encoder over
  8 bits, `DEF_MAP[6]=DEF_MAP[7]=0`.
- `rtl/joystick_input.sv` (both repos): `joy` output [5:0]→[7:0]; the mask enables
  bits 6–7 always (like fire).
- `rtl/apple2_top.v` (verilog) / `rtl/apple2_top.vhd` (newsdee): `joy` port width → 8.
- `Apple-II.sv` (newsdee) `joyd`/`core_joyd` → [7:0]; `verilator/sim.v` `joyd` → [7:0].

The raw gameport (`joy[4]`/`joy[5]` → open/closed apple) is unchanged.

---

## 4. `.a2k` format (16 bytes) + byte validation

The `.a2k` is **exactly the 16-byte `joy_map` table** (no reserved tail). Byte *i* sets
button *i*; a byte of `0` = "no key".

**Validation (both repos):** a key code is 7-bit. A byte with **bit 7 set (>127)** is
invalid (corrupt / wrong file); the core stores `0` (no key) instead of the truncated low
7 bits, so a bad byte can't emit a random keystroke:

```verilog
joy_map[ioctl_addr[3:0]] <= (ioctl_data > 8'd127) ? 8'h00 : ioctl_data;
```

The `ioctl_addr < 16` guard remains as a safety net against an oversized file wrapping
`addr[3:0]` onto entries 0/1. The HTML editor applies the same rule on load (a >127 byte
shows as blank).

Default file (hex): `4B 4A 4D 49 55 4F 00 00 00 00 00 00 00 00 00 00`
(= K J M I U O, space/enter blank).

**Persistence (like the palette):** the table is initialized with power-up `initial`
values and has **no reset**, so a loaded `.a2k` survives a cold/warm reset. Only a full
power cycle restores the default. (This mirrors the `.a2p` palette, whose `BUFFER_COL*`
registers work the same way — which is why palettes are preserved.) Mounted disks behave
differently: they re-mount from the SD card on reset, whereas the joy map lives in FPGA
registers.

---

## 5. OSD: "Load Joy Map" moved to System & BIOS

The file slot is the global file **channel** (`F3` → `ioctl_index 3`, `JOYMAP_INDEX=3`),
which is independent of the menu page. So the item moved from `P3F3` (Hardware) to
**`P1F3`** (System & BIOS), one line below the virtual-keyboard options, with **no core
change** (channel stays 3). The "Joystick to keys" toggle (`P3oB`, status bit) stays in
Hardware, per the user.

```
"P1oA,Virtual keyboard,Off,On;",
"P1o89,Keypad visibility,100%,75%,50%,25%;",
"P1F3,A2K,Load Joy Map;",      // <- moved here (was P3F3)
"P1-;",
```

---

## 5b. Joy-to-key off while the virtual keyboard is on + file moved to osk/

**Gating:** when the "Virtual keyboard" toggle (`status[42]`) is on, joy-to-key is
disabled — the user is expected to type with the keyboard, so the joystick must not inject
keystrokes at the same time. Implemented in `Apple-II.sv`:

```verilog
.JOY_TO_KEY_EN(status[43] && !virtual_keyboard_enabled),   // virtual_keyboard_enabled = status[42]
```

The raw joystick (gameport) is unaffected — only the joy-to-key injection is gated. (There
was already a separate `core_joyd = virtual_keyboard_active ? 0 : joyd` that zeroes the raw
joy while the keyboard is on-screen; that stays.)

**File move:** `rtl/joy_to_key.v` → **`rtl/osk/joy_to_key.v`** (both repos), since it is
related to the on-screen keyboard. Build lists updated: `files.qip`, `Apple-II.qsf`
(newsdee), `verilator/Makefile` (verilog), and the `a2k_load_tb` build comment.

---

## 6. Tools

- **`a2k_editor.html`** (this project root): self-contained HTML+JS. Gamepad = D-pad
  (correct bit order) + fire1/2 + **extra1/space** + **extra2/enter**; click a button,
  click a key to assign. Filename box is above the Save/Load buttons (Reset to the right);
  the default name is `joy_map` (`.a2k` is added on save). "Save .a2k" downloads the
  16-byte file; "Load .a2k" applies the >127→blank rule. Default = K J M I U O,
  extra1/extra2 blank.
- **`confstr_map.py`** (this project root): parses the CONF_STR **and** extracts the
  core's real `status[N]` / file-slot usage from `Apple-II.sv`, printing every OSD entry,
  the file slots, and a **taken/free bit map** (the option-index→bit translation is done
  by the MiSTer OSD *software*, so the tool uses the core's actual bit usage as ground
  truth). Run: `python confstr_map.py`. Current result: taken bits `0,3-43`; free `1-2,44-63`.

---

## 7. Reviewer feedback — disposition

| item | status |
|---|---|
| **High:** directional order wrong | **Fixed** (§2) |
| **Medium:** simultaneous presses dropped | Known limitation — one edge/cycle; a diagonal sends the lower bit. Documented in `joy_to_key.v`; not queued (would need a queue). |
| **Medium:** cold reset erases loaded profile | **Fixed** — the `joy_map` table now uses power-up `initial` values + **no reset** (exactly like the `.a2p` palette's `BUFFER_COL*` in `vga_controller.v`), so a loaded profile survives cold/warm reset; only a full power cycle restores the default. |
| **Low:** profile load not atomic | Known — an interrupted/short file leaves a partial profile. Benign (reload fixes it). |
| **Low:** "inferred block RAM" comment wrong | **Fixed** — comment now says it synthesizes as registers. |
| **Low:** PS/2 + joy same-cycle, no queue | Known — both feed one latch in `keyboard.v`; same-cycle events can suppress each other. Rare at human speed. |

---

## 8. Validation (Verilator 5.050, MSYS2 UCRT64)

### `module_tests/joy_to_key/a2k_load_tb.sv` — **ALL PASS**
- **Phase 0** default map: right→K, left→J, down→M, up→I, fire1→U, fire2→O, space/enter blank.
- **Phase 1** load 16-byte `.a2k`: all 8 buttons emit their byte (incl. space 0x20, enter 0x0D).
- **Phase 2** oversized bytes 16/17 ignored by the guard (entries 0/1 intact).
- **Phase 3** invalid byte 0x85 (>127) → stored as 0 (no key).
- **Phase 4** loaded profile (all 'A') **survives a cold reset** (not restored to default).

### `module_tests/keyboard/joy_repeat_tb.sv` — **ALL PASS**
C1 joy key presented (K=0xC9, akd=1); C2 consumed (akd=0); C3 **zero** re-assertions over
~3 repeat periods. (Buggy build with the fix reverted: C2 akd=1, C3 = 3 → FAIL.)

### Full machine
`verilate.sh -j4` → clean (47 modules, no HDL width errors from the 8-bit change);
`Vemu --smoke-test` → **SMOKE PASS** (frames=6, keyboard open/close, reset, ioctl green).

### Git hygiene
newsdee + verilog: `git diff --numstat` equals `--ignore-all-space` numstat for every file
I touched (no EOL churn). `Apple-II.qsf` (269 ins) is the user's own change, untouched.

---

## 9. Checklist / status

- [x] Repeat bug (Bug A) fixed + validated (`keyboard.v`, both repos).
- [x] Bit-order bug (Bug B) fixed + validated (`joy_to_key.v`, `joystick_input.sv`, HTML, test).
- [x] Two extra buttons (space/enter) wired through `joy` [7:0] (both repos + wrappers).
- [x] `.a2k` = 16 bytes; byte >127 → 0 (both repos + HTML).
- [x] `.a2k` **persists across cold/warm reset** (palette-like: `initial` + no reset);
      validated by `a2k_load_tb` Phase 4.
- [x] OSD "Load Joy Map" moved to System & BIOS (`P1F3`, channel 3 unchanged).
- [x] Joy-to-key **disabled while the virtual keyboard is on** (`status[43] && !status[42]`).
- [x] `joy_to_key.v` moved to `rtl/osk/` (both repos) + build lists updated.
- [x] HTML: buttons renamed extra1/space + extra2/enter; filename above buttons; reset
      right-aligned; hex display reflowed; hint wording updated.
- [x] `a2k_editor.html` updated (bit order, space/enter, 16-byte, >127→blank).
- [x] `confstr_map.py` tool (CONF_STR + core bit/slot map).
- [x] Reviewer items: bit order, block-RAM comment fixed; rest documented.
- [x] Verilator: a2k load test, keyboard repeat test, full smoke test — all pass.
- [ ] **User:** rebuild newsdee RBF (Quartus full compile) with all the above, then test
      on hardware (D-pad maps correctly, no repeat, space/enter via `.a2k`, OSD item under
      System & BIOS).

## 10. How to use (after rebuild)
1. Open `a2k_editor.html`, set the mapping, **Save .a2k** → `<name>.a2k` (16 bytes).
2. Copy `<name>.a2k` to the MiSTer SD card.
3. OSD → **System & BIOS → "Load Joy Map"** → select `<name>.a2k`.
4. OSD → Hardware → "Joystick to keys" = On. Press joystick buttons.
   - D-pad → K/J/M/I, fire1/2 → U/O by default; set space/enter in the editor if wanted.
