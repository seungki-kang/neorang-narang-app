param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('Standard','Full')][string]$Mode = 'Standard',
    [string]$DeviceId = '',
    [int]$ShuffleSeed = 22022
)
$ErrorActionPreference = 'Stop'
# NN-DEVICE-SAFETY-BLOCK
if ($Mode -eq 'Full') {
    throw '기기 테스트 차단: 테스트 앱 ID와 전용 에뮬레이터 분리 전에는 Full 모드를 실행할 수 없습니다. PC 검사는 Standard 모드를 사용하세요.'
}
Get-Command flutter -ErrorAction Stop | Out-Null
Set-Location -LiteralPath $ProjectRoot
if (!(Test-Path -LiteralPath 'pubspec.yaml')) { throw 'Project root missing.' }
if ($Mode -eq 'Full' -and [string]::IsNullOrWhiteSpace($DeviceId)) {
    throw 'Full mode requires -DeviceId. Run flutter devices, then use the Android device ID.'
}
$reportRoot = Join-Path $ProjectRoot ('test-results\' + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
$steps = [System.Collections.Generic.List[object]]::new()
$startedAt = (Get-Date).ToUniversalTime().ToString('o')
Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'lib') -Filter '*.dart' -File -Recurse |
    ForEach-Object { [ordered]@{ path = $_.FullName; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $reportRoot 'source-hashes.json') -Encoding UTF8
function Save-Summary([string]$Result) {
    $summary = [ordered]@{
        startedAt = $startedAt; finishedAt = (Get-Date).ToUniversalTime().ToString('o')
        result = $Result; mode = $Mode; shuffleSeed = $ShuffleSeed
        deviceId = $DeviceId; steps = @($steps.ToArray())
        deviceSqlite = $(if ($steps | Where-Object { $_.name -eq 'device-sqlite' -and $_.exitCode -eq 0 }) { 'PASS' } else { 'NOT_RUN' })
        osForceKillRecovery = 'NOT_RUN'; releaseSigning = 'NOT_RUN'
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportRoot 'summary.json') -Encoding UTF8
}
function Invoke-NNStep([string]$Name, [string[]]$Arguments) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $log = Join-Path $reportRoot ($Name + '.txt')
    Write-Host ('--- ' + $Name + ' ---')
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & flutter @Arguments 2>&1 | Tee-Object -FilePath $log
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    $watch.Stop()
    $steps.Add([ordered]@{ name = $Name; command = @('flutter') + $Arguments; exitCode = $code; seconds = $watch.Elapsed.TotalSeconds; log = $log })
    if ($code -ne 0) { throw "Failed: $Name. See $log" }
}
try {
    Invoke-NNStep 'version' @('--version')
    Invoke-NNStep 'analyze' @('analyze')
    Invoke-NNStep 'tests-coverage' @('test','test','--coverage','--reporter','expanded')
    if (!(Test-Path -LiteralPath 'coverage\lcov.info')) { throw 'Coverage output missing.' }
    Copy-Item -LiteralPath 'coverage\lcov.info' -Destination (Join-Path $reportRoot 'lcov.info')
    $lf = 0L; $lh = 0L
    foreach ($line in Get-Content -LiteralPath 'coverage\lcov.info') {
        if ($line -match '^LF:(\d+)$') { $lf += [long]$Matches[1] }
        if ($line -match '^LH:(\d+)$') { $lh += [long]$Matches[1] }
    }
    [ordered]@{ linesFound = $lf; linesHit = $lh; linePercent = $(if ($lf -gt 0) { [Math]::Round(100.0 * $lh / $lf, 2) } else { $null }); note = 'Execution coverage is not proof of correctness.' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reportRoot 'coverage-summary.json') -Encoding UTF8
    # Deliberate second run detects shared state / execution-order dependence.
    Invoke-NNStep 'tests-shuffled' @('test','test','--reporter','expanded','--test-randomize-ordering-seed',"$ShuffleSeed")
    if ($Mode -eq 'Full') {
        Invoke-NNStep 'device-sqlite' @('test','integration_test/operations_sqlite_test.dart','-d',$DeviceId,'--reporter','expanded')
        Invoke-NNStep 'apk-debug' @('build','apk','--debug')
    }
    Save-Summary 'PASS_FOR_REQUESTED_SCOPE'
    Write-Host "결과 폴더: $reportRoot"
    if ($Mode -eq 'Standard') {
        Write-Host 'PC 검사 통과. 실제 기기 SQLite·OS 강제 종료·출시 서명 검증은 미실행입니다.'
    } else {
        Write-Host 'PC 검사·기기 SQLite·디버그 APK 통과. OS 강제 종료·출시 서명 검증은 미실행입니다.'
    }
} catch {
    Save-Summary 'FAIL'
    Write-Host "결과 폴더: $reportRoot"
    throw
}
