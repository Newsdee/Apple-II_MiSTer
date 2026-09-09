# Core hardware capture - 4x sound

Source: `D:\Xcapture1\2026-08-23_185128.mp4`

Captured from hardware with Disk drive sound set to `On (4x)` after replacing the phase-coherent 1.4 kHz step oscillator with a noise-excited ring.

## Capture validation

- Duration: 12.37 seconds.
- Video: valid 1920x1080 H.264 Constrained Baseline, 708 frames, `yuv420p`.
- Audio: stereo AAC at 48 kHz, analyzed as mono PCM at 48 kHz.
- Active-audio peak: -8.79 dBFS.
- Active-audio RMS: -28.16 dBFS.
- No flat-topped capture samples were detected.
- The level is approximately 12 dB above the earlier 1x capture, as expected for 4x gain.

## Findings

- The fixed-pitch startup beeps are gone. Step groups now have broadband, irregular mechanical attacks rather than a phase-coherent harmonic ladder.
- The 100-350 Hz low band remains 3-4 dB stronger than the 350-650 Hz motor band.
- The 650-2200 Hz mechanical band is only about 1 dB above the motor band. The louder real Disk II reference places this band about 7 dB above motor during active seeks.
- The encoded idle tail measures about -68 dBFS RMS. This is capture/AAC noise and cannot prove FPGA exact-zero output, but no sustained synthesized layer is visible after shutdown.

## Next tuning direction

Reduce the broadband motor-noise level while retaining the 430 Hz motor tone. This should reveal step mechanics and move the low/motor/mechanical balance toward the Disk II reference without increasing transient gain or risking saturation in 4x mode.
