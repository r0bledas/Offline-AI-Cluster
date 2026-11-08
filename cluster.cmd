@echo off
setlocal

:: Prefer local portable node in bin/ if present, otherwise system node
if exist "%~dp0bin\node.exe" (
    "%~dp0bin\node.exe" "%~dp0cluster.js" %*
) else (
    node "%~dp0cluster.js" %*
)
