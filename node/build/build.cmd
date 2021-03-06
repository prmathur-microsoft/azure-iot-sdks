@REM Copyright (c) Microsoft. All rights reserved.
@REM Licensed under the MIT license. See LICENSE file in the project root for full license information.

@setlocal
@echo off

set node-root=%~dp0..
rem // resolve to fully qualified path
for %%i in ("%node-root%") do set node-root=%%~fi

rem ---------------------------------------------------------------------------
rem -- parse script arguments
rem ---------------------------------------------------------------------------

set min-output=0
set integration-tests=0
set e2e-tests=0

:args-loop
if "%1" equ "" goto args-done
if "%1" equ "--min" goto arg-min-output
if "%1" equ "--integration-tests" goto arg-integration-tests
if "%1" equ "--e2e-tests" goto arg-e2e-tests
call :usage && exit /b 1

:arg-min-output
set min-output=1
goto args-continue

:arg-integration-tests
set integration-tests=1
goto args-continue

:arg-e2e-tests
set e2e-tests=1
goto args-continue

:args-continue
shift
goto args-loop

:args-done

if %min-output%==0 if %integration-tests%==0 set "npm-command=npm -s test"
if %min-output%==0 if %integration-tests%==1 set "npm-command=npm -s run lint && npm -s run alltest"
if %min-output%==1 if %integration-tests%==0 set "npm-command=npm -s run lint && npm -s run unittest-min"
if %min-output%==1 if %integration-tests%==1 set "npm-command=npm -s run ci"

rem ---------------------------------------------------------------------------
rem -- create x509 test device
rem ---------------------------------------------------------------------------
if "%OPENSSL_CONF%"=="" (
  echo The OPENSSL_CONF environment variable must be defined in order to generate the x509 certificate for the test device.
  set ERRORLEVEL=1
  goto :eof
)

set IOTHUB_X509_DEVICE_ID=x509device-node-%RANDOM%
call node %node-root%\build\tools\create_device_certs.js --connectionString %IOTHUB_CONNECTION_STRING% --deviceId %IOTHUB_X509_DEVICE_ID%
set IOTHUB_X509_CERTIFICATE=%node-root%\%IOTHUB_X509_DEVICE_ID%-cert.pem
set IOTHUB_X509_KEY=%node-root%\%IOTHUB_X509_DEVICE_ID%-key.pem

rem ---------------------------------------------------------------------------
rem -- lint and run tests
rem ---------------------------------------------------------------------------

echo.
if %integration-tests%==0 echo -- Linting and running unit tests --
if %integration-tests%==1 echo -- Linting and running unit + integration tests --
echo.

call :lint-and-test %node-root%\common\core
if errorlevel 1 goto :cleanup

call :lint-and-test %node-root%\common\transport\amqp
if errorlevel 1 goto :cleanup

call :lint-and-test %node-root%\common\transport\http
if errorlevel 1 goto :cleanup

call :lint-and-test %node-root%\device\core
if errorlevel 1 goto :cleanup

call :lint-and-test %node-root%\device\transport\amqp
if errorlevel 1 goto :cleanup

call :lint-and-test %node-root%\device\transport\http
if errorlevel 1 goto :cleanup

call :lint-and-test %node-root%\device\transport\mqtt
if errorlevel 1 goto :cleanup

call :lint-and-test %node-root%\service
if errorlevel 1 goto :cleanup

if %e2e-tests%==1 (
  call :lint-and-test %node-root%\e2etests
  if errorlevel 1 goto :cleanup
)

cd %node-root%\..\tools\iothub-explorer
call npm -s test
if errorlevel 1 goto :cleanup

goto :cleanup


rem ---------------------------------------------------------------------------
rem -- helper subroutines
rem ---------------------------------------------------------------------------

:usage
echo Lint code and run tests.
echo build.cmd [options]
echo options:
echo  --min                 minimize display output
echo  --integration-tests   run integration tests too (unit tests always run)
echo  --e2e-tests           run end-to-end tests too (unit tests always run)
goto :eof

:lint-and-test
cd "%1"
echo %cd%
call %npm-command%
goto :eof

:cleanup
set EXITCODE=%ERRORLEVEL%
call node %node-root%\..\tools\iothub-explorer\iothub-explorer.js delete %IOTHUB_X509_DEVICE_ID% --login %IOTHUB_CONNECTION_STRING% 
del %IOTHUB_X509_CERTIFICATE%
del %IOTHUB_X509_KEY%
exit /b %EXITCODE%