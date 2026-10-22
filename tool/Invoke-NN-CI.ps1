#requires -Version 5.1
param(
    [ValidateSet('Tests','Apk')][string]$Mode = 'Tests',
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot 'pubspec.lock'))) { throw 'pubspec.lock is required.' }
Get-Command flutter -ErrorAction Stop | Out-Null
$report = Join-Path $ProjectRoot ('test-results/ci-' + $Mode.ToLowerInvariant())
New-Item -ItemType Directory -Path $report -Force | Out-Null
$steps = New-Object 'System.Collections.Generic.List[object]'
function Invoke-Check([string]$Name, [string[]]$FlutterArgs) {
    $log = Join-Path $report ($Name + '.log')
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & flutter @FlutterArgs 2>&1 | Tee-Object -FilePath $log
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    $steps.Add([ordered]@{ name = $Name; exitCode = $code })
    if ($code -ne 0) { throw "Check failed: $Name (exit $code). See $log" }
}
Push-Location -LiteralPath $ProjectRoot
$result = 'FAIL'
try {
    Invoke-Check 'version' @('--version')
    Invoke-Check 'dependencies' @('pub','get','--enforce-lockfile')
    if ($Mode -eq 'Tests') {
        Invoke-Check 'analyze' @('analyze','--no-pub')
        # Never reuse old coverage after a failed or empty run.
        $lcov = Join-Path $ProjectRoot 'coverage/lcov.info'
        if (Test-Path -LiteralPath $lcov) { Remove-Item -LiteralPath $lcov }
        Invoke-Check 'tests' @('test','test','--no-pub','--coverage','--reporter','expanded','--timeout','60s')
        if (!(Test-Path -LiteralPath $lcov)) { throw 'Coverage report missing.' }
        Copy-Item -LiteralPath $lcov -Destination (Join-Path $report 'lcov.info') -Force
        $found = 0L; $hit = 0L
        foreach ($line in Get-Content -LiteralPath $lcov) {
            if ($line -match '^LF:(\d+)$') { $found += [long]$Matches[1] }
            if ($line -match '^LH:(\d+)$') { $hit += [long]$Matches[1] }
        }
        if ($found -le 0 -or $hit -gt $found) { throw 'Invalid coverage totals.' }
        $percent = [Math]::Round(100.0 * $hit / $found, 2)
        [ordered]@{ linesHit=$hit; linesFound=$found; linePercent=$percent; note='Execution coverage is not proof of correctness.' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $report 'coverage-summary.json') -Encoding UTF8
        if ($env:GITHUB_STEP_SUMMARY) {
            "Line coverage: $percent% ($hit / $found). Device tests: NOT_RUN." |
                Out-File -LiteralPath $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8
        }
        Invoke-Check 'tests-shuffled' @('test','test','--no-pub','--reporter','expanded','--timeout','60s','--test-randomize-ordering-seed','22022')
    } else {
        Invoke-Check 'apk-debug' @('build','apk','--debug','--no-pub')
    }
    $result = 'PASS_FOR_REQUESTED_SCOPE'
} finally {
    [ordered]@{
        result=$result; mode=$Mode; steps=@($steps.ToArray())
        deviceSqlite='NOT_RUN'; osForceStop='NOT_RUN'; releaseSigning='NOT_RUN'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $report 'summary.json') -Encoding UTF8
    Pop-Location
    Write-Host "Result: $result / $report"
}
