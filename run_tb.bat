@echo off
setlocal enabledelayedexpansion

rem Paths
set "ROOT=%~dp0"
set "DESIGN=%ROOT%design"
set "TB_DIR=%ROOT%testbench"
set "RUN=%ROOT%run"
set "SIGNAL_FILE="

rem Deps
where iverilog >nul 2>nul || (echo ERROR: iverilog not found in PATH. & exit /b 1)
where vvp >nul 2>nul || (echo ERROR: vvp not found in PATH. & exit /b 1)
for %%G in (gtkwave.exe gtkwave) do (
    where %%G >nul 2>nul && set "GTKWAVE_BIN=%%G"
)

if not exist "%RUN%" mkdir "%RUN%"

:select_design
echo === Select Design (Top-Level) ===
set i=0
for %%F in ("%DESIGN%\*.sv" "%DESIGN%\*.v") do (
    if exist "%%~fF" (
        set /a i+=1
        set "DESIGN_!i!=%%~fF"
        echo !i!: %%~fF
    )
)
if %i%==0 (
    echo No design files in %DESIGN%
    exit /b 1
)
set /p sel=Enter option:
if not defined DESIGN_%sel% (
    echo Invalid option.
    goto select_design
)
set "DESIGN_FILE=!DESIGN_%sel%!"
echo Design: %DESIGN_FILE%

:select_signals
set "SIGNAL_FILE="
echo.
echo === Select GTKWave signal list (optional) ===
set k=0
for /f "delims=" %%F in ('dir /b /a-d "%RUN%\*.gtkw" "%RUN%\*.sav" "%RUN%\*signals*" 2^>nul ^| sort /unique') do (
    set /a k+=1
    set "SIG_!k!=%%~fF"
    echo !k!: %%~fF
)
echo 0: Continue without signal list
set /p sel_sig=Enter option:
if "%sel_sig%"=="0" goto :after_signals
if defined SIG_%sel_sig% (
    for /f "delims=" %%S in ("!SIG_%sel_sig%!") do set "SIGNAL_FILE=%%S"
    echo Signals: !SIGNAL_FILE!
) else (
    echo Invalid option. Continuing without.
)
:after_signals

:tb_menu
echo.
echo === Select Testbench ===
set j=0
for %%F in ("%TB_DIR%\*.sv" "%TB_DIR%\*.v" "%TB_DIR%\*.tb") do (
    if exist "%%~fF" (
        set /a j+=1
        set "TB_!j!=%%~fF"
        echo !j!: %%~fF
    )
)
echo 0: Change design
echo X: Exit
if %j%==0 (
    echo No testbenches in %TB_DIR%
    exit /b 1
)
set /p sel_tb=Enter option:
if "%sel_tb%"=="0" (
    goto select_design
) else if /I "%sel_tb%"=="X" (
    exit /b 0
) else if defined TB_%sel_tb% (
    set "TB_FILE=!TB_%sel_tb%!"
    echo Testbench: %TB_FILE%
) else (
    echo Invalid option.
    goto tb_menu
)

:action_menu
echo.
echo === Action ===
echo 1: Run
echo 2: Run and open GTKWave
echo 3: Back (choose testbench)
set /p act=Enter option:
if "%act%"=="1" goto run_only
if "%act%"=="2" goto run_gtkw
if "%act%"=="3" goto action_menu_exit_tb
echo Invalid option.
goto action_menu

:run_only
call :build_and_run run
goto action_menu

:run_gtkw
call :build_and_run run_gtkw
goto action_menu

:build_and_run
set "ACTION=%1"
del /f /q "%RUN%\*.vcd" "%RUN%\simulation.vvp" 2>nul
echo.
echo === Compiling ===
iverilog -g2012 -I "%TB_DIR%" -o "%RUN%\simulation.vvp" "%DESIGN_FILE%" "%TB_FILE%"
if errorlevel 1 (
    echo Compile failed.
    goto :eof
)
echo === Running simulation ===
pushd "%RUN%" && vvp simulation.vvp & popd
if "%ACTION%"=="run_gtkw" (
    if defined GTKWAVE_BIN (
        for %%V in ("%RUN%\*.vcd") do (
            if defined SIGNAL_FILE (
                if exist "!SIGNAL_FILE!" (
                "%GTKWAVE_BIN%" "%%~fV" "!SIGNAL_FILE!"
                ) else (
                    echo Signal file not found, opening without: !SIGNAL_FILE!
                    "%GTKWAVE_BIN%" "%%~fV"
                )
            ) else (
                "%GTKWAVE_BIN%" "%%~fV"
            )
            goto :eof
        )
        echo No VCD found in %RUN% to open in GTKWave.
    ) else (
        echo GTKWave not found in PATH.
    )
)
goto :eof

rem resume action menu without re-selecting TB
:action_menu_exit_tb
goto tb_menu

endlocal
