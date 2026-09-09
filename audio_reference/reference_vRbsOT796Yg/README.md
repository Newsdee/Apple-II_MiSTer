# Neptune Apple II recording

Source: https://www.youtube.com/watch?v=vRbsOT796Yg

Title: `Neptune short play and disk drive sound (Apple II - Gebelli Software)`
Uploader: `AppleAdventures`
Duration: 18:45

The requested analysis begins at source time 0:24. The video shows only the Apple display during the initial loading sequence, not the physical drive, so audio events cannot all be classified confidently from visuals or spectra alone.

## Reviewed clips

Clips are in `needs_listening/` and have been identified by listening.

| File | Source time | Visible context | Question |
|---|---:|---|---|
| `01-event-24.75s.wav` | 24.75-25.55 s | Disk instruction screen | User closing the drive bay; ignore for sound analysis. |
| `02-event-26.20s.wav` | 26.20-28.25 s | Blank/loading transition before title | Apple II boot head clacking and drive-spinning noise; valid reference. |
| `03-event-28.80s.wav` | 28.80-30.95 s | Neptune title appears | Drive spinning and read sounds; valid reference. |
| `04-event-30.80s.wav` | 30.80-33.30 s | Static title screen | Drive read sound with different software-controlled cadence; valid reference. |
| `05-event-33.10s.wav` | 33.10-35.70 s | Static title screen | Drive spinning and read sounds; valid reference. |
| `06-event-35.50s.wav` | 35.50-39.60 s | Title/game-state transition | Contains non-drive game sounds at the end; exclude the clip from quantitative tuning. |

Only clips explicitly marked as valid references should influence `rtl/floppy_sound.sv`.

## Measured findings

Levels below are relative to the 350-650 Hz motor band, avoiding differences in recording gain.

| Interval | 100-350 Hz | 650-2200 Hz | 2200-6000 Hz |
|---|---:|---:|---:|
| Clip 02, boot clacking | -3.1 dB | +1.4 dB | +0.1 dB |
| Clips 03-05, spinning/read | -4.2 dB | -1.9 to -2.2 dB | -6.6 to -7.3 dB |
| Current 4x core capture | +2.7 to +3.8 dB | +0.6 to +1.1 dB | -4.8 to -5.4 dB |

The core has roughly 7 dB too much low-band energy relative to its motor tone. Its boot mechanical band is already close to the reference, but its step attacks lack about 5 dB of short 2.2-6 kHz energy. The repeated read cadences are software-controlled and should continue to come directly from real controller events.
