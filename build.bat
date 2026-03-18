@echo off
:: somsee 루트 빌드 스크립트 — 모든 예제를 빌드
cd /d "%~dp0"

echo === Building: particle_demo ===
call examples\particle_demo\build.bat || goto :error

echo.
echo All builds OK.
goto :end

:error
echo BUILD FAILED
exit /b 1

:end
