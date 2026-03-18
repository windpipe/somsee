@echo off
cd /d "%~dp0"
set GLSLC=C:\VulkanSDK\1.3.216.0\Bin\glslc.exe
set SHADER_DIR=shaders
set COLLECTION=somsee=..\..

echo === Compiling shaders ===
%GLSLC% -fshader-stage=comp %SHADER_DIR%\particle.comp.glsl -o %SHADER_DIR%\particle.comp.spv || goto :error
%GLSLC% -fshader-stage=vert %SHADER_DIR%\particle.vert.glsl -o %SHADER_DIR%\particle.vert.spv || goto :error
%GLSLC% -fshader-stage=frag %SHADER_DIR%\particle.frag.glsl -o %SHADER_DIR%\particle.frag.spv || goto :error
echo Shaders OK

echo === Building Odin ===
odin build . -collection:%COLLECTION% -out:particle_basic_single_vsync.exe -o:speed || goto :error
echo Done: particle_basic_single_vsync.exe
goto :end

:error
echo BUILD FAILED
exit /b 1

:end
