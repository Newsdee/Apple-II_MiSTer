# Louder Disk II reference

Source: https://www.youtube.com/watch?v=Dub4nraPLlQ

Title: `Sound / grind of a 5.25" Apple II floppy drive at work`
Uploader: `kevgordon`
Duration: 34.93 seconds

## Comparison clips

| File | Source time | Identification |
|---|---:|---|
| `01-startup-grind.wav` | 2.56-4.60 s | Motor onset and dense recalibration/seek impacts |
| `02-steady-seeks-and-read.wav` | 4.70-26.30 s | Sustained motor with intermittent seeks and read activity |
| `03-long-seek-sweep.wav` | 26.40-30.50 s | Long changing-rate seek with visible harmonic sweep |
| `04-late-activity.wav` | 30.50-34.70 s | Quieter motor and isolated late seeks |

## Findings

- A stable motor ridge remains near 450-500 Hz, supporting the synthesized 430 Hz motor tone.
- Head motion is strongly harmonic from roughly 650 Hz through 2200 Hz, with energy extending above 6 kHz during impacts.
- Relative to the 350-650 Hz motor band, 650-2200 Hz mechanical energy is about 7 dB higher in the new startup and steady intervals. It was about 3 dB higher during the first reference's boot burst.
- The long seek produces a changing harmonic comb rather than continuous broadband noise. Step cadence and resonant ringing dominate its character.
- This recording has no clean motor-stop interval. Keep using the first reference's `07-motor-stop-transition.wav` for shutdown tuning.

The next synthesis priority should be a short resonant step component around 1-2 kHz and realistic grouped step cadence. Increasing the broadband I/O texture would move away from this reference.
