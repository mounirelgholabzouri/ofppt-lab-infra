@echo off
title OFPPT-Lab - Installation
set "LOG=%USERPROFILE%\Desktop\ofppt_install_log.txt"

echo Installation OFPPT-Lab > "%LOG%"
echo Date : %DATE% %TIME% >> "%LOG%"

echo.
echo ============================================================
echo   OFPPT-Lab - Installation Automatique
echo ============================================================
echo.

:: Verification droits admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERREUR] Droits admin requis - Clic droit + Executer en tant qu'administrateur
    echo ERREUR: pas droits admin >> "%LOG%"
    pause
    exit /b 1
)
echo [OK] Droits administrateur confirmes
echo [OK] Droits admin >> "%LOG%"

:: ----------------------------------------------------------
:: ETAPE 1 - VirtualBox
:: ----------------------------------------------------------
echo.
echo [1/5] Verification VirtualBox...
set "PATH=%PATH%;C:\Program Files\Oracle\VirtualBox"
VBoxManage --version >nul 2>&1
if %errorLevel% equ 0 (
    echo [OK] VirtualBox OK
    echo [OK] VirtualBox >> "%LOG%"
) else (
    echo [ERREUR] VirtualBox non trouve - Installez depuis virtualbox.org
    echo ERREUR VirtualBox >> "%LOG%"
    pause & exit /b 1
)

:: ----------------------------------------------------------
:: ETAPE 2 - Vagrant
:: ----------------------------------------------------------
echo.
echo [2/5] Verification Vagrant...
set "PATH=%PATH%;C:\HashiCorp\Vagrant\bin"
vagrant --version >nul 2>&1
if %errorLevel% equ 0 (
    echo [OK] Vagrant OK
    echo [OK] Vagrant >> "%LOG%"
) else (
    echo [..] Vagrant absent - Installation via winget...
    winget install HashiCorp.Vagrant --silent >nul 2>&1
    if %errorLevel% equ 0 (
        echo [OK] Vagrant installe via winget
        echo [OK] Vagrant installe winget >> "%LOG%"
        set "PATH=%PATH%;C:\HashiCorp\Vagrant\bin"
    ) else (
        echo [..] winget echoue - Telechargement direct...
        powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest 'https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9_windows_amd64.msi' -OutFile '%TEMP%\vagrant.msi' -UseBasicParsing"
        msiexec /i "%TEMP%\vagrant.msi" /qn /norestart
        set "PATH=%PATH%;C:\HashiCorp\Vagrant\bin"
        echo [OK] Vagrant installe - Redemarrer le PC si erreur
        echo [OK] Vagrant installe msi >> "%LOG%"
    )
)

:: ----------------------------------------------------------
:: ETAPE 3 - Git
:: ----------------------------------------------------------
echo.
echo [3/5] Verification Git...
set "PATH=%PATH%;C:\Program Files\Git\bin;C:\Program Files\Git\cmd"
git --version >nul 2>&1
if %errorLevel% equ 0 (
    echo [OK] Git OK
    echo [OK] Git >> "%LOG%"
) else (
    echo [..] Git absent - Installation via winget...
    winget install Git.Git --silent >nul 2>&1
    if %errorLevel% equ 0 (
        echo [OK] Git installe via winget
        echo [OK] Git installe winget >> "%LOG%"
        set "PATH=%PATH%;C:\Program Files\Git\bin;C:\Program Files\Git\cmd"
    ) else (
        echo [..] winget echoue - Telechargement direct (~50Mo)...
        powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest 'https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.2/Git-2.53.0.2-64-bit.exe' -OutFile '%TEMP%\git_setup.exe' -UseBasicParsing"
        if exist "%TEMP%\git_setup.exe" (
            "%TEMP%\git_setup.exe" /VERYSILENT /NORESTART /NOCANCEL /SP-
            set "PATH=%PATH%;C:\Program Files\Git\bin;C:\Program Files\Git\cmd"
            echo [OK] Git installe
            echo [OK] Git installe exe >> "%LOG%"
        ) else (
            echo [ERREUR] Telechargement Git echoue - Verifier connexion Internet
            echo ERREUR Git telechargement >> "%LOG%"
            pause & exit /b 1
        )
    )
)

:: ----------------------------------------------------------
:: ETAPE 4 - Copie projet
:: ----------------------------------------------------------
echo.
echo [4/5] Copie du projet dans C:\ofppt-lab...
set "SOURCE=%~dp0ofppt-lab"
set "DEST=C:\ofppt-lab"
echo Source: %SOURCE% >> "%LOG%"

if exist "%DEST%\vagrant\Vagrantfile" (
    echo [OK] Projet deja dans C:\ofppt-lab
    echo [OK] Projet deja present >> "%LOG%"
) else (
    if exist "%SOURCE%\vagrant\Vagrantfile" (
        xcopy "%SOURCE%" "%DEST%" /E /I /Y /Q
        echo [OK] Projet copie dans C:\ofppt-lab
        echo [OK] Projet copie >> "%LOG%"
    ) else (
        echo [ERREUR] Dossier ofppt-lab introuvable sur le Bureau
        echo [ERREUR] Chemin cherche : %SOURCE%
        echo ERREUR: ofppt-lab absent >> "%LOG%"
        pause & exit /b 1
    )
)

:: ----------------------------------------------------------
:: ETAPE 5 - Choix et lancement VM
:: ----------------------------------------------------------
echo.
echo [5/5] Lancement des VMs
echo.
echo ============================================================
echo   1 - VM Cloud       (Docker, Terraform, Azure CLI) - 4Go
echo   2 - VM Reseau      (Wireshark, GNS3, VPN)        - 3Go
echo   3 - VM Cyber       (Metasploit, Nmap, DVWA)      - 4Go
echo   4 - TOUTES les VMs                               - 11Go
echo   5 - Quitter
echo ============================================================
echo.
set /p CHOICE="Votre choix [1-5] : "
echo Choix: %CHOICE% >> "%LOG%"

cd /d "C:\ofppt-lab\vagrant"

if "%CHOICE%"=="1" (
    echo [..] Demarrage vm-cloud (20-30 min la 1ere fois)...
    vagrant up vm-cloud
    echo [OK] vm-cloud >> "%LOG%"
    goto FIN
)
if "%CHOICE%"=="2" (
    echo [..] Demarrage vm-reseau...
    vagrant up vm-reseau
    echo [OK] vm-reseau >> "%LOG%"
    goto FIN
)
if "%CHOICE%"=="3" (
    echo [..] Demarrage vm-cyber...
    vagrant up vm-cyber
    echo [OK] vm-cyber >> "%LOG%"
    goto FIN
)
if "%CHOICE%"=="4" (
    echo [..] Demarrage de toutes les VMs (30-45 min)...
    vagrant up
    echo [OK] all VMs >> "%LOG%"
    goto FIN
)

:FIN
echo.
echo ============================================================
echo   Termine ! Projet dans C:\ofppt-lab
echo ============================================================
echo.
pause
