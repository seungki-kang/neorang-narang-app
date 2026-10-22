#requires -Version 5.1
param(
    [ValidateSet('Quick','Standard','Device')][string]$Mode = 'Quick',
    [string]$ProjectRoot = 'D:\CHGO-VibeCodeing\neorang_narang_app',
    [int]$ShuffleSeed = 22022,
    [ValidateRange(120,3600)][int]$StepTimeoutSeconds = 600
)
$ErrorActionPreference = 'Stop'
$baseId = 'com.example.neorang_narang_app'
$testId = $baseId + '.devicetest'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if ((Split-Path $root -Leaf) -ne 'neorang_narang_app') { throw '일반 프로젝트 폴더에서만 실행할 수 있습니다.' }
foreach ($item in @('pubspec.yaml','lib','test')) {
    if (!(Test-Path -LiteralPath (Join-Path $root $item))) { throw "필수 경로 없음: $item" }
}
$flutter = (Get-Command flutter -ErrorAction Stop).Source
if (!$flutter) { throw 'Flutter 실행 파일을 찾지 못했습니다.' }
$lockKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())).Replace('/','_')
$mutex = New-Object System.Threading.Mutex($false, ('Local\NN-Test-' + $lockKey))
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (!$owned) { $mutex.Dispose(); throw '이 프로젝트의 검사가 이미 실행 중입니다.' }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmssfff'
$report = Join-Path $root ('test-results\optimized-' + $stamp)
$steps = New-Object 'System.Collections.Generic.List[object]'
$started = (Get-Date).ToUniversalTime().ToString('o')
$device = $null; $stage = $null; $before = $null
$excluded = @('.git','.dart_tool','.gradle','build','test-results','coverage','.idea')
$inputs = @('lib','test','integration_test','assets','android','pubspec.yaml','pubspec.lock','analysis_options.yaml')
function Input-Files([string]$Directory) {
    foreach ($f in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($f.Name -in $excluded) { continue }
        if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "링크 경로는 자동 복사하지 않습니다: $($f.FullName)" }
        if ($f.PSIsContainer) { Input-Files $f.FullName } else { $f }
    }
}
function Source-Snapshot {
    foreach ($item in $inputs) {
        $path = Join-Path $root $item
        if (!(Test-Path -LiteralPath $path)) { continue }
        $files = if (Test-Path -LiteralPath $path -PathType Container) { @(Input-Files $path) } else { @(Get-Item -LiteralPath $path) }
        foreach ($f in $files) {
            [pscustomobject]@{ path = $f.FullName.Substring($root.Length + 1); sha256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
        }
    }
}
function Assert-Unchanged($Expected) {
    $current = @(Source-Snapshot | Sort-Object path)
    $difference = @(Compare-Object $Expected $current -Property path,sha256)
    if ($difference.Count -gt 0) { throw '검사 중 원본 코드가 변경되었습니다. 이 결과는 최신 코드의 통과로 처리하지 않습니다.' }
}
function Assert-Device {
    $avd = @(& $script:adb -s $script:device emu avd name)
    if ($LASTEXITCODE -ne 0 -or $avd -notcontains 'NN_Test_Only') { throw '테스트 전용 기기가 아닙니다.' }
    $boot = & $script:adb -s $script:device shell getprop sys.boot_completed
    if ($LASTEXITCODE -ne 0 -or "$boot".Trim() -ne '1') { throw '테스트 기기 부팅이 완료되지 않았습니다.' }
    $packages = @(& $script:adb -s $script:device shell pm list packages)
    if ($LASTEXITCODE -ne 0) { throw '테스트 기기 앱 목록 확인 실패' }
    if ($packages -contains ('package:' + $baseId)) { throw '테스트 기기에 일반 앱이 있습니다. 자동 검사를 중단합니다.' }
}
function Invoke-Step([string]$Name,[string[]]$Arguments,[string]$WorkingDirectory) {
    $config = Join-Path $report ($Name + '.json')
    $log = Join-Path $report ($Name + '.log')
    @{ executable=$flutter; arguments=$Arguments; directory=$WorkingDirectory; log=$log } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $config -Encoding UTF8
    $worker = Join-Path $report 'worker.ps1'
    $workerOut = Join-Path $report ($Name + '.worker.log')
    $workerErr = Join-Path $report ($Name + '.worker-error.log')
    $ps = Join-Path $PSHOME 'powershell.exe'
    if (!(Test-Path -LiteralPath $ps)) { $ps = Join-Path $PSHOME 'pwsh.exe' }
    if (!(Test-Path -LiteralPath $ps)) { throw 'Windows PowerShell 실행 파일을 찾지 못했습니다.' }
    Write-Host "[$Name] 시작 (최대 $StepTimeoutSeconds 초)"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $ps -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Config "{1}"' -f $worker,$config) -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $workerOut -RedirectStandardError $workerErr -PassThru
    $null = $process.Handle
    $timedOut = $false
    try {
        $nextNotice = 15
        while (!$process.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalSeconds -ge $StepTimeoutSeconds) {
                $timedOut = $true
                & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
                break
            }
            if ($watch.Elapsed.TotalSeconds -ge $nextNotice) {
                Write-Host "[$Name] 실행 중: $([int]$watch.Elapsed.TotalSeconds)초 / 로그: $log"
                $nextNotice += 15
            }
        }
        if (!$timedOut) { $process.WaitForExit(); $code = $process.ExitCode } else { $code = 124 }
    } finally {
        if (!$process.HasExited) { & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null }
        $process.Dispose()
    }
    $watch.Stop()
    $steps.Add([pscustomobject]@{ name=$Name; arguments=$Arguments; exitCode=$code; seconds=[Math]::Round($watch.Elapsed.TotalSeconds,2); log=$log })
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 16 | ForEach-Object { Write-Host $_ } }
    if ($code -ne 0) {
        if (Test-Path -LiteralPath $workerErr) { Get-Content -LiteralPath $workerErr -Tail 10 | ForEach-Object { Write-Host $_ } }
        throw "검사 실패 또는 제한 시간 초과: $Name / 로그: $log"
    }
}
$result = 'FAIL'
try {
    New-Item -ItemType Directory -Path $report -Force | Out-Null
    @'
param([string]$Config)
$ErrorActionPreference = 'Stop'
try {
    $step = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
    Set-Location -LiteralPath $step.directory
    $nnArgs = @($step.arguments)
    $ErrorActionPreference = 'Continue'
    & $step.executable @nnArgs 2>&1 | Tee-Object -FilePath $step.log | Out-Null
    $nnExit = $LASTEXITCODE
    if ($null -eq $nnExit) { exit 1 }
    exit $nnExit
} catch { Write-Error $_; exit 1 }
'@ | Set-Content -LiteralPath (Join-Path $report 'worker.ps1') -Encoding UTF8
    $before = @(Source-Snapshot | Sort-Object path)
    ConvertTo-Json -InputObject $before -Depth 4 | Set-Content -LiteralPath (Join-Path $report 'source-hashes.json') -Encoding UTF8
    Invoke-Step 'version' @('--version') $root
    if ($Mode -ne 'Device') {
        Invoke-Step 'analyze' @('analyze','--no-pub') $root
        $argsForTest = @('test','test','--no-pub','--reporter','expanded','--timeout','60s')
        if ($Mode -eq 'Standard') { $argsForTest += '--coverage' }
        Invoke-Step 'host-tests' $argsForTest $root
        if ($Mode -eq 'Standard') {
            $coverage = Join-Path $root 'coverage\lcov.info'
            if (!(Test-Path -LiteralPath $coverage)) { throw '커버리지 파일이 없습니다.' }
            Copy-Item -LiteralPath $coverage -Destination (Join-Path $report 'lcov.info')
            $lf=0L; $lh=0L
            foreach ($line in Get-Content -LiteralPath $coverage) {
                if ($line -match '^LF:(\d+)$') { $lf += [long]$Matches[1] }
                if ($line -match '^LH:(\d+)$') { $lh += [long]$Matches[1] }
            }
            @{linesFound=$lf;linesHit=$lh;linePercent=$(if($lf -gt 0){[Math]::Round(100.0*$lh/$lf,2)}else{$null});note='실행 범위이며 정확성 보장은 아님'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $report 'coverage-summary.json') -Encoding UTF8
            Invoke-Step 'shuffled-tests' @('test','test','--no-pub','--reporter','expanded','--timeout','60s','--test-randomize-ordering-seed',"$ShuffleSeed") $root
        }
    } else {
        $script:adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        $devices = @(& $adb devices)
        if ($LASTEXITCODE -ne 0) { throw 'ADB 기기 조회 실패' }
        $matchesForTest = @()
        foreach ($line in $devices) {
            if ($line -match '^(emulator-\d+)\s+device\s*$') {
                $serial = $Matches[1]
                $name = @(& $adb -s $serial emu avd name)
                if ($LASTEXITCODE -eq 0 -and $name -contains 'NN_Test_Only') { $matchesForTest += $serial }
            }
        }
        if ($matchesForTest.Count -ne 1) { throw 'NN_Test_Only를 하나만 실행한 뒤 다시 검사하세요.' }
        $script:device = $matchesForTest[0]
        Assert-Device
        foreach ($required in @('android\app\build.gradle.kts','android\app\src\main\AndroidManifest.xml','integration_test\operations_sqlite_test.dart')) {
            if (!(Test-Path -LiteralPath (Join-Path $root $required))) { throw "필수 경로 없음: $required" }
        }
        $gradleOriginal = [IO.File]::ReadAllText((Join-Path $root 'android\app\build.gradle.kts'))
        foreach ($setting in @('namespace','applicationId')) {
            $pattern = '(?m)^\s*' + $setting + '\s*=\s*"' + [regex]::Escape($baseId) + '"\s*$'
            if ([regex]::Matches($gradleOriginal,$pattern).Count -ne 1) { throw "Android $setting 설정이 예상과 다릅니다. 자동 변경하지 않습니다." }
        }
        # Every run uses a new staging directory; old source files cannot remain.
        $stage = Join-Path $env:LOCALAPPDATA ('NN-Test-Workspaces\' + $stamp + '-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        foreach ($entry in $before) {
            $destination = Join-Path $stage $entry.path
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $root $entry.path) -Destination $destination
            if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $entry.sha256) { throw '복사 중 소스가 변경됐습니다.' }
        }
        Assert-Unchanged $before
        $gradle = $gradleOriginal
        foreach ($setting in @('namespace','applicationId')) {
            $pattern = '(?m)^(\s*' + $setting + '\s*=\s*")' + [regex]::Escape($baseId) + '("\s*)$'
            $gradle = [regex]::Replace($gradle,$pattern,('${1}'+$testId+'${2}'))
        }
        $encoding = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Join-Path $stage 'android\app\build.gradle.kts'),$gradle,$encoding)
        foreach ($manifest in Get-ChildItem -LiteralPath (Join-Path $stage 'android\app\src') -Filter AndroidManifest.xml -File -Recurse) {
            $text = [IO.File]::ReadAllText($manifest.FullName).Replace('android:name=".MainActivity"',('android:name="'+$baseId+'.MainActivity"'))
            [IO.File]::WriteAllText($manifest.FullName,$text,$encoding)
        }
        Invoke-Step 'stage-pub-get' @('pub','get','--enforce-lockfile') $stage
        Invoke-Step 'test-help' @('test','--help','--verbose') $stage
        if (!(Select-String -LiteralPath (Join-Path $report 'test-help.log') -SimpleMatch 'uninstall' -Quiet)) { throw '자동 삭제 방지 옵션을 확인하지 못했습니다.' }
        Invoke-Step 'build-test-apk' @('build','apk','--debug','--no-pub','--target','integration_test/operations_sqlite_test.dart') $stage
        $apk = Join-Path $stage 'build\app\outputs\flutter-apk\app-debug.apk'
        $aapt = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools') -Filter aapt.exe -File -Recurse | Sort-Object FullName -Descending | Select-Object -First 1
        if ($null -eq $aapt) { throw 'APK 앱 ID 확인 도구(aapt)가 없습니다.' }
        $badging = @(& $aapt.FullName dump badging $apk)
        if ($LASTEXITCODE -ne 0 -or !($badging -match ("^package: name='" + [regex]::Escape($testId) + "'"))) { throw '빌드된 APK의 앱 ID가 테스트 전용 ID가 아닙니다.' }
        @{applicationId=$testId;sha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $report 'apk-identity.json') -Encoding UTF8
        Assert-Unchanged $before
        Assert-Device
        Invoke-Step 'device-sqlite' @('test','integration_test/operations_sqlite_test.dart','--no-pub','-d',$device,'--no-uninstall','--reporter','expanded','--timeout','60s') $stage
    }
    Assert-Unchanged $before
    $result = 'PASS_FOR_REQUESTED_SCOPE'
} finally {
    try {
        if (Test-Path -LiteralPath $report) {
            $summary = [ordered]@{result=$result;mode=$Mode;startedAt=$started;finishedAt=(Get-Date).ToUniversalTime().ToString('o');sourceRoot=$root;stage=$stage;deviceId=$device;steps=$steps.ToArray();deviceSqlite=$(if($steps | Where-Object {$_.name -eq 'device-sqlite' -and $_.exitCode -eq 0}){'PASS'}else{'NOT_RUN'});osForceKillRecovery='NOT_RUN';releaseSigning='NOT_RUN';note='이 실행 범위만 판정. 커버리지는 정확성 보장이 아님.'}
            $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $report 'summary.json') -Encoding UTF8
            Write-Host "결과: $result / 보고서: $report"
            if ($stage) { Write-Host "진단용 테스트 사본(보관): $stage" }
        }
    } finally { if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
