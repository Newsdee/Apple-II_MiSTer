@echo off
rem ============================================================
rem Savestate machine-LOAD harness: build + run (chained).
rem Usage:  run_load_test.bat [path-to-file_1.ss]
rem   (default: Apple-II-Verilog_MiSTer savestates\Apple-II\Jungle Hunt_1.ss)
rem Re-runs the whole build+run in one invocation (AV fresh-PE window).
rem Log:    unit_tests\savestate_load\load_tb_run.log
rem ============================================================
setlocal
cd /d E:\MiSTer\Apple-II_FPGAdev\Apple-II_MiSTer
set PATH=C:\msys64\ucrt64\bin;C:\msys64\usr\bin;C:\msys64\tmp\makeshim;%PATH%
set SHELL=C:\msys64\usr\bin\sh
set VERILATOR_ROOT=C:\msys64\ucrt64\share\verilator
set TMP=C:\msys64\tmp
set TEMP=C:\msys64\tmp
set TMPDIR=C:\msys64\tmp

echo [1/3] g++ probe...
C:\msys64\ucrt64\bin\gcc.exe -o C:\Temp\ssload_probe.exe C:\Temp\hello_ssload.c
if errorlevel 1 goto gpp_blocked
echo     ok
goto gpp_done
:gpp_blocked
echo g++ is being blocked by the AV/endpoint agent (compile killed).
echo Wait a few minutes and re-run this .bat.
echo (AGENTS.md Phase-2: do not fight the AV.)
pause
exit /b 1
:gpp_done

echo [2/3] make shim + sh check...
if not exist C:\msys64\tmp\makeshim mkdir C:\msys64\tmp\makeshim
copy /y C:\msys64\ucrt64\bin\mingw32-make.exe C:\msys64\tmp\makeshim\make.exe >nul
if not exist C:\msys64\usr\bin\sh.exe goto no_sh
echo     ok
goto sh_done
:no_sh
echo C:\msys64\usr\bin\sh.exe not found - install it in MSYS2 (pacman -S bash).
pause
exit /b 1
:sh_done

echo [3/3] build + run (chained, takes a few minutes)...
C:\msys64\usr\bin\sh.exe unit_tests\savestate_load\run_load_test.sh %1 > unit_tests\savestate_load\load_tb_run.log 2>&1
echo === tail of log ===
powershell -NoProfile -Command "Get-Content unit_tests\savestate_load\load_tb_run.log -Tail 40"
pause
