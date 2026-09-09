# Apple II floppy audio references

Reference recordings and extracted comparison clips used to tune `rtl/floppy_sound.sv`.

## Original boot reference

Source: https://www.youtube.com/watch?v=BDSFdfwocYU&t=12s

- `apple2-boot-reference.wav`: complete extracted reference interval.
- `apple2-drive-only.wav`: drive-only interval without the power switch and boot beep.
- `identified_parts/`: isolated boot, motor, read activity, shutdown, and room-tone clips.
- `apple2-boot-spectrogram.png`: full reference spectrogram.
- `apple2-boot-spectrogram-zoom.png`: detailed drive-activity spectrogram.
- `apple2-boot-waveform.png`: reference waveform.

See `identified_parts/README.md` for timestamps and the motor-stop analysis.

## Louder mechanical reference

Source: https://www.youtube.com/watch?v=Dub4nraPLlQ

The 34.93-second recording emphasizes head movement and seek resonance. It confirms a motor body near 450-500 Hz and shows strong harmonic mechanical energy from approximately 650-2200 Hz.

See `louder_reference/README.md` for isolated clips, measurements, and implementation conclusions.

## Apple IIc cadence reference

Source: https://www.youtube.com/watch?v=f3nklHUtwh0

This recording uses the Apple IIc internal drive rather than a Disk II mechanism. Use `apple_iic_reference/` only for software-driven cadence and activity grouping. Its pitch, resonance, impact timbre, and layer balance are not Disk II tuning targets.

## Newer Apple IIe drive reference

Source: https://www.youtube.com/shorts/4-ES0DXfzwE

The first eight seconds show an Apple IIe with a newer drive mechanism. The remainder shows a Commodore 1541-II and is excluded. Use `newer_iie_drive_reference/` as secondary evidence for step cadence and broad spectral balance, not exact Disk II pitch or timbre.

## Core hardware captures

`core_capture_20260823_185128_4x/` contains the validated 4x hardware capture after replacing the pitched step oscillator with a noise-excited ring. Its analysis confirms that the startup beeps are gone and identifies excessive low-band motor noise as the next tuning target.

## Current conclusions

- Keep the synthesized motor body near 430 Hz.
- Use the original reference for motor shutdown timing.
- Use the louder reference for step impacts, grouped seek cadence, and resonant ringing.
- Let real controller phase-step events provide cadence; do not generate artificial seek timing in the sound module.
- Use the Apple IIc reference only to verify the grouping of dense seeks and isolated accesses.
- Use the newer IIe drive only as secondary evidence for short bright step attacks; exclude its Commodore segment.
- Prefer a short 1-2 kHz resonant step component over additional broadband I/O noise.
- Preserve exact-zero output while the drive sound is idle.
