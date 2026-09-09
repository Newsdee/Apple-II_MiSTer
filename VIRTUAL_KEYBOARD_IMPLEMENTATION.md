# Virtual Keyboard Implementation Plan

## Goal

Add an Apple IIc-style on-screen keyboard to the MiSTer core.

Controls:

- F10 opens the virtual keyboard.
- F10 or Escape closes it while it is visible.
- Arrow keys move the selection.
- Page Up moves the overlay to the top; Page Down moves it to the bottom.
- Enter presses and releases the selected key.
- The MiSTer-mappable `Keyb On` joystick button opens or closes the keyboard.
- Joystick directions move the selection while the keyboard is open.
- Joystick Fire 1 presses, holds, and releases the selected key.
- On the running-man button, Up/Down moves the overlay to the top or bottom.
- The `System & BIOS` OSD option selects transparency `Off`, opaque `On`, `On (75%)`, or `On (50%)`; it does not disable F10 or Keyboard On.
- The diamond button cycles the three enabled rendering modes and writes the selection back to the OSD status field.
- F10 and Escape used to control the overlay must not reach the Apple II.

## Input Ownership

When the virtual keyboard is hidden, existing input behavior is unchanged.

When it is visible, it owns user input:

- Physical keyboard events are consumed by the virtual keyboard controller.
- Digital joystick input is held at its neutral value.
- Analog joystick and paddle inputs are held at their calibrated center values.
- Mouse movement strobes and mouse buttons are suppressed.
- Existing keyboard shortcuts such as F2, F8, and F9 are suppressed.
- MiSTer menu and reset controls remain available.
- Storage, RTC, UART, and tape infrastructure are not considered user controls and are not gated.

Opening or closing the overlay must release any virtual key state that could otherwise remain held in the Apple II core. Sticky virtual Shift and Control clear when the overlay closes; continuously tracked physical modifiers and Caps state remain synchronized with the PC keyboard.

## Proposed Architecture

The implementation is divided into four responsibilities:

1. A SystemVerilog controller consumes raw PS/2 events, manages visibility and selection, and produces virtual Apple key events.
2. The existing VHDL keyboard module accepts virtual decoded key events while preserving the Apple keyboard latch, strobe, and AKD behavior.
3. A character-ROM reader provides authentic Apple II character-generator glyphs.
4. A SystemVerilog overlay renderer composites the keyboard after the existing drive-status overlay and before `video_mixer`.

Expected data path:

```text
PS/2 events -> virtual keyboard controller -> filtered physical keyboard path
                                    |
                                    +-> decoded virtual Apple key events
                                    +-> selection and modifier display state

Apple II RGB -> drive status overlay -> virtual keyboard overlay -> video_mixer
                                             ^
                                             |
                                  Apple character ROM copy
```

## Clocking and Execution Model

The virtual keyboard does not use a CPU. It is implemented as synchronous RTL: finite-state machines, counters, constant key-descriptor tables, and the duplicated character ROM.

It must not borrow the emulated Apple 6502. Doing so would require injecting code or data into the emulated machine, would depend on the currently running software and memory map, and could alter Apple state. The Apple CPU continues running normally behind the overlay unless a Commands-page reset action explicitly resets it.

It also does not justify a separate soft CPU. Navigation, sticky modifiers, key press/release events, hold-to-confirm timing, and three reset commands have bounded state and map directly to a small RTL controller. A soft CPU would add firmware, memory, clock-domain, and build complexity without simplifying this behavior.

### Primary Clock Domain

All new keyboard logic runs on `clk_sys`, the core's approximately 14.31818 MHz clock:

- `hps_io` is already clocked by `clk_sys` and presents `ps2_key` as an event bus in this domain.
- `virtual_keyboard_controller.sv` samples the event-toggle bit and updates selection, modifiers, page state, and virtual key events on `posedge clk_sys`.
- Hold-to-confirm, navigation repeat, and reset/button sequencing use cycle counters derived from a clock-frequency parameter.
- `keyboard.vhd`, `apple2_top.vhd`, the duplicate font ROM, and the Apple RGB/hblank/vblank signals already operate in this domain.
- `virtual_keyboard_overlay.sv` follows the existing `drive_status_overlay.sv` pattern and tracks active-pixel coordinates on `posedge clk_sys`.

The controller consumes the event-toggle protocol; it does not decode a raw PS/2 serial clock and does not need key-switch debounce logic.

### Video Clock Boundary

`CLK_VIDEO` and `ce_pix` belong to the downstream MiSTer `video_mixer`. The virtual keyboard is composited before that mixer, beside the existing drive overlay, so no new keyboard state crosses into `CLK_VIDEO` directly. The existing video pipeline owns that boundary.

The duplicate character ROM has a synchronous one-cycle read latency. The renderer must pipeline the corresponding pixel coordinates, glyph-row/column state, and background RGB by the same latency before compositing a glyph pixel. This is a local `clk_sys` pipeline, not a clock-domain crossing.

### RTL Building Blocks

```text
PS/2 event detector       toggle-bit edge detector
UI controller             finite-state machine
Key/layout data           synthesized constant table or case ROM
Navigation                small index/geometry comparisons
Sticky modifiers          state bits
Key press/release          event pulse plus remembered key identifier
Hold-to-confirm            cycle counter
Reset command sequencing  finite-state machine plus cycle counter
Glyph storage             duplicated block ROM
Overlay drawing           pixel counters, comparisons, and RGB mux
```

Counter durations should be parameters expressed from `CLK_SYS_HZ`, not unexplained literal counts. Simulation may override them with small values so controller and command tests run quickly.

## PS/2 Control Handling

MiSTer supplies keyboard events through `ps2_key[10:0]`:

- Bit 10 toggles for every press or release event.
- Bit 9 indicates press state.
- Bit 8 indicates an extended scan code.
- Bits 7:0 contain the Set-2 scan code.

Relevant Set-2 codes:

- F10: non-extended `0x09`
- Escape: non-extended `0x76`
- Enter: non-extended `0x5A`
- Up: extended `0x75`
- Down: extended `0x72`
- Left: extended `0x6B`
- Right: extended `0x74`

The controller must react only to new events detected through bit 10. A held F10 key must therefore produce one visibility transition, not repeated toggles.

## Virtual Keyboard Controller

Proposed new file:

```text
rtl/virtual_keyboard_controller.sv
```

Responsibilities:

- Track visible and hidden state.
- Detect F10 and Escape control events.
- Consume navigation events while visible.
- Track the selected key by a stable key identifier.
- Save the key identifier at press time so release cannot target a different key.
- Emit explicit virtual press and release events.
- Emit a forced release when the overlay closes or the core resets.
- Maintain sticky modifier state.
- Open and close the Commands page.
- Require a hold-to-confirm interval for destructive commands.
- Sequence reset requests and ROM-visible Apple button levels atomically.
- Export selection and modifier state to the renderer.
- Export an `active` signal for input gating.

The key table should describe each key rather than encode navigation in large case statements. Each key entry should contain:

- Row and logical identifier
- Horizontal position and width
- US and French display labels
- Unshifted Apple code
- Shifted Apple code
- Control Apple code where applicable
- Key type: character, action, or sticky modifier
- Layout membership for keys that exist in only one layout

Horizontal navigation selects the previous or next key in a row. Vertical navigation selects the key in the neighboring row whose horizontal center is nearest to the current key center.

## Documented Keyboard Layouts

The supplied photograph shows a French Apple IIe keyboard with both legends printed on shared key positions. On dual-labelled keys, the left column is the French layout and the right column is the US layout. The virtual keyboard should model this as one physical geometry with selectable legend and output profiles, rather than as two separate sets of coordinates.

For the initial implementation:

```text
ACTIVE_LAYOUT = US
```

Only US legends and US key outputs will be rendered and emitted initially. The French profile is documented now so it can be enabled later without redesigning the key table.

See [KEYBOARD_LAYOUT.md](KEYBOARD_LAYOUT.md) for an ASCII preview of the initial US keyboard overlay.

In the tables below, character pairs are written as `shifted / unshifted`. A single character has the same named key position in both layouts. `--` means that the photographed keyboard has no corresponding character in that layout at that position.

### Row 0: Escape and Number Row

| Position | French legend | US legend |
| --- | --- | --- |
| `ESC` | Escape | Escape |
| `DIGIT1` | `1 / &` | `! / 1` |
| `DIGIT2` | `2 / é` | `@ / 2` |
| `DIGIT3` | `3 / "` | `# / 3` |
| `DIGIT4` | `4 / '` | `$ / 4` |
| `DIGIT5` | `5 / (` | `% / 5` |
| `DIGIT6` | `6 / §` | `^ / 6` |
| `DIGIT7` | `7 / è` | `& / 7` |
| `DIGIT8` | `8 / !` | `* / 8` |
| `DIGIT9` | `9 / ç` | `( / 9` |
| `DIGIT0` | `0 / à` | `) / 0` |
| `MINUS` | `° / )` | `_ / -` |
| `EQUALS` | `+ / -` | `+ / =` |
| `DELETE` | Delete | Delete |
| `RESET` | Reset | Reset |

Reset is retained here as documentation of the photographed hardware. It is not rendered as a directly selectable key in the typing overlay; its separated position is used for the `COMMANDS` page selector.

### Row 1: Tab and Upper Letter Row

| Position | French legend | US legend |
| --- | --- | --- |
| `TAB` | Tab | Tab |
| `KEY_Q` | `A` | `Q` |
| `KEY_W` | `Z` | `W` |
| `KEY_E` | `E` | `E` |
| `KEY_R` | `R` | `R` |
| `KEY_T` | `T` | `T` |
| `KEY_Y` | `Y` | `Y` |
| `KEY_U` | `U` | `U` |
| `KEY_I` | `I` | `I` |
| `KEY_O` | `O` | `O` |
| `KEY_P` | `P` | `P` |
| `LEFT_BRACKET` | `¨ / ^` | `{ / [` |
| `RIGHT_BRACKET` | `* / $` | `} / ]` |
| `RETURN` | Return | Return |

### Row 2: Control and Home Letter Row

| Position | French legend | US legend |
| --- | --- | --- |
| `CONTROL` | Control | Control |
| `KEY_A` | `Q` | `A` |
| `KEY_S` | `S` | `S` |
| `KEY_D` | `D` | `D` |
| `KEY_F` | `F` | `F` |
| `KEY_G` | `G` | `G` |
| `KEY_H` | `H` | `H` |
| `KEY_J` | `J` | `J` |
| `KEY_K` | `K` | `K` |
| `KEY_L` | `L` | `L` |
| `SEMICOLON` | `M` | `: / ;` |
| `QUOTE` | `% / ù` | `" / '` |
| `TILDE` | -- | `~` |
| `RETURN_LOWER` | Return | Return |
| `POSITION` | Running Man | Running Man |

`RETURN` and `RETURN_LOWER` are two rendered parts of the same L-shaped Return key and must share one logical key identifier.

### Row 3: Shift and Lower Letter Row

| Position | French legend | US legend |
| --- | --- | --- |
| `LEFT_SHIFT` | Shift | Shift |
| `BACKSLASH` | `£ / *` | `| / \` |
| `KEY_Z` | `W` | `Z` |
| `KEY_X` | `X` | `X` |
| `KEY_C` | `C` | `C` |
| `KEY_V` | `V` | `V` |
| `KEY_B` | `B` | `B` |
| `KEY_N` | `N` | `N` |
| `KEY_M` | `? / ,` | `M` |
| `COMMA` | `. / ;` | `< / ,` |
| `PERIOD` | `/ / :` | `> / .` |
| `SLASH` | `+ / =` | `? / /` |
| `RIGHT_SHIFT` | Shift | Shift |

The position identifiers in this row describe the photographed physical positions; they are not USB or PS/2 key names. Before implementing the French profile, its punctuation outputs must be checked against the local character-ROM bank and the existing `keyboard.mif` mapping.

### Row 4: Modifiers, Space, and Arrows

| Position | French legend | US legend |
| --- | --- | --- |
| `CAPS_LOCK` | Caps Lock | Caps Lock |
| `OPEN_APPLE` | Open Apple | Open Apple |
| `SPACE` | Space | Space |
| `CLOSED_APPLE` | Closed Apple | Closed Apple |
| `LEFT_ARROW` | Left Arrow | Left Arrow |
| `RIGHT_ARROW` | Right Arrow | Right Arrow |
| `DOWN_ARROW` | Down Arrow | Down Arrow |
| `UP_ARROW` | Up Arrow | Up Arrow |
| `TRANSPARENCY` | Diamond | Diamond |

The illuminated square between Caps Lock and Open Apple in the photograph is the Caps Lock indicator, not an input key. It must not be included in navigation.

### Layout Data Model

Geometry, navigation, and logical action belong to the physical position. Legends and emitted character values belong to a layout profile. A descriptor should therefore contain layout-indexed values, conceptually:

```text
key_position {
  geometry
  action
  us:     { normal_label, shifted_label, normal_code, shifted_code }
  french: { normal_label, shifted_label, normal_code, shifted_code }
}
```

Action keys such as Escape, Return, Delete, modifiers, arrows, and Space share their action between profiles. `ISO_EXTRA` is omitted from navigation while the US profile is active. The first implementation should use a constant US profile, but the data structure must not bake US labels into rendering logic.

## Commands Page and Reset Behavior

The physical Reset key is omitted from the typing grid to avoid accidental activation. A `COMMANDS` selector occupies its visually separated position and opens a page of explicit special actions.

The Apple IIe ROM already implements the reset distinctions. After the CPU reset vector enters the monitor ROM at `$FAFA`, the firmware reads the two game-port button inputs:

- `$C061` (`BUTN0`, Open Apple, joystick button 0): pressed alone selects a forced cold start.
- `$C062` (`BUTN1`, Closed Apple, joystick button 1): pressed selects the built-in self-test, whether or not Open Apple is also pressed.
- Neither button pressed selects the normal warm-reset path and honors a valid page-3 reset vector.

This matches the local wiring in `rtl/apple2_top.vhd`: Open Apple is ORed with `joy(4)` into game-port button 0, and Closed Apple is ORed with `joy(5)` into game-port button 1. Control is part of the physical keyboard's protection against accidentally asserting Reset; it is not a CPU-readable game-port input.

Initial command entries:

| Command | Displayed physical combination | ROM-visible state |
| --- | --- | --- |
| Warm Reset | Control + Reset | Open Apple off, Closed Apple off |
| Forced Cold Start | Control + Open Apple + Reset | Open Apple on, Closed Apple off |
| Built-in Self-Test | Control + Closed Apple + Reset | Closed Apple on; Open Apple off for clarity |

The forced cold-start firmware deliberately invalidates memory, including the page-3 reset vector. The self-test writes and reads programmable memory. Both commands must therefore require a deliberate hold-to-confirm action rather than execute on an ordinary Enter press.

Command execution sequence:

1. Latch the selected command and ignore navigation changes.
2. Assert the required virtual Apple button level or levels.
3. Assert the CPU reset request.
4. Deassert reset while continuing to hold the Apple button levels long enough for the ROM to read `$C061/$C062`.
5. Release the Apple button levels, close the overlay, and clear all virtual key and modifier state.

Ordinary joystick input remains suppressed while the overlay is active. Command-generated Apple button levels must bypass that suppression so the ROM sees only the selected command state, not live controller buttons.

Research basis: Chapter 4, "The Reset Routine," "Forced Cold Start," and "Automatic Self-Test" in the *Apple IIe Technical Reference Manual*, plus its monitor ROM listing (`BUTN0`, `BUTN1`, `NODIAGS`, and `DIAGS`). The local `apple2e.mif` reset vector also resolves to `$FAFA`.

## Modifier Behavior

The virtual keyboard should improve on the single-key limitation found in the reviewed Analogue Amiga implementation.

The following virtual keys are sticky toggles:

- Shift
- Control
- Caps Lock
- Open Apple
- Closed Apple

Physical PC Shift and Control are momentary. Their effective states are the physical state OR the corresponding sticky virtual state. Left and right PC Shift are tracked independently so releasing one does not cancel the other. PC Caps Lock and virtual Caps Lock toggle the same persistent Caps state.

Effective Shift, Control, and Caps Lock affect the decoded character chosen when a normal key is pressed. Letter keys display one uppercase or Enhanced lowercase glyph matching effective Shift/Caps case. Open Apple and Closed Apple drive their existing level-sensitive outputs while latched.

The renderer must visibly distinguish latched modifiers from the currently selected key.

Sticky Shift, Control, Open Apple, and Closed Apple clear when the virtual keyboard closes. Caps Lock persists across overlay sessions. Core reset clears all controller state.

## Apple Keyboard Injection

Files to modify:

```text
rtl/keyboard.vhd
rtl/apple2_top.vhd
Apple-II.sv
```

Proposed additions to the `keyboard` entity:

```text
virtual_active
virtual_event
virtual_pressed
virtual_code[6:0]
virtual_open_apple
virtual_closed_apple
```

On a virtual key press:

- Latch `virtual_code` as the current Apple key value.
- Set the Apple keyboard strobe.
- Assert AKD.

On a virtual key release:

- Deassert AKD.
- Leave the keyboard strobe set until the Apple reads it, matching the existing keyboard contract.

On virtual-keyboard activation:

- Clear any pending physical key strobe.
- Clear physical Shift and Control state.
- Clear physical Open Apple and Closed Apple state.
- Ignore subsequent physical key events except those consumed by the virtual keyboard controller.

When the overlay is inactive, physical Escape must retain its existing Apple mapping.

Direct decoded Apple-code injection is preferred over generating synthetic PS/2 sequences. It avoids event-spacing assumptions while preserving the machine-facing latch and strobe behavior.

## Character Glyph Source

Apple glyphs are stored in the character-generator ROM:

```text
rtl/roms/video2.mif
```

They are not stored in the Apple II system ROM.

The bundled ROM contains the Enhanced IIe MouseText symbols used by the Apple
modifier keys. In the alternate character set, screen code `$40` selects the
filled Closed Apple glyph (ROM address `$0200`) and `$41` selects the outline
Open Apple glyph (ROM address `$0208`). The overlay exposes the alternate-set
address bit so these glyphs can be used directly instead of abbreviated text.

The active video generator uses an 8192 x 8 single-port `spram`. Its live read port should not be shared with the overlay because doing so would disturb video timing.

Proposed new file:

```text
rtl/apple2_font_rom.vhd
```

This module should instantiate an independent ROM initialized from `video2.mif` and use the same character address construction as `rtl/video_generator.vhd`.

Requirements:

- Select the same US or local character-ROM bank as the active core.
- Receive the same video-ROM `ioctl` writes so a loaded custom character ROM also changes overlay glyphs.
- Defer or blank overlay glyph reads during character-ROM writes if required by the single-port implementation.
- Use explicit Apple screen-character values in key descriptors instead of assuming linear ASCII indexing.

The duplicate ROM costs 65,536 block-memory bits. The current build uses approximately 3.07 Mbits, so the expected cost is acceptable, but the Quartus fitter report must confirm it.

## Overlay Renderer

Proposed new file:

```text
rtl/virtual_keyboard_overlay.sv
```

Insertion point:

```text
Apple II RGB
  -> rtl/drive_status_overlay.sv
  -> rtl/virtual_keyboard_overlay.sv
  -> video_mixer
```

Presentation:

- Apple IIe keyboard layout across the lower portion of the active picture.
- Panel, border, well, key, indicator, and legend colors use the selected opaque, 75%-transparent, or 50%-transparent rendering mode.
- Character-generator glyphs in a high-contrast foreground color.
- A distinct selected-key highlight.
- A separate latched-modifier indication.
- Single letter legends that follow effective Caps/Shift case, using the Enhanced lowercase bank when needed, plus simultaneous full-size shifted/unshifted symbol legends diagonally offset with the inactive symbol slightly darker.
- A running-man MouseText control for top/bottom placement and a diamond control that cycles the enabled OSD transparency modes.
- Fixed geometry derived from active-video pixel counters.

The renderer should maintain its own active-pixel coordinates using the same hblank/vblank edge technique as `drive_status_overlay.sv`.

The first implementation should favor deterministic geometry and low logic cost over animation.

## Input Gating in Apple-II.sv

While `virtual_keyboard_active` is asserted:

- Pass neutral digital joystick values to `apple2_top`.
- Pass calibrated-center analog and paddle values to `apple2_top`.
- Hold mouse buttons released.
- Suppress mouse strobes so accumulated host movement is not replayed into the core.
- Preserve host-side mouse state so closing the overlay does not create a movement jump.

The exact neutral polarity and center representation must be verified against `rtl/joystick_input.sv` and the `apple2_top` game-port mapping before the gating edit is made.

## Expected File Changes

New files:

```text
rtl/virtual_keyboard_controller.sv
rtl/virtual_keyboard_overlay.sv
rtl/apple2_font_rom.vhd
VIRTUAL_KEYBOARD_IMPLEMENTATION.md
```

Modified files:

```text
Apple-II.sv
rtl/apple2_top.vhd
rtl/keyboard.vhd
files.qip
```

Additional testbench files may be added alongside the implementation.

## Implementation Stages

### Stage 1: Visibility and Ownership

- Add PS/2 event decoding.
- Toggle visibility with F10.
- Close with F10 or Escape.
- Gate human input while visible.
- Flush held state on open, close, and reset.

This stage may initially render a simple solid rectangle to prove video placement and ownership behavior.

### Stage 2: Selection and Key Injection

- Add the key descriptor table.
- Add arrow-key navigation.
- Add Enter press and release handling.
- Extend `keyboard.vhd` with virtual event injection.
- Verify Apple strobe, read-clear, AKD, and repeat interactions.

### Stage 3: Full Layout and Modifiers

- Populate the documented physical layout and US legend/output profile.
- Add Shift, Control, Caps Lock, Open Apple, and Closed Apple.
- Add shifted and control output mappings.
- Add forced modifier cleanup.
- Retain the documented French profile in the key descriptors, disabled for now.

### Stage 3A: Commands Page

- Replace the rendered Reset key with the `COMMANDS` selector.
- Add Warm Reset, Forced Cold Start, and Built-in Self-Test entries.
- Add hold-to-confirm behavior with visible progress and release-to-cancel.
- Hold the selected Apple button state across reset release until the ROM can sample it.
- Close the overlay and clear all input state after command execution.

### Stage 4: Apple Glyph Renderer

- Add the duplicate character ROM.
- Render labels from Apple glyph data.
- Add selection and modifier highlighting.
- Verify US, local, and custom character ROM behavior.

### Stage 5: Joypad Activation

- Select the final joypad chord or button.
- Add joypad navigation and selection.
- Keep F10 available temporarily for debugging, then decide whether it remains as a secondary shortcut.

## Validation Plan

### Controller Simulation

- One F10 press produces exactly one visibility transition.
- F10 release does not toggle visibility.
- F10 closes the visible keyboard without reaching the Apple II.
- Escape closes the visible keyboard without reaching the Apple II.
- Escape reaches the Apple II normally while the keyboard is hidden.
- Arrow navigation stays within valid keys.
- Vertical movement selects the nearest key center.
- Enter release targets the key saved on Enter press.
- Closing while Enter is held emits a release.
- Reset clears visibility, selection press state, and all modifiers.
- An ordinary Enter press cannot trigger a reset command.
- Releasing Enter before the confirmation interval cancels the command.
- Warm Reset releases reset with both Apple buttons low.
- Forced Cold Start releases reset with only Open Apple high.
- Built-in Self-Test releases reset with Closed Apple high.
- Live joystick buttons cannot alter a command's latched Apple-button state.

### Keyboard Interface Simulation

- Physical keys behave identically while the overlay is hidden.
- Physical keys cannot alter K, AKD, modifiers, or Apple keys while it is visible.
- A virtual press sets the correct code and strobe.
- An Apple keyboard read clears the strobe.
- A virtual release clears AKD.
- Shifted and Control combinations produce the expected Apple codes.
- Opening while a physical key or modifier is held cannot leave it stuck.

### Renderer Simulation

- Known character-ROM rows produce expected glyph pixels.
- Selection and modifier highlights do not alter unrelated pixels.
- The overlay is absent when disabled.
- The overlay remains inside the active picture in NTSC and PAL modes.
- RGB, hblank, vblank, and sync alignment remain unchanged outside the overlay.

### Quartus Validation

- Analysis and synthesis complete without errors.
- Timing remains clean on the 14.31818 MHz and video paths.
- Character-ROM duplication is inferred as block memory.
- Resource growth is recorded from the fitter report.

### Hardware Validation

- Test F10 open and F10/Escape close behavior.
- Test inactive Escape behavior in Apple software.
- Test every displayed key.
- Verify the displayed and emitted initial layout is US.
- Test Shift, Control, Caps Lock, Open Apple, and Closed Apple combinations.
- Verify joystick, paddle, and mouse isolation while the keyboard is visible.
- Verify no stuck keys after opening, closing, reset, or MiSTer menu use.
- Verify video placement with PAL/NTSC, both pixel-clock modes, all scaler modes, and representative display modes.

## Design Constraints

- Do not import the Spectrum PicoRV32 or Amiga VexRiscv infrastructure.
- Do not manipulate a keyboard matrix; the Apple II interface is decoded key data plus latch/strobe state.
- Do not copy the Amiga implementation's single-key modifier limitation.
- Do not allow navigation to change which key receives a pending release.
- Do not share the live single-port character-ROM read port with the overlay.
- Keep the existing physical keyboard behavior unchanged whenever the overlay is hidden.

## Open Decisions

- Final joypad activation button or chord.
- How the French profile will eventually be selected.
- Confirm French punctuation codes against the local character ROM and `keyboard.mif` before enabling that profile.
- Whether Space should also select the highlighted key during the F10 development phase.
- Exact visual dimensions, colors, and screen position.
- Whether modifier state should persist after typing one character; the initial recommendation is to keep it latched until explicitly toggled or the overlay closes.
- Whether F10 remains as a permanent secondary shortcut after joypad support is added.