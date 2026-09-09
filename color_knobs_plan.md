# Apple II FPGA Color Knobs Plan

## Goal

Add adjustable NTSC-style color controls without generating and decoding a
synthetic composite waveform. Gamma remains handled by the existing MiSTer
video pipeline.

The Apple II artifact decoder already reduces each stable four-bit video
pattern to one of 16 color indices. Therefore, recalculate a 16-entry RGB
palette only when a knob changes instead of applying expensive arithmetic to
every output pixel.

```text
Apple video pattern -> color index -> generated 16-entry RGB palette -> filters -> gamma
```

## Knobs

The JS palette tool exposes these controls, excluding gamma:

1. Brightness: adds an offset to the decoded signal.
2. Picture (contrast): scales the decoded signal.
3. Color (saturation): scales chroma magnitude.
4. Hue: rotates the two chroma axes.
5. Subcarrier phase: adds a fixed color phase offset.
6. Chroma bandwidth: scales the ideal square-wave chroma fundamental.
7. Differential phase: changes hue in proportion to luma.

For this static 16-color model, some controls reduce to shared mathematical
parameters:

$$
\theta = \mathrm{hue} + \mathrm{phase} + \mathrm{diffphase}\,Y
$$

$$
C_{gain} = \mathrm{color}\,\mathrm{bandwidth}
$$

The hardware therefore fundamentally needs:

- Brightness
- Contrast
- Chroma gain
- Base hue/phase
- Differential phase

The eventual UI may still expose all seven controls while mapping them onto
these five internal parameters.

## Per-Color Mathematics

Store fixed base $Y$, $U$, and $V$ values for each of the 16 Apple II signal
patterns in a small ROM.

For each palette entry, calculate the effective phase and chroma amplitude:

$$
\begin{aligned}
\theta &= H + P + D Y \\
U_0 &= U(CB) \\
V_0 &= V(CB)
\end{aligned}
$$

where $C$ is saturation and $B$ is chroma bandwidth.

Rotate the chroma axes:

$$
\begin{aligned}
U' &= U_0\cos\theta - V_0\sin\theta \\
V' &= V_0\cos\theta + U_0\sin\theta
\end{aligned}
$$

Convert YUV to RGB using the same coefficients as the JS model:

$$
\begin{aligned}
R &= Y + 1.14V' \\
B &= Y + 2.03U' \\
G &= \frac{Y - 0.299R - 0.114B}{0.587}
\end{aligned}
$$

Apply picture and brightness, then clamp each channel:

$$
\begin{aligned}
R' &= \operatorname{clamp}(RK + B_r) \\
G' &= \operatorname{clamp}(GK + B_r) \\
B' &= \operatorname{clamp}(BK + B_r)
\end{aligned}
$$

Here $K$ is picture/contrast and $B_r$ is brightness. The generated values
feed the existing filtering and gamma stages.

## Proposed Hardware

Use a small iterative palette-generation unit that runs only after a control
changes. It can reuse arithmetic resources across all 16 colors:

- One multiplier
- One adder/subtractor datapath
- A small sine/cosine lookup table
- ROM constants for the 16 base YUV colors
- A 16 x 24-bit generated RGB palette RAM
- Approximately 12 to 16 bits of signed fixed-point internal precision

No per-pixel multipliers should be required. Normal rendering remains a color
index lookup, so the additional latency in the active video path should be
negligible.

## Staged Implementation

1. Implement brightness, contrast, saturation, and hue.
2. Verify neutral settings reproduce the current NTSC palette closely.
3. Compare generated colors against the JS tool over representative settings.
4. Add separate subcarrier phase and chroma-bandwidth controls if their
   duplicated UI behavior is still useful.
5. Add differential phase after the basic fixed-point implementation is
   validated.
6. Design controls and a possible core-local OSD separately; do not allocate
   additional MiSTer status bits during the mathematics prototype.

## Validation

- Neutral controls must reproduce the expected neutral palette within a small
  per-channel rounding tolerance.
- Optimal JS knob values should produce comparable 16-color RGB output.
- Test minimum and maximum controls for overflow and correct clamping.
- Confirm monochrome modes and sync/blanking alignment remain unchanged.
- Confirm the existing sharpness and vertical-comb options continue to operate
  on the generated palette output.