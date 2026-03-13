@echo off
:: Auto-commit and push script for ofppt-lab-infra
:: Runs every 30 minutes via Windows Task Scheduler

set REPO_DIR=C:\Users\Administrateur\Desktop\ofppt-lab
set LOG_FILE=C:\Users\Administrateur\Desktop\ofppt-lab\tmp\auto_git.log

:: Create tmp dir if needed
if not exist "%REPO_DIR%\tmp" mkdir "%REPO_DIR%\tmp"

cd /d "%REPO_DIR%"

:: Check if there are changes
git status --porcelain > nul 2>&1
if "%ERRORLEVEL%" NEQ "0" (
    echo [%DATE% %TIME%] ERROR: git status failed >> "%LOG_FILE%"
    exit /b 1
)

:: Get list of changes
for /f "delims=" %%i in ('git status --porcelain') do set HAS_CHANGES=1

if not defined HAS_CHANGES (
    echo [%DATE% %TIME%] No changes to commit >> "%LOG_FILE%"
    exit /b 0
)

:: Stage all changes
git add -A

:: Commit with timestamp
set TIMESTAMP=%DATE% %TIME%
git commit -m "Auto-commit: %TIMESTAMP%"

if "%ERRORLEVEL%" NEQ "0" (
    echo [%DATE% %TIME%] ERROR: commit failed >> "%LOG_FILE%"
    exit /b 1
)

:: Push to GitHub
git push origin master

if "%ERRORLEVEL%" NEQ "0" (
    echo [%DATE% %TIME%] ERROR: push failed >> "%LOG_FILE%"
    exit /b 1
)

echo [%DATE% %TIME%] Auto-commit and push successful >> "%LOG_FILE%"
exit /b 0
