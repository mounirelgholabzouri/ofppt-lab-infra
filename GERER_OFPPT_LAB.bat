@echo off
title OFPPT-Lab - Gestion des VMs

set "PATH=%PATH%;C:\HashiCorp\Vagrant\bin;C:\Program Files\Oracle\VirtualBox"

:MENU
cls
echo.
echo ============================================================
echo   OFPPT-Lab - Gestionnaire de VMs
echo ============================================================
echo.
echo   1 - Voir le statut des VMs
echo   2 - Demarrer VM Cloud        (192.168.56.10)
echo   3 - Demarrer VM Reseau       (192.168.56.20)
echo   4 - Demarrer VM Cybersecurite (192.168.56.30)
echo   5 - Demarrer TOUTES les VMs
echo   6 - Connexion SSH vm-cloud
echo   7 - Connexion SSH vm-reseau
echo   8 - Connexion SSH vm-cyber
echo   9 - Arreter TOUTES les VMs
echo   0 - Quitter
echo.
set /p CHOICE="Votre choix [0-9] : "

cd /d "C:\ofppt-lab\vagrant"

if "%CHOICE%"=="1" ( vagrant status & pause & goto MENU )
if "%CHOICE%"=="2" ( vagrant up vm-cloud & pause & goto MENU )
if "%CHOICE%"=="3" ( vagrant up vm-reseau & pause & goto MENU )
if "%CHOICE%"=="4" ( vagrant up vm-cyber & pause & goto MENU )
if "%CHOICE%"=="5" ( vagrant up & pause & goto MENU )
if "%CHOICE%"=="6" ( vagrant ssh vm-cloud & pause & goto MENU )
if "%CHOICE%"=="7" ( vagrant ssh vm-reseau & pause & goto MENU )
if "%CHOICE%"=="8" ( vagrant ssh vm-cyber & pause & goto MENU )
if "%CHOICE%"=="9" ( vagrant halt & echo [OK] VMs arretees. & pause & goto MENU )
if "%CHOICE%"=="0" exit /b

echo Choix invalide.
pause
goto MENU
