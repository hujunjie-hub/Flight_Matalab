[CmdletBinding()]
param([string]$GccDir = 'D:\STM32CubeCLT\mingw64\bin')

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$flight = (Resolve-Path (Join-Path $project '../Flight')).Path
$objectsDir = Join-Path $project 'work/upstream_sil'
$mexDir = Join-Path $project 'work/mex'
New-Item -ItemType Directory -Force $objectsDir,$mexDir | Out-Null

# Flight's upstream runner owns the list of firmware translation units.
# Start a fresh, isolated object directory so source removals cannot leave objects in the link.
$buildDir = Join-Path $objectsDir ([Guid]::NewGuid().ToString('N'))
& (Join-Path $flight 'tests/simulation/run_sil.ps1') -GccDir $GccDir -OutDir $buildDir
$includes = @(
    'tests/simulation', 'tests/runtime/stubs', 'applications/tasks', 'applications/runtime',
    'middleware/contracts', 'middleware/communication', 'middleware/protocol', 'middleware/param',
    'middleware/sensor', 'middleware/model/ins', 'middleware/model/fms', 'middleware/model/fms/quad_x4',
    'middleware/guidance', 'middleware/model/control', 'middleware/model/control/inner_loop/quad_x4',
    'middleware/actuator', 'sensor_device', 'sensor_device/time_base', 'sensor_device/actuator',
    'sensor_device/imu', 'sensor_device/gnss', 'sensor_device/mag', 'sensor_device/barometer',
    'sensor_device/pmu', 'libraries/HAL_Drivers/drivers', 'board'
) | ForEach-Object { '-I' + (Join-Path $flight $_) }
$adapter = Join-Path $project 'adapters/flight_runtime/fmt_flight_runtime.c'
$adapterObject = Join-Path $buildDir 'fmt_flight_runtime.o'
& (Join-Path $GccDir 'gcc.exe') -std=c99 -O2 -Wall -Wextra -Werror -Wno-unused-function -fno-short-enums `
    -DFLIGHT_HOST_TEST -DFLIGHT_HOST_SIL @includes -c $adapter -o $adapterObject
if ($LASTEXITCODE) { throw 'Flight Simulink adapter compilation failed' }

$sensorSimulation = Join-Path $project 'adapters/flight_runtime/fmt_sensor_simulation.c'
$sensorSimulationObject = Join-Path $buildDir 'fmt_sensor_simulation.o'
& (Join-Path $GccDir 'gcc.exe') -std=c99 -O2 -Wall -Wextra -Werror -fno-short-enums `
    -DFLIGHT_HOST_TEST -DFLIGHT_HOST_SIL @includes -c $sensorSimulation -o $sensorSimulationObject
if ($LASTEXITCODE) { throw 'Deterministic sensor simulation compilation failed' }
$timeService = Join-Path $buildDir 'systime_host.o'
& (Join-Path $GccDir 'gcc.exe') -std=c99 -O2 -Wall -Wextra -Werror -fno-short-enums -DFLIGHT_HOST_TEST -DFLIGHT_HOST_SIL -DFLIGHT_HOST_REAL_TIME_SERVICE @includes -c (Join-Path $flight 'sensor_device/time_base/systime.c') -o $timeService
if ($LASTEXITCODE) { throw 'Flight time service compilation failed' }
$objects = Get-ChildItem -LiteralPath $buildDir -Filter '*.o' -File |
    Where-Object Name -ne 'tests_simulation_sil_flight.c.o' | Select-Object -ExpandProperty FullName
$wrappers = @('estimator_init', 'estimator_push_imu', 'estimator_update', 'estimator_get_snapshot',
    'estimator_get_capability', 'ins_get_pending_origin', 'estimator_push_measurement', 'fms_authorize_origin_reset', 'estimator_reset') | ForEach-Object { '-Wl,--wrap=' + $_ }
$dll = Join-Path $mexDir 'fmt_flight_runtime.dll'
& (Join-Path $GccDir 'g++.exe') -shared -static -static-libgcc -static-libstdc++ @objects @wrappers -lm -lws2_32 -o $dll
if ($LASTEXITCODE) { throw 'Flight Simulink runtime linking failed' }
& python -B (Join-Path $PSScriptRoot 'record_flight_baseline.py') $project $flight $buildDir $dll
if ($LASTEXITCODE) { throw 'Flight baseline recording failed' }
