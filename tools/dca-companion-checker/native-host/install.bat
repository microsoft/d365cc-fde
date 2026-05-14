@echo off
setlocal EnableDelayedExpansion

echo ============================================
echo D365 DCA Checker - Native Host Installer
echo ============================================
echo.

:: Check for admin privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: This script requires administrator privileges.
    echo Please right-click and select "Run as administrator"
    pause
    exit /b 1
)

:: Set variables
set "INSTALL_DIR=%ProgramFiles%\D365 DCA Checker"
set "HOST_NAME=com.microsoft.dynamics.dca.checker"
set "MANIFEST_FILE=%HOST_NAME%.json"
set "HOST_FILE=dca-checker-host.exe"

:: Create installation directory
echo Creating installation directory...
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
)

:: Copy files
echo Copying files...
copy /Y "%~dp0%HOST_FILE%" "%INSTALL_DIR%\" >nul 2>&1
if !errorLevel! neq 0 (
    echo WARNING: Could not copy host executable. Copying JS version...
    copy /Y "%~dp0dca-checker-host.js" "%INSTALL_DIR%\" >nul 2>&1
)

:: Create manifest with correct path
echo Creating manifest file...
(
echo {
echo   "name": "%HOST_NAME%",
echo   "description": "Native messaging host for D365 DCA Companion Checker",
echo   "path": "%INSTALL_DIR:\=\\%\\%HOST_FILE%",
echo   "type": "stdio",
echo   "allowed_origins": [
echo     "chrome-extension://*/",
echo     "edge-extension://*/"
echo   ]
echo }
) > "%INSTALL_DIR%\%MANIFEST_FILE%"

:: Register with Chrome
echo Registering with Google Chrome...
reg add "HKCU\Software\Google\Chrome\NativeMessagingHosts\%HOST_NAME%" /ve /t REG_SZ /d "%INSTALL_DIR%\%MANIFEST_FILE%" /f >nul 2>&1

:: Register with Edge
echo Registering with Microsoft Edge...
reg add "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\%HOST_NAME%" /ve /t REG_SZ /d "%INSTALL_DIR%\%MANIFEST_FILE%" /f >nul 2>&1

:: Verify installation
echo.
echo Verifying installation...
if exist "%INSTALL_DIR%\%MANIFEST_FILE%" (
    echo [OK] Manifest file created
) else (
    echo [FAIL] Manifest file not found
)

reg query "HKCU\Software\Google\Chrome\NativeMessagingHosts\%HOST_NAME%" >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] Chrome registry entry created
) else (
    echo [WARN] Chrome registry entry not created
)

reg query "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\%HOST_NAME%" >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] Edge registry entry created
) else (
    echo [WARN] Edge registry entry not created
)

echo.
echo ============================================
echo Installation complete!
echo ============================================
echo.
echo Please restart your browser for changes to take effect.
echo.
pause
