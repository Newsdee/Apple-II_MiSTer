# FPGA Resource Utilization

This design targets the MiSTer Cyclone V `5CSEBA6U23I7`, which provides
41,910 Adaptive Logic Modules (ALMs), marketed as 110,000 logic elements
(LEs). Quartus reports Cyclone V logic utilization in ALMs; a fixed ALM-to-LE
conversion is only an approximation.

The fitted report used for this snapshot reports 19,812.0 ALMs needed, or
47.3% of the available ALMs. It includes the initial virtual keyboard but
predates the joystick-control and transparent-renderer changes. Refresh these
figures after the next complete compilation.

| High-level component | ALMs needed | Share of fitted design |
| --- | ---: | ---: |
| Apple II system (`apple2_top`) | 9,392.5 | 47.4% |
| HDD controller | 4,051.3 | 21.1% |
| Video scaler (`ascal`) | 1,962.5 | 9.9% |
| AppleMouse, two instances | 1,714.8 | 8.7% |
| Mockingboard, two instances | 1,319.1 | 6.7% |
| Apple II core | 1,175.8 | 5.9% |
| HDMI and VGA OSD | 1,071.7 | 5.4% |
| Audio output | 1,033.0 | 5.2% |
| Selectable 6502 and 65C02 implementations | 888.8 | 4.5% |
| Video mixer | 748.9 | 3.8% |
| VGA controller | 542.2 | 2.7% |

These rows are hierarchical and overlap. For example, the HDD controller,
AppleMouse instances, Mockingboards, and CPU implementations are already
included in `apple2_top`; the rows must not be added together.

## Mockingboard Configuration

The fitted hierarchy contains two Mockingboard instances, `mb_4` and `mb_5`.
Each instance contains two YM2149-compatible sound generators and two 6522
VIAs. Both instances are synthesized into the FPGA image.

## Source Report

Figures come from `output_files/Apple-II.fit.rpt`, section "Fitter Resource
Utilization by Entity". Use "ALMs needed" for component comparisons and the
top-level Quartus flow summary for authoritative whole-device utilization.