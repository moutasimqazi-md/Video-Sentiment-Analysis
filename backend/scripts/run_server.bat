@echo off
cd /d %~dp0..
:loop
".venv\Scripts\python.exe" -m uvicorn neurolens.main:app --host 0.0.0.0 --port 8000
echo [%date% %time%] server exited, restarting in 5s >> data\server_restarts.log
ping -n 6 127.0.0.1 >nul
goto loop
