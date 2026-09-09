# Newer Apple IIe drive reference

Source: https://www.youtube.com/shorts/4-ES0DXfzwE

Title: `Retro Computer ASMR: apple II floppy disk drive & Commodore 64 1541 II "head banging"`
Uploader: `Ashton's Retro Computer Room`
Duration: 22.11 seconds

## Hardware and segmentation caveat

This video contains two different computers. The Apple IIe and its newer drive occupy approximately 0.00-7.98 seconds. The Commodore 1541-II segment begins around 8.00 seconds and is excluded from Apple sound analysis.

The Apple drive is newer than the original Disk II mechanism. Use it as a secondary reference for cadence, broad layer balance, and the distinction between head impacts and steady operation. Do not use its exact pitches or resonance frequencies as authoritative Disk II targets.

## Comparison clips

| File | Source time | Identification |
|---|---:|---|
| `01-apple-iie-opening.wav` | 0.00-2.94 s | Apple IIe opening and initial drive activity |
| `02-apple-iie-head-recalibration.wav` | 2.94-4.75 s | Dense Apple head recalibration impacts |
| `03-apple-iie-quieter-operation.wav` | 4.75-7.98 s | Quieter Apple drive operation |
| `04-commodore-excluded.wav` | 8.00-22.10 s | Commodore 1541-II; excluded from Apple analysis |

## Findings

- Apple recalibration has strong mechanical energy without behaving like a fixed electronic tone.
- During recalibration, the 650-2200 Hz band is about 1 dB above the 350-650 Hz motor band.
- During quieter Apple operation, the mechanical band is about 3 dB above motor.
- The 2200-6000 Hz upper band is only about 1-2 dB below the mechanical band during recalibration.
- In the current 4x core capture, 100-350 Hz is about 4 dB above motor and the upper band is about 6 dB below mechanical.

## Implementation direction

This recording supports reducing broadband low-frequency motor noise. It also supports adding a short, irregular bright attack to each real step event so impacts carry some 2-6 kHz energy. The bright component should decay quickly and must not use a phase-coherent oscillator, which previously made repeated steps sound like beeps.

Retain the original Disk II recordings as the authority for motor pitch, sustained resonance, and shutdown timing.
