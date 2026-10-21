@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; & 'C:\Users\Hourz26\Desktop\Deepseek\qqbot-backup\backup-pull.ps1' *>&1 | Tee-Object -FilePath 'D:\qqbot-backups\logs\scheduler.log' -Append"