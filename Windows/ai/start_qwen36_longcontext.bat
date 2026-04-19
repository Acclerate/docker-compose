@echo off
title Qwen3.6-35B Long Context Mode (Mixed KV: q8_0/turbo4)
echo ============================================================
echo  Qwen3.6-35B-A3B - Long Context Mode (Mixed KV)
echo  Port: 11436  KV: q8_0 K + turbo4 V  Speed: ~25 t/s
echo  Best for: Chat + Medium-Long Documents (8K+ context)
echo ============================================================

netstat -ano | findstr ":11436 " | findstr "LISTENING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [WARN] Port 11436 is in use, killing existing process...
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":11436 " ^| findstr "LISTENING"') do (
        taskkill /F /PID %%a >nul 2>&1
    )
    timeout /t 2 /nobreak >nul
)

cd /d D:\ai_tools\turboquant_llama\build\bin
if not exist llama-server.exe (
    echo [ERROR] llama-server.exe not found in D:\ai_tools\turboquant_llama\build\bin
    pause
    exit /b 1
)

echo Starting server for Claude Code...
llama-server.exe ^
  -m "D:\ai_models\llama-gguf\Qwen_Qwen3.6-35B-A3B-IQ4_XS.gguf" ^
  -ngl 99 ^
  -ot "exps=CPU" ^
  -fa 1 ^
  -t 8 ^
  -ctk q8_0 ^
  -ctv turbo4 ^
  -ub 2048 ^
  --host 0.0.0.0 ^
  --port 11436 ^
  --alias "Qwen3.6-35B-A3B" ^
  --jinja ^
  --ctx-size 131072 ^
  --temp 0.6 ^
  --top-p 0.95 ^
  --top-k 20 ^
  --min-p 0.0

echo.
echo [Server stopped]
pause
