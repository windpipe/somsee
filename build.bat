@echo off
:: somsee 루트 빌드 스크립트 — 모든 예제를 빌드
cd /d "%~dp0"

echo === Building: particle_basic_dual ===
call examples\particle_basic_dual\build.bat || goto :error

echo.
echo === Building: particle_basic_single ===
call examples\particle_basic_single\build.bat || goto :error

echo.
echo === Building: particle_basic_single_vsync ===
call examples\particle_basic_single_vsync\build.bat || goto :error

echo.
echo All builds OK.
goto :end

:error
echo BUILD FAILED
exit /b 1

:end
