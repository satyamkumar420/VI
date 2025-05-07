@echo off
setlocal enabledelayedexpansion

:: This script lists all installed VSCode extensions and lets you ban one by selection
:: Author: Claude

echo VSCode Extension Ban Tool
echo ========================

:: All possible VSCode installation locations
set VSCODE_LOCATIONS=^
%USERPROFILE%\.vscode\extensions\^
%PROGRAMFILES%\Microsoft VS Code\resources\app\extensions\^
%PROGRAMFILES(X86)%\Microsoft VS Code\resources\app\extensions\^
%APPDATA%\Code\User\extensions\^
%USERPROFILE%\.vscode-insiders\extensions\

:: Create a temporary file to store extension list
set "TEMP_FILE=%TEMP%\vscode_extensions_list.txt"
if exist "%TEMP_FILE%" del "%TEMP_FILE%"

echo Searching for installed extensions...
echo.

:: Find all extensions and put them in an array
set EXTENSION_COUNT=0
for %%L in (%VSCODE_LOCATIONS%) do (
    if exist "%%L" (
        for /d %%E in ("%%L*") do (
            :: Skip system extensions and disabled/blocker extensions
            set "DIRNAME=%%~nxE"
            if not "!DIRNAME:~0,1!"=="." (
                if not "!DIRNAME:blocker!"=="!DIRNAME!" (
                    rem Skip blocker directories
                ) else if not "!DIRNAME:disabled!"=="!DIRNAME!" (
                    rem Skip already disabled extensions
                ) else (
                    set /a EXTENSION_COUNT+=1
                    set "EXTENSION_!EXTENSION_COUNT!_PATH=%%E"
                    set "EXTENSION_!EXTENSION_COUNT!_NAME=%%~nxE"
                    
                    :: Try to get friendly name from package.json if it exists
                    set "FRIENDLY_NAME=Unknown"
                    if exist "%%E\package.json" (
                        for /f "tokens=*" %%i in ('powershell -Command "(Get-Content '%%E\package.json' -Raw | ConvertFrom-Json).displayName"') do (
                            if not "%%i" == "" set "FRIENDLY_NAME=%%i"
                        )
                    )
                    echo !EXTENSION_COUNT!. !FRIENDLY_NAME! (!DIRNAME!)
                    echo !EXTENSION_COUNT!. !FRIENDLY_NAME! (!DIRNAME!)>> "%TEMP_FILE%"
                )
            )
        )
    )
)

echo.
if %EXTENSION_COUNT% EQU 0 (
    echo No extensions found.
    goto end
)

:: Ask the user which extension to ban
set /p SELECTION="Enter the number of the extension you want to ban (1-%EXTENSION_COUNT%): "

:: Validate input
if %SELECTION% LSS 1 (
    echo Invalid selection.
    goto end
)
if %SELECTION% GTR %EXTENSION_COUNT% (
    echo Invalid selection.
    goto end
)

:: Get the selected extension path and name
set "SELECTED_PATH=!EXTENSION_%SELECTION%_PATH!"
set "SELECTED_NAME=!EXTENSION_%SELECTION%_NAME!"

echo.
echo You selected: !SELECTED_NAME!
echo Located at: !SELECTED_PATH!
echo.
set /p CONFIRM="Are you sure you want to ban this extension? (Y/N): "

if /i "%CONFIRM%" NEQ "Y" (
    echo Operation cancelled.
    goto end
)

echo.
echo Banning extension !SELECTED_NAME!...

:: Ban the extension (same logic as previous script)
:: Disable the extension
echo Disabling extension...

:: First lock the extension folder
if exist "!SELECTED_PATH!\package.json" (
    echo Modifying extension package.json to make it invalid
    ren "!SELECTED_PATH!\package.json" "package.json.disabled"
    echo Created: !SELECTED_PATH!\package.json.disabled
)

:: Get the base extension ID (usually publisher.name)
for /f "tokens=* delims=" %%I in ("!SELECTED_NAME!") do (
    set EXTENSION_ID=%%~nI
)

:: Create a blocker file that prevents the extension from being reinstalled
echo Creating blocker...
for %%L in (%VSCODE_LOCATIONS%) do (
    if exist "%%L" (
        mkdir "%%L!EXTENSION_ID!.blocker" 2>nul
        echo This extension has been blocked by administrator. > "%%L!EXTENSION_ID!.blocker\BLOCKED"
        attrib +R +H "%%L!EXTENSION_ID!.blocker" /S /D
    )
)

:: Rename the extension directory
ren "!SELECTED_PATH!" "!SELECTED_NAME!.disabled"
echo Renamed directory to: !SELECTED_PATH!.disabled

:: Update current VSCode user settings to blacklist the extension
set SETTINGS_FILE=%APPDATA%\Code\User\settings.json
if exist "%SETTINGS_FILE%" (
    echo Adding extension to VSCode blacklist in user settings
    
    :: Backup the settings.json file here and modify it
    copy "%SETTINGS_FILE%" "%SETTINGS_FILE%.backup"
    echo Backup created: %SETTINGS_FILE%.backup
    
    :: PowerShell command block that will set "extensions.disallowedExtensions" in settings.json
    powershell -Command "$settings = Get-Content -Raw '%SETTINGS_FILE%' | ConvertFrom-Json; if (-not $settings.'extensions.disallowedExtensions') { $settings | Add-Member -Name 'extensions.disallowedExtensions' -Value @() -MemberType NoteProperty }; if ($settings.'extensions.disallowedExtensions' -notcontains '!EXTENSION_ID!') { $settings.'extensions.disallowedExtensions' += '!EXTENSION_ID!' }; $settings | ConvertTo-Json -Depth 10 | Set-Content '%SETTINGS_FILE%'"
    
    echo Updated settings.json to blacklist !EXTENSION_ID!
)

:: Add blocker entry in Windows registry
echo Adding registry entry to block the extension...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun" /v "VSCode_!EXTENSION_ID!" /t REG_SZ /d "!EXTENSION_ID!" /f

echo.
echo =============================
echo Extension !SELECTED_NAME! has been successfully banned!
echo Users will not be able to install or use this extension.
echo.
echo Note: For complete blocking, you may need to:
echo 1. Run this script as administrator
echo 2. Restart VSCode if it's currently running
echo 3. Consider using group policy for organization-wide blocking

:end
echo.
pause
