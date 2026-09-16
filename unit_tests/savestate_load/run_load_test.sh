#!/bin/sh
# Build + run the machine-level savestate LOAD harness.
#
# DUT: Apple-II_MiSTer/rtl/apple2_top.v (+define+SIM_FAST) +
#      Apple-II_MiSTer/rtl/savestates/savestate_manager.sv + the wrapper's RAM
#      fabric (two dpram, Verilog behavioral model from the verilog repo - the
#      active project's dpram is the VHDL altsyncram version, which Verilator
#      cannot compile; module_tests/dpram proves the Verilog model equivalent).
#
# Usage: from an MSYS2 UCRT64 shell:
#   sh run_load_test.sh                          # loads the Jungle Hunt state
#   sh run_load_test.sh "/path/to/file_1.ss"     # or any hardware .ss (131336 B)
#
# Setup facts honored (see AGENTS.md, "Unit-test ladder build setup" and the
# bare-cmd gotchas subsection):
#  - native mingw32-make via the `make` shim dir (the --binary link calls make)
#  - TMP/TEMP/TMPDIR exported inside this shell
#  - VERILATOR_ROOT exported (verilator 5.050 locates verilated_std.sv)
#  - pure self-driving SystemVerilog TB -> verilator --binary --timing
#  - build and run are chained in one invocation (fresh-PE AV window)
#  - the exe runs with CWD at the Apple-II_MiSTer root so ROM $readmemh paths
#    and the state hex path resolve
set -e
LVL=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$LVL/../.." && pwd)
VERILOG_REPO=$(cd "$REPO/../Apple-II-Verilog_MiSTer" && pwd)
SS_FILE=${1:-"$VERILOG_REPO/savestates/Apple-II/Jungle Hunt_1.ss"}

export TMP=/c/msys64/tmp
export TEMP=/c/msys64/tmp
export TMPDIR=/c/msys64/tmp
export VERILATOR_ROOT=/c/msys64/ucrt64/share/verilator
SHIM=/c/msys64/tmp/makeshim
mkdir -p "$SHIM"
cp -f /c/msys64/ucrt64/bin/mingw32-make.exe "$SHIM/make.exe"
PATH="$SHIM:$PATH"
V=/c/msys64/ucrt64/bin/verilator_bin.exe
OUT=$LVL/build

if [ ! -f "$SS_FILE" ]; then
  echo "ERROR: state file not found: $SS_FILE" >&2
  exit 1
fi
SZ=$(wc -c < "$SS_FILE")
if [ "$SZ" -ne 131336 ]; then
  echo "ERROR: state file is $SZ bytes, expected 131336 (131328 payload + 8 tail)" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/obj_dir"

# .ss -> one hex byte per line (bytes 0..131327 = the 128 KiB slot payload;
# the final 8-byte miosd tail is DDR data the manager never reads)
perl -e '
  my ($in, $out) = @ARGV;
  open my $fh, "<:raw", $in or die "open $in: $!";
  local $/;
  my $d = <$fh>;
  close $fh;
  my @b = unpack "C131328", $d;
  open my $oh, ">:raw", $out or die "open $out: $!";
  # $readmemb wants binary (0/1) per element: 8 chars per byte.
  printf $oh "%08b\n", $_ for @b;
  close $oh;
' "$SS_FILE" "$OUT/state.hex"
echo "state: $SS_FILE -> $OUT/state.hex ($(wc -l < "$OUT/state.hex") lines)"

cd "$REPO"
"$V" --binary --timing -O3 --x-assign fast --x-initial fast \
  -Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
  +define+SIM_FAST \
  --top-module tb_ss_load_machine \
  -Mdir "$OUT/obj_dir" \
  "$LVL/tb_ss_load_machine.sv" \
  "$REPO/rtl/apple2_top.v" \
  "$REPO/rtl/apple2.v" \
  "$REPO/rtl/rom.v" \
  "$REPO/rtl/ramcard.v" \
  "$REPO/rtl/timing_generator.v" \
  "$REPO/rtl/video_generator.v" \
  "$REPO/rtl/cpu/nmos6502/cpu_65c02.sv" \
  "$REPO/rtl/cpu/nmos6502/cpu_alu.sv" \
  "$REPO/rtl/cpu/wdc65c02/cpu_65c02.sv" \
  "$REPO/rtl/cpu/wdc65c02/cpu_alu.sv" \
  "$REPO/rtl/apple2_font_rom.v" \
  "$REPO/rtl/keyboard.v" \
  "$REPO/rtl/osk/joy_to_key.v" \
  "$REPO/rtl/video/video_pipeline.sv" \
  "$REPO/rtl/video/vga_controller.v" \
  "$REPO/rtl/video/apple_composite.sv" \
  "$REPO/rtl/video/composite_decoder.sv" \
  "$REPO/rtl/video/composite_decoder_v5a.sv" \
  "$REPO/rtl/woz/disk_ii_woz.sv" \
  "$REPO/rtl/woz/flux_drive.v" \
  "$REPO/rtl/woz/woz_bram.sv" \
  "$REPO/rtl/woz/woz_cell525.sv" \
  "$REPO/rtl/woz/woz_floppy_controller.sv" \
  "$REPO/rtl/woz/disk_ii_rom.v" \
  "$REPO/rtl/nsc_ticker.sv" \
  "$REPO/rtl/no_slot_clock.sv" \
  "$REPO/rtl/savestates/savestate_manager.sv" \
  "$VERILOG_REPO/rtl/dpram.v"
echo "=== running ==="
"$OUT/obj_dir/Vtb_ss_load_machine"
