@echo off

set    zip=bwidow.zip
set ifiles=136017-101.d1+136017-102.ef1+136017-103.h1+136017-104.j1+136017-105.kl1+136017-106.m1+136017-107.l7+136017-107.l7+136017-108.mn7+136017-109.np7+136017-110.r7+136002-125.n4
set  ofile=a.bwidow.rom

rem =====================================
setlocal ENABLEDELAYEDEXPANSION

set pwd=%~dp0
echo.
echo.

if EXIST %zip% (

	!pwd!7za x -otmp %zip%
	if !ERRORLEVEL! EQU 0 ( 
		cd tmp

		copy /b/y %ifiles% !pwd!%ofile%
		if !ERRORLEVEL! EQU 0 ( 
			echo.
			echo ** done **
			echo.
			echo Copy "%ofile%" into root of SD card
		)
		cd !pwd!
		rmdir /s /q tmp
	)

) else (

	echo Error: Cannot find "%zip%" file
	echo.
	echo Put "%zip%", "7za.exe" and "%~nx0" into the same directory
)

echo.
echo.
pause
