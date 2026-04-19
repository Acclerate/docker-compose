@echo off
setlocal enabledelayedexpansion
title Mixed KV Cache Benchmark Suite

set BENCH=D:\ai_tools\turboquant_llama\build\bin\llama-bench.exe
set MODEL=D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf
set COMMON=-m "%MODEL%" -ngl 99 -ot "exps=CPU" -fa 1 -t 8 -ub 2048 -r 3 -o csv
set OUTDIR=D:\ai_tools\bench_results

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo ============================================================
echo  Mixed KV Cache Benchmark Suite
echo  Model: Qwen3.6-35B-A3B IQ4_XS
echo  Date: %date% %time%
echo  Output: %OUTDIR%
echo ============================================================
echo.

REM Kill any existing llama-server
netstat -ano | findstr ":11436 " | findstr "LISTENING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [WARN] Killing existing server on port 11436...
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":11436 " ^| findstr "LISTENING"') do (
        taskkill /F /PID %%a >nul 2>&1
    )
    timeout /t 3 /nobreak >nul
)

REM Verify benchmark tool exists
if not exist "%BENCH%" (
    echo [ERROR] llama-bench.exe not found at %BENCH%
    pause
    exit /b 1
)

REM Verify model exists
if not exist "%MODEL%" (
    echo [ERROR] Model not found at %MODEL%
    pause
    exit /b 1
)

REM Record initial VRAM
echo [INFO] Initial VRAM state:
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv,noheader
echo.

REM ============================================================
REM C1: q8_0 K + q8_0 V (baseline)
REM ============================================================
echo [1/7] C1: q8_0 K + q8_0 V (baseline)...
echo === C1: q8_0/q8_0 === > "%OUTDIR%\bench_c1_q8k_q8v.csv"
%BENCH% %COMMON% -ctk q8_0 -ctv q8_0 -pg 512,128 -pg 2048,256 -pg 4096,128 >> "%OUTDIR%\bench_c1_q8k_q8v.csv" 2>"%OUTDIR%\stderr_c1.log"
if %ERRORLEVEL% NEQ 0 (
    echo [WARN] C1 may have OOM at larger context, retrying with smaller sizes...
    echo === C1 retry: pp512 only === > "%OUTDIR%\bench_c1_q8k_q8v.csv"
    %BENCH% %COMMON% -ctk q8_0 -ctv q8_0 -pg 512,128 -pg 2048,256 >> "%OUTDIR%\bench_c1_q8k_q8v.csv" 2>"%OUTDIR%\stderr_c1.log"
)
echo VRAM after C1: >> "%OUTDIR%\vram_summary.txt"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader >> "%OUTDIR%\vram_summary.txt"
echo C1 done.
timeout /t 5 /nobreak >nul

REM ============================================================
REM C2: q8_0 K + turbo4 V (conservative mix)
REM ============================================================
echo [2/7] C2: q8_0 K + turbo4 V (conservative mix)...
echo === C2: q8_0/turbo4 === > "%OUTDIR%\bench_c2_q8k_t4v.csv"
%BENCH% %COMMON% -ctk q8_0 -ctv turbo4 -pg 512,128 -pg 2048,256 -pg 8192,128 >> "%OUTDIR%\bench_c2_q8k_t4v.csv" 2>"%OUTDIR%\stderr_c2.log"
echo VRAM after C2: >> "%OUTDIR%\vram_summary.txt"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader >> "%OUTDIR%\vram_summary.txt"
echo C2 done.
timeout /t 5 /nobreak >nul

REM ============================================================
REM C3: q8_0 K + turbo3 V (balanced mix)
REM ============================================================
echo [3/7] C3: q8_0 K + turbo3 V (balanced mix)...
echo === C3: q8_0/turbo3 === > "%OUTDIR%\bench_c3_q8k_t3v.csv"
%BENCH% %COMMON% -ctk q8_0 -ctv turbo3 -pg 512,128 -pg 2048,256 -pg 8192,128 >> "%OUTDIR%\bench_c3_q8k_t3v.csv" 2>"%OUTDIR%\stderr_c3.log"
echo VRAM after C3: >> "%OUTDIR%\vram_summary.txt"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader >> "%OUTDIR%\vram_summary.txt"
echo C3 done.
timeout /t 5 /nobreak >nul

REM ============================================================
REM C4: q8_0 K + turbo2 V (extreme V compression)
REM ============================================================
echo [4/7] C4: q8_0 K + turbo2 V (extreme V compression)...
echo === C4: q8_0/turbo2 === > "%OUTDIR%\bench_c4_q8k_t2v.csv"
%BENCH% %COMMON% -ctk q8_0 -ctv turbo2 -pg 512,128 -pg 2048,256 -pg 8192,128 >> "%OUTDIR%\bench_c4_q8k_t2v.csv" 2>"%OUTDIR%\stderr_c4.log"
echo VRAM after C4: >> "%OUTDIR%\vram_summary.txt"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader >> "%OUTDIR%\vram_summary.txt"
echo C4 done.
timeout /t 5 /nobreak >nul

REM ============================================================
REM C5: turbo4 K + turbo4 V (current long context mode)
REM ============================================================
echo [5/7] C5: turbo4 K + turbo4 V (current long context)...
echo === C5: turbo4/turbo4 === > "%OUTDIR%\bench_c5_t4k_t4v.csv"
%BENCH% %COMMON% -ctk turbo4 -ctv turbo4 -pg 512,128 -pg 2048,256 -pg 8192,128 >> "%OUTDIR%\bench_c5_t4k_t4v.csv" 2>"%OUTDIR%\stderr_c5.log"
echo VRAM after C5: >> "%OUTDIR%\vram_summary.txt"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader >> "%OUTDIR%\vram_summary.txt"
echo C5 done.
timeout /t 5 /nobreak >nul

REM ============================================================
REM C6: turbo3 K + turbo3 V (max compression)
REM ============================================================
echo [6/7] C6: turbo3 K + turbo3 V (max compression)...
echo === C6: turbo3/turbo3 === > "%OUTDIR%\bench_c6_t3k_t3v.csv"
%BENCH% %COMMON% -ctk turbo3 -ctv turbo3 -pg 512,128 -pg 2048,256 -pg 8192,128 >> "%OUTDIR%\bench_c6_t3k_t3v.csv" 2>"%OUTDIR%\stderr_c6.log"
echo VRAM after C6: >> "%OUTDIR%\vram_summary.txt"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader >> "%OUTDIR%\vram_summary.txt"
echo C6 done.
timeout /t 5 /nobreak >nul

REM ============================================================
REM C7: turbo4 K + turbo3 V (cross-compression)
REM ============================================================
echo [7/7] C7: turbo4 K + turbo3 V (cross-compression)...
echo === C7: turbo4/turbo3 === > "%OUTDIR%\bench_c7_t4k_t3v.csv"
%BENCH% %COMMON% -ctk turbo4 -ctv turbo3 -pg 512,128 -pg 2048,256 -pg 8192,128 >> "%OUTDIR%\bench_c7_t4k_t3v.csv" 2>"%OUTDIR%\stderr_c7.log"
echo VRAM after C7: >> "%OUTDIR%\vram_summary.txt"
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader >> "%OUTDIR%\vram_summary.txt"
echo C7 done.

echo.
echo ============================================================
echo  All 7 benchmarks complete!
echo  Results in: %OUTDIR%
echo  CSV files:  bench_c*.csv
echo  VRAM log:   vram_summary.txt
echo  Stderr logs: stderr_c*.log
echo ============================================================
echo.
echo Key columns in CSV: type_k, type_v, n_prompt, n_gen, avg_ts
echo.
pause
