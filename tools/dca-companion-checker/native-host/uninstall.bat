@echo off
setlocal

echo ============================================
echo D365 DCA Checker - Native Host Uninstaller
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

set "INSTALL_DIR=%ProgramFiles%\D365 DCA Checker"
set "HOST_NAME=com.microsoft.dynamics.dca.checker"

:: Remove registry entries
echo Removing Chrome registry entry...
reg delete "HKCU\Software\Google\Chrome\NativeMessagingHosts\%HOST_NAME%" /f >nul 2>&1

echo Removing Edge registry entry...
reg delete "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\%HOST_NAME%" /f >nul 2>&1

:: Remove files
echo Removing installation directory...
if exist "%INSTALL_DIR%" (
    rmdir /S /Q "%INSTALL_DIR%"
)

echo.
echo ============================================
echo Uninstallation complete!
echo ============================================
echo.
pause
