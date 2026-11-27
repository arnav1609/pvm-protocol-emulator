[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Run')]
    [ValidatePattern('^COM[1-9][0-9]*$')]
    [string]$Port,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateSet('all', 'uart_tx', 'spi_mode0', 'i2c_write', 'dmx512_tx')]
    [string]$Demo = 'all',

    [Parameter(Mandatory, ParameterSetName = 'Check')]
    [string]$Check
)

$ErrorActionPreference = 'Stop'
$python = (Get-Command python.exe -CommandType Application | Select-Object -First 1).Source
$overlay = Split-Path -Parent $PSScriptRoot

if ($Check) {
    $capture = (Resolve-Path -LiteralPath $Check).Path
    $runs = Get-Content -LiteralPath (Join-Path $capture 'readback.jsonl') | ForEach-Object {
        $result = ConvertFrom-Json $_
        '{0}/{1}' -f $result.demo, $result.run
    }
    if (($runs -join ',') -ne 'uart_tx/1,spi_mode0/1,i2c_write/1,dmx512_tx/1,dmx512_tx/2') {
        throw 'The readback file must contain the five successful runs from one all-demos session.'
    }
    Write-Host 'PASS five demo readbacks recorded'
    $compare = Join-Path $overlay 'scripts/compare_capture.py'
    & $python -B $compare reset (Join-Path $capture 'reset.csv')
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    & $python -B $compare uart (Join-Path $capture 'uart.csv')
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    & $python -B $compare spi (Join-Path $capture 'spi.csv')
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    & $python -B $compare i2c (Join-Path $capture 'i2c.csv') --i2c-target board-fixture
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    & $python -B $compare dmx512 (Join-Path $capture 'dmx512_run1.csv') (Join-Path $capture 'dmx512_run2.csv')
    exit $LASTEXITCODE
}

if (!$Port) {
    & $python -B -m serial.tools.list_ports -v
    exit $LASTEXITCODE
}

$output = New-Item -ItemType Directory -Path (Join-Path $overlay ('board_results/{0}_{1}' -f $Demo, [guid]::NewGuid().ToString('N').Substring(0, 8)))
$readback = Join-Path $output.FullName 'readback.jsonl'
$runner = Join-Path $overlay 'host/run_demos.py'
Write-Host "Capture folder: $($output.FullName.Replace('\', '/'))"
& $python -B $runner --port $Port --demo $Demo --arm --output $readback
exit $LASTEXITCODE
