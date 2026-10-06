@echo off
cd /d %~dp0..
:loop
"C:\Users\User\AppData\Local\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe" http 8000 --log=stdout
echo [%date% %time%] ngrok exited, restarting in 5s >> data\ngrok_restarts.log
ping -n 6 127.0.0.1 >nul
goto loop
