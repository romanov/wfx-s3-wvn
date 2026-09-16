:: build delphi project

@echo off

setlocal

:: run from this script's folder, so the relative paths below hold
pushd "%~dp0"

set version=0.9.1

:: locate the Delphi command line environment, newest first:
:: 37.0 = Delphi 13 Florence, 23.0 = 12 Athens, 22.0 = 11 Alexandria.
:: set DELPHI_BIN yourself beforehand to override this.
for %%v in (37.0 23.0 22.0) do (
	if not defined DELPHI_BIN (
		if exist "C:\Program Files (x86)\Embarcadero\Studio\%%v\bin\rsvars.bat" (
			set "DELPHI_BIN=C:\Program Files (x86)\Embarcadero\Studio\%%v\bin"
		)
	)
)

if not defined DELPHI_BIN (
	echo ERROR: no RAD Studio found under "C:\Program Files (x86)\Embarcadero\Studio".
	echo Set DELPHI_BIN to the folder holding rsvars.bat and run again.
	popd
	exit /b 1
)

set DELPHI_PROJECT=..\source\S3.dproj

call "%DELPHI_BIN%\rsvars.bat"

msbuild "%DELPHI_PROJECT%" /t:Build /p:Config=Release /p:Platform=Win32
if errorlevel 1 goto :failed
copy ..\bin\S3.wfx ..\release\WvN-S3.wfx

msbuild "%DELPHI_PROJECT%" /t:Build /p:Config=Release /p:Platform=Win64
if errorlevel 1 goto :failed
copy ..\bin\S3.wfx64 ..\release\WvN-S3.wfx64
copy ..\res\pluginst.inf ..\release\pluginst.inf
copy ..\README.md ..\release\README.md

powershell -NoProfile -Command "Compress-Archive -Force -Path '../release/WvN-S3.wfx','../release/WvN-S3.wfx64','../release/pluginst.inf','../release/README.md' -DestinationPath '../release/TotalCommander-WvN-S3-WFX-%version%.zip'"
if errorlevel 1 goto :failed

echo Built release\TotalCommander-WvN-S3-WFX-%version%.zip
popd
endlocal
exit /b 0

:failed
echo BUILD FAILED
popd
endlocal
exit /b 1
