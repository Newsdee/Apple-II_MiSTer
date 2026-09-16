@echo off
rem ============================================================
rem v3g: F5-LOAD re-anchor verification (build + run)
rem
rem   [1/4] probe g++  - detects the AV compiler block early
rem   [2/4] make shim  - Verilator's link step calls bare make
rem   [3/4] Verilator build of the 4-check regression TB
rem   [4/4] run the TB
rem
rem Label-based flow on purpose: parenthesized if-blocks with
rem literal parentheses in echo text break cmd's parser.
rem
rem Environment gotchas (see AGENTS.md, "Verilator harness builds
rem from bare cmd"): ucrt64 bin on PATH for the MSYS2 PE DLLs
rem (libgmp-10.dll etc.), usr/bin on PATH + SHELL for make's
rem POSIX recipe shell, VERILATOR_ROOT for verilated_std.sv.
rem
rem Expected when the compiler is unblocked:
rem   Check 1 PASS  line_len=912 x8, hs_rises=786
rem   Check 2 PASS  contrast present, black clamp on porch
rem   Check 3 PASS  phase@sync = 00000000 x6  locked edges hpos 911
rem                 PHASE_AT_SYNC_RISE = 24'h000000, constant, value match
rem   Check 4 PASS  clean4=00400000 post4=00400000 diff=00000000
rem   summary: fails=0
rem ============================================================

setlocal

cd /d E:\MiSTer\Apple-II_FPGAdev\Apple-II_MiSTer

rem ucrt64 bin: g++.exe / verilator_bin.exe / linked exe are MSYS2 PEs
rem that need sibling DLLs (libgmp-10.dll etc.) on PATH from bare cmd.
rem usr/bin: mingw32-make needs sh.exe on PATH for verilated.mk's
rem POSIX recipes; without it make falls back to cmd.exe and the
rem __ALL.a archive step dies with "0 was unexpected at this time".
set PATH=C:\msys64\ucrt64\bin;C:\msys64\usr\bin;C:\msys64\tmp\makeshim;%PATH%
set SHELL=C:\msys64\usr\bin\sh
set VERILATOR_ROOT=C:\msys64\ucrt64\share\verilator
set VERILATOR=C:\msys64\ucrt64\bin\verilator_bin.exe
set GXX=C:\msys64\ucrt64\bin\g++.exe

echo.
echo === [1/4] compiler probe  AV-block check ===
> C:\Temp\v3g_probe.c echo int main(){return 0;}
%GXX% -c -o C:\Temp\v3g_probe.o C:\Temp\v3g_probe.c
if errorlevel 1 goto :probe_failed
del /q C:\Temp\v3g_probe.c C:\Temp\v3g_probe.o 2>nul
echo PROBE OK: g++ compiles.
goto :step2

:probe_failed
del /q C:\Temp\v3g_probe.c C:\Temp\v3g_probe.o 2>nul
echo PROBE FAILED: g++ is blocked by the host AV, or its DLLs are missing.
echo Verilator parse and lint still work, but the C++ compile and link cannot.
echo Re-run this .bat later.
goto :end

:step2
echo.
echo === [2/4] make shim + recipe shell ===
if not exist C:\msys64\tmp\makeshim\make.exe goto :make_shim
echo shim present.
if not exist C:\msys64\usr\bin\sh.exe goto :no_sh
echo recipe shell present.
goto :step3

:make_shim
echo creating C:\msys64\tmp\makeshim\make.exe ...
mkdir C:\msys64\tmp\makeshim 2>nul
copy /y C:\msys64\ucrt64\bin\mingw32-make.exe C:\msys64\tmp\makeshim\make.exe >nul
if not exist C:\msys64\usr\bin\sh.exe goto :no_sh
goto :step3

:no_sh
echo ERROR: C:\msys64\usr\bin\sh.exe missing - MSYS2 not installed?
goto :end

:step3
echo.
echo === [3/4] Verilator build  fresh Mdir tools\obj_dir_v3g ===
if exist tools\obj_dir_v3g rd /s /q tools\obj_dir_v3g
%VERILATOR% --binary --timing -sv -Wall -Wno-fatal --top tb_v5_regress ^
  --Mdir tools\obj_dir_v3g -o tb_v5 ^
  tools\tb_v5_regress.sv rtl\video\apple_composite.sv ^
  rtl\video\composite_decoder.sv rtl\video\composite_decoder_v5a.sv
if errorlevel 1 goto :build_failed
echo build OK.
goto :step4

:build_failed
echo.
echo BUILD FAILED - see errors above.
goto :end

:step4
echo.
echo === [4/4] run regression TB ===
tools\obj_dir_v3g\tb_v5.exe > tools\v3g_tb_run.log 2>&1
set TBEXIT=%errorlevel%
echo.
type tools\v3g_tb_run.log
echo.
echo TB exit code: %TBEXIT%   0 means all checks passed

:end
endlocal
echo.
pause
