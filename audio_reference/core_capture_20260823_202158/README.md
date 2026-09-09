# Core hardware capture - enhanced read texture

Source: `D:\Xcapture1\2026-08-23_202158.mp4`

Captured after changing the controller-driven read texture from:

- texture divider 8192 to 4096
- decay divider 2048 to 4096
- retrigger interval 8192 to 4096 clocks

Motor level and all step layers remained unchanged.

## Capture validation

- Duration: 12.13 seconds.
- Video: valid 1920x1080 H.264 Constrained Baseline, 694 frames, `yuv420p`.
- Active peak: -8.60 dBFS.
- Active RMS: -27.86 dBFS.
- No flat-topped samples were detected.
- Encoded idle tail: approximately -67 dBFS RMS, consistent with capture/AAC noise.

## Before/after listening clips

| File | Description |
|---|---|
| `01-before-middle-read.wav` | Previous 4x capture, middle activity |
| `02-after-middle-read.wav` | Enhanced texture, matching middle activity |
| `03-before-late-read.wav` | Previous 4x capture, late activity |
| `04-after-late-read.wav` | Enhanced texture, matching late activity |

## Measured effect

Relative to the 350-650 Hz motor band:

- Middle activity gained about 1.0 dB in 650-2200 Hz and 1.2 dB in 2200-6000 Hz.
- Late activity gained about 0.7 dB in 650-2200 Hz and 1.0 dB in 2200-6000 Hz.
- Low-band balance changed by less than 0.2 dB.

The change is measurable, preserves headroom and idle behavior, and does not alter software-controlled cadence. Listening should determine whether the read texture is now sufficiently audible or needs a peak-level increase.

## Assessment

Do not increase read-texture level again yet. In the latest middle activity, the 650-2200 Hz band is about 1.8 dB above motor and the 2200-6000 Hz band is about 3.9 dB below motor. The confirmed Neptune steady-read clips measure about 2 dB below and 7 dB below motor respectively. The core therefore already has roughly 3-4 dB more relative read-band energy than that reference.

If the texture still seems masked, the remaining cause is the core's excess 100-350 Hz motor energy, not insufficient read-texture amplitude. Keep the enhanced read parameters and defer additional read gain until the motor balance is revisited. The separate short bright step attack remains the next unimplemented sound layer.
