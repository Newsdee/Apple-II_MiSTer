# Apple IIc cadence reference

Source: https://www.youtube.com/watch?v=f3nklHUtwh0

Title: `Wizardry disk drive sound (Apple II - Sir-Tech)`
Uploader: `AppleAdventures`
Duration: 66.07 seconds

## Hardware caveat

This recording is from an Apple IIc internal 5.25-inch drive, not the external Disk II mechanism associated with the Apple IIe reference recordings. Use it only to compare software-driven operation cadence, activity grouping, and the transition between dense seeks and isolated accesses. Do not use its motor pitch, resonance frequencies, impact timbre, or relative layer levels as targets for `rtl/floppy_sound.sv`.

## Comparison clips

| File | Source time | Identification |
|---|---:|---|
| `01-startup-and-grind.wav` | 3.87-7.54 s | Startup followed by dense mechanical activity |
| `02-short-burst-cadence.wav` | 8.63-11.47 s | Short separated access bursts |
| `03-extended-burst-cadence.wav` | 12.48-23.42 s | Longer sequence of grouped accesses |
| `04-isolated-late-seek.wav` | 55.56-56.47 s | Isolated late seek/activity event |
| `05-final-short-event.wav` | 61.73-62.55 s | Final short activity event |

## Implementation conclusion

Cadence should not be generated artificially inside the sound module. The existing per-drive phase-step events already preserve the timing produced by Apple II software and the emulated controller. A resonant step layer should retrigger directly from every real step event so dense recalibration, long seeks, and isolated accesses naturally retain their original cadence.

Use the Disk II recordings for all timbre and amplitude tuning.
