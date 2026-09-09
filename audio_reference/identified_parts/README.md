# Identified Apple II boot audio parts

Source: `apple2-boot-reference.wav`, extracted from approximately 12.00 seconds in the referenced YouTube video.

The labels are inferred from waveform and spectrogram analysis. Listen to the clips to verify them against the video.

| File | Reference WAV time | Approx. video time | Identification |
|---|---:|---:|---|
| `01-initial-room-tone.wav` | 0.00-0.22 s | 12.00-12.22 s | Initial silence / room tone |
| `02-power-switch-transient.wav` | 0.22-0.50 s | 12.22-12.50 s | Power-switch and startup transient |
| `03-boot-beep.wav` | 0.50-0.70 s | 12.50-12.70 s | Apple II boot beep |
| `04-pre-drive-gap.wav` | 0.70-0.91 s | 12.70-12.91 s | Gap before drive activity |
| `05-disk-ii-boot-sequence.wav` | 0.91-2.35 s | 12.91-14.35 s | Loud initial Disk II motor and head activity |
| `06-drive-spinning-and-read-activity.wav` | 2.35-12.25 s | 14.35-24.25 s | Quieter sustained drive spinning and read activity |
| `07-motor-stop-transition.wav` | 12.00-12.60 s | 24.00-24.60 s | Overlapping close-up of the motor stopping |
| `08-drive-stopped-room-tone.wav` | 12.60-14.88 s | 24.60-26.88 s | Room tone after the drive has stopped |

Use both clips as comparison references for `rtl/floppy_sound.sv`. The aggregate
`../apple2-drive-only.wav` contains the complete 0.91-14.88 second drive interval
without the power-switch transient or boot beep.

The 200-2000 Hz mechanical-band level falls by roughly 10-14 dB around reference
time 12.3 seconds. Compare parts 06 and 08, using part 07 to hear the transition.
