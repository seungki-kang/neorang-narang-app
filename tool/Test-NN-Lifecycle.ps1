#requires -Version 5.1
param(
    [string]$ProjectRoot = 'D:\CHGO-VibeCodeing\neorang_narang_app',
    [ValidateRange(120,3600)][int]$StepTimeoutSeconds = 600
)
$Mode = 'Lifecycle'
$ErrorActionPreference = 'Stop'
$baseId = 'com.example.neorang_narang_app'
$testId = $baseId + '.lifecycle.r' + [guid]::NewGuid().ToString('N')
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
$report = Join-Path $root ('test-results\lifecycle-' + $stamp)
$steps = New-Object 'System.Collections.Generic.List[object]'
$started = (Get-Date).ToUniversalTime().ToString('o')
$device = $null; $stage = $null; $before = $null
$excluded = @('.git','.dart_tool','.gradle','build','test-results','coverage','.idea')
$inputs = @('lib','test','integration_test','assets','android','pubspec.yaml','pubspec.lock','analysis_options.yaml','tool\nn_lifecycle_probe.dart')
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
function Invoke-Step([string]$Name,[string[]]$Arguments,[string]$WorkingDirectory,[string]$Executable=$flutter,[bool]$AllowFailure=$false) {
    $config = Join-Path $report ($Name + '.json')
    $log = Join-Path $report ($Name + '.log')
    @{ executable=$Executable; arguments=$Arguments; directory=$WorkingDirectory; log=$log } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $config -Encoding UTF8
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
    if ($code -ne 0 -and !$AllowFailure) {
        if (Test-Path -LiteralPath $workerErr) { Get-Content -LiteralPath $workerErr -Tail 10 | ForEach-Object { Write-Host $_ } }
        throw "검사 실패 또는 제한 시간 초과: $Name / 로그: $log"
    }
}
$result = 'FAIL'
$reflectionStatus='NOT_RUN'; $signatureStatus='NOT_RUN'; $updateStatus='NOT_RUN'; $finalStatus='NOT_RUN'
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
    foreach ($required in @('android\app\build.gradle.kts','android\app\src\main\AndroidManifest.xml','tool\nn_lifecycle_probe.dart')) {
        if (!(Test-Path -LiteralPath (Join-Path $root $required))) { throw "필수 경로 없음: $required" }
    }
    $script:adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    $devices = @(& $adb devices)
    if ($LASTEXITCODE -ne 0) { throw 'ADB 기기 조회 실패' }
    $candidates = @()
    foreach ($line in $devices) {
        if ($line -match '^(emulator-\d+)\s+device\s*$') {
            $serial = $Matches[1]
            $name = @(& $adb -s $serial emu avd name)
            if ($LASTEXITCODE -eq 0 -and $name -contains 'NN_Test_Only') { $candidates += $serial }
        }
    }
    if ($candidates.Count -ne 1) { throw 'NN_Test_Only를 하나만 실행하세요.' }
    $script:device = $candidates[0]
    Assert-Device
    $gradleOriginal = [IO.File]::ReadAllText((Join-Path $root 'android\app\build.gradle.kts'))
    foreach ($setting in @('namespace','applicationId')) {
        $pattern = '(?m)^\s*' + $setting + '\s*=\s*"' + [regex]::Escape($baseId) + '"\s*$'
        if ([regex]::Matches($gradleOriginal,$pattern).Count -ne 1) { throw "Android $setting 설정이 다릅니다. 변경하지 않습니다." }
    }
    $stage = Join-Path $env:LOCALAPPDATA ('NN-Test-Workspaces\lifecycle-' + $stamp + '-' + [guid]::NewGuid().ToString('N'))
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
    [IO.File]::WriteAllText((Join-Path $stage 'android\app\build.gradle.kts'),$gradle,(New-Object Text.UTF8Encoding($false)))
    foreach ($manifest in Get-ChildItem -LiteralPath (Join-Path $stage 'android\app\src') -Filter AndroidManifest.xml -File -Recurse) {
        $text = [IO.File]::ReadAllText($manifest.FullName).Replace('android:name=".MainActivity"',('android:name="'+$baseId+'.MainActivity"'))
        [IO.File]::WriteAllText($manifest.FullName,$text,(New-Object Text.UTF8Encoding($false)))
    }
    Invoke-Step 'version' @('--version') $stage
    Invoke-Step 'pub-get' @('pub','get','--enforce-lockfile') $stage
    # Validate production APIs and the probe before installing any APK.
    Invoke-Step 'probe-analyze' @('analyze','--no-pub','lib','tool/nn_lifecycle_probe.dart') $stage
    $aapt = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools') -Filter aapt.exe -File -Recurse | Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $aapt) { throw 'aapt 확인 도구가 없습니다.' }
    function Build-Probe([string]$Build,[string]$Number) {
        Invoke-Step ('build-' + $Build) @('build','apk','--debug','--no-pub','--target','tool/nn_lifecycle_probe.dart','--build-name',$(if($Build -eq 'A'){'0.0.1'}else{'0.0.2'}),'--build-number',$Number,('--dart-define=NN_PROBE_BUILD='+$Build)) $stage
        $sourceApk = Join-Path $stage 'build\app\outputs\flutter-apk\app-debug.apk'
        $savedApk = Join-Path $report ('probe-' + $Build + '.apk')
        Copy-Item -LiteralPath $sourceApk -Destination $savedApk
        Invoke-Step ('apk-identity-'+$Build) @('dump','badging',$savedApk) $stage $aapt.FullName
        $metadata = @(Get-Content -LiteralPath (Join-Path $report ('apk-identity-'+$Build+'.log')))
        if (!($metadata -match ("^package: name='"+[regex]::Escape($testId)+"' .*versionCode='"+$Number+"'"))) { throw 'APK 앱 ID 또는 버전 번호 불일치' }
        @{build=$Build;versionCode=$Number;applicationId=$testId;sha256=(Get-FileHash -LiteralPath $savedApk -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $report ('apk-'+$Build+'.json')) -Encoding UTF8
        return $savedApk
    }
    function Adb-Step([string]$Name,[string[]]$Arguments,[bool]$AllowFailure=$false) {
        Assert-Device
        Invoke-Step $Name (@('-s',$device)+$Arguments) $stage $adb $AllowFailure
    }
    function Read-Proof([string]$Label,[string]$Phase,[string]$Build,[string]$Previous) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        for ($attempt=0; $attempt -lt 30 -and $watch.Elapsed.TotalSeconds -lt 90; $attempt++) {
            Adb-Step ('proof-'+$Label+'-'+$attempt) @('shell','run-as',$testId,'cat','files/nn-lifecycle-proof.json') $true
            $last = $steps[$steps.Count-1]
            if ($last.exitCode -eq 0) {
                $raw = Get-Content -LiteralPath $last.log -Raw
                try { $proof = $raw | ConvertFrom-Json } catch { throw '검증 결과 JSON 손상' }
                if ($proof.launchId -and $proof.launchId -ne $Previous) {
                    $proof | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $report ($Label+'-proof.json')) -Encoding UTF8
                    if ($proof.status -ne 'PASS' -or $proof.build -ne $Build -or $proof.phase -ne $Phase) { throw "앱 내부 검증 실패: $Label / 결과 파일을 보내주세요." }
                    if (!$proof.pid -or [int]$proof.pid -le 0) { throw '앱 프로세스 증거 없음' }
                    return $proof
                }
            }
            Start-Sleep -Milliseconds 1000
        }
        throw "새 프로세스의 검증 결과 대기 시간 초과: $Label"
    }
    function Launch-Probe([string]$Label,[string]$Phase,[string]$Build,[string]$Previous) {
        Adb-Step ('launch-'+$Label) @('shell','am','start','-W','-n',($testId+'/'+$baseId+'.MainActivity'))
        return Read-Proof $Label $Phase $Build $Previous
    }
    function Stop-Probe([string]$Label) {
        Adb-Step ('force-stop-'+$Label) @('shell','am','force-stop',$testId)
        Adb-Step ('pid-after-stop-'+$Label) @('shell','pidof',$testId) $true
        $last = $steps[$steps.Count-1]
        $remaining = if (Test-Path -LiteralPath $last.log) { (Get-Content -LiteralPath $last.log -Raw) } else { '' }
        if ($last.exitCode -notin @(0,1) -or ![string]::IsNullOrWhiteSpace($remaining)) { throw '강제 종료 후 프로세스가 남아 있거나 조회 실패' }
    }
    function Package-Identity([string]$Label) {
        Adb-Step ('package-'+$Label) @('shell','dumpsys','package',$testId)
        $text = Get-Content -LiteralPath (Join-Path $report ('package-'+$Label+'.log')) -Raw
        $install = [regex]::Match($text,'firstInstallTime=([^\r\n]+)')
        $uid = [regex]::Match($text,'(?:userId|appId)=(\d+)')
        if (!$install.Success -or !$uid.Success) { throw '설치 연속성 증거를 읽지 못했습니다.' }
        return ($install.Groups[1].Value.Trim()+'|'+$uid.Groups[1].Value)
    }
    $apkA = Build-Probe 'A' '100001'
    Assert-Unchanged $before
    Adb-Step 'install-A' @('install','-r',$apkA)
    $p1 = Launch-Probe 'seed' 'seeded_reflection' 'A' ''
    $identityA = Package-Identity 'A'
    Stop-Probe 'reflection'
    $p2 = Launch-Probe 'reflection' 'reflection_restored_signature_prepared' 'A' $p1.launchId
    $reflectionStatus='PASS'
    Stop-Probe 'signature'
    $p3 = Launch-Probe 'signature' 'signature_restored' 'A' $p2.launchId
    $signatureStatus='PASS'
    Stop-Probe 'before-update'
    $apkB = Build-Probe 'B' '100002'
    Assert-Unchanged $before
    Adb-Step 'install-B-in-place' @('install','-r',$apkB)
    $identityB = Package-Identity 'B'
    if ($identityA -ne $identityB) { throw '앱 최초 설치 시각 또는 UID가 변경됐습니다. 업데이트 보존 통과로 처리하지 않습니다.' }
    $p4 = Launch-Probe 'updated' 'update_preserved_and_recovery_completed' 'B' $p3.launchId
    $updateStatus='PASS'
    Stop-Probe 'final'
    $p5 = Launch-Probe 'final' 'final_state_restored' 'B' $p4.launchId
    $finalStatus='PASS'
    Assert-Unchanged $before
    $result = 'PASS_FOR_REQUESTED_SCOPE'
} finally {
    try {
        if (Test-Path -LiteralPath $report) {
            $summary = [ordered]@{
                result=$result;mode='Lifecycle';startedAt=$started;finishedAt=(Get-Date).ToUniversalTime().ToString('o');sourceRoot=$root;stage=$stage;deviceId=$device;applicationId=$testId;steps=$steps.ToArray()
                reflectionAfterForceStop=$reflectionStatus
                signatureAfterForceStop=$signatureStatus
                updatePreservation=$updateStatus
                finalAfterForceStop=$finalStatus
                releaseSigning='NOT_RUN';schemaUpgrade='NOT_RUN';productionUiEndToEnd='NOT_RUN'
                note='현재 소스의 debug APK A/B 사이 버전 코드 증가 설치와 저장 완료 후 프로세스 강제 종료 검증. 전원 차단 및 저장 도중 종료는 미검증.'
            }
            $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $report 'summary.json') -Encoding UTF8
            Write-Host "결과: $result / 보고서: $report"
            if ($stage) { Write-Host "진단용 테스트 사본: $stage" }
        }
    } finally { if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
