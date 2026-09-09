# Virtual Keyboard Layout

This is the visual reference for the planned on-screen keyboard. The initial implementation renders and emits the US layout. The French legends remain documented in [VIRTUAL_KEYBOARD_IMPLEMENTATION.md](VIRTUAL_KEYBOARD_IMPLEMENTATION.md) for a later selectable profile.

## US Overlay Preview

The layout follows the compact Apple IIc keyboard shape. Letter keys show one glyph in the effective Caps/Shift case. Symbol keys show both glyphs at full size: shifted at the upper-left and unshifted at the lower-right. The inactive glyph uses a slightly darker color.

```text
+-----+----+----+----+----+----+----+----+----+----+----+----+----+--------+  +-------+
| Esc | !1 | @2 | #3 | $4 | %5 | ^6 | &7 | *8 | (9 | )0 | _- | += |  Del   |       | Cmd |
+------+---+----+----+----+----+----+----+----+----+----+----+----+--------+  +-------+
| Tab  | Q | W  | E  | R  | T  | Y  | U  | I  | O  | P  | {[ | }] |    ↵    |
+-------+--+----+----+----+----+----+----+----+----+----+----+----+--+       |
| Ctrl  | A | S  | D  | F  | G  | H  | J  | K  | L  | :; | "' | ~` |       |  [run]
+---------+--+----+----+----+----+----+----+----+----+----+----+----+-------+
|  ⇧  | |\ | Z | X  | C  | V  | B  | N  | M  | <, | >. | ?/ |    Shift    |
+----------+--+----+----+----+----+----+----+----+----+----+---------------+
|   Caps    | On | Open Apple |                  Space                   | Closed Apple | ← | → | ↓ | ↑ |  ◇
+-----------+------------+--------------------------------------+--------------+----+----+---+---+
```

## Interaction States

The renderer should represent state without changing key geometry:

```text
Normal key:             [  A  ]
Current selection:      [> A <]
Latched modifier:       [*Shift*]
Selected and latched:   [>Shift<]
```

The exact border and highlight colors are renderer details. Selection must remain visually distinct from a latched modifier when color is unavailable or poorly reproduced.

## Rendering Notes

- Character legends use glyphs from `rtl/roms/video2.mif`.
- Caps-off letter legends use the Enhanced lowercase character bank; each letter key still shows one glyph.
- Open Apple and Closed Apple use the Enhanced alternate-set glyphs at screen codes `$41` and `$40`, respectively.
- Return and the four cursor keys use Enhanced MouseText glyphs: `$4D`, `$48`, `$55`, `$4A`, and `$4B`.
- Tab combines MouseText `$55` and `$5F`. The position button uses the running-man frames `$46` then `$47`.
- Left Shift uses MouseText `$52`; right Shift, Caps, and Ctrl use mixed-case labels. MouseText `$4A/$4B` remain reserved for cursor Down/Up.
- The housing uses `#D0C4B1` with a dark key well, visible row separators, charcoal keycaps, and pale legends.
- A nonselectable gray housing with a pale-green lamp sits immediately to the right of Caps Lock.
- Named keys may use abbreviated Apple-ROM labels where space is limited: `ESC`, `Del`, and `Ctrl`.
- Return is one logical key rendered with an L-shaped two-row footprint.
- `CMD` replaces the photographed Reset key and opens the Commands page.
- The Caps Lock lamp is decoration only and is not selectable.
- The `| / \` key is immediately right of left Shift; shifted `$7E` tilde and unshifted `$60` backtick share the key beneath `] / }`.
- The running-man button uses Up/Down to move the overlay to the top or bottom of the active picture.
- Page Up and Page Down move the overlay to the top or bottom from either overlay page.
- PC Shift and Ctrl act momentarily in addition to sticky virtual Shift and Ctrl. PC Caps Lock toggles the shared Caps state.
- The `System & BIOS` OSD page provides `Virtual keyboard: Off / On` and `Keypad visibility: 100% / 75% / 50% / 25%`.
- Selecting `Virtual keyboard: On` displays the keyboard immediately. F10 and the `Keyboard On` controller button update that OSD option even while the OSD menu is closed.
- The bottom-right diamond cycles the four keypad visibility levels and updates the OSD setting.
- Transparent modes blend panel, key, indicator, active legend, and inactive legend colors with the underlying Apple video.

## Commands Page Preview

```text
+------------------------------------------------------------------------------+
| Keyboard | COMMANDS                                                         |
+------------------------------------------------------------------------------+
|                                                                              |
|  [ Warm Reset ]       [ Forced Cold Start ]       [ Built-in Self-Test ]     |
|   Ctrl + Reset         Ctrl + Open Apple + Reset   Ctrl + Closed Apple + Reset|
|                                                                              |
|  Hold Enter to run the selected command. Release Enter to cancel.            |
|                                                                              |
|  [ Back to Keyboard ]                                                        |
+------------------------------------------------------------------------------+
```

The Commands page is not a second Apple keyboard row. Each entry is an explicit controller action. The selected command must complete its reset/button timing atomically, close the overlay, and clear all virtual modifiers afterward.