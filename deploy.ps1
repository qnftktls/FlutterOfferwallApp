#Requires -Version 5.1

<#
  Rewards Hub - LIVE function deploy (Windows PowerShell 5.1 compatible)
  ======================================================================
  Why this exists
  ---------------
  `firebase deploy` on Windows can hang forever when the CLI stops on an
  interactive prompt. When its output is redirected, PowerShell buffers it
  or hides it, so you stare at a blank screen for 20 minutes and never find
  out that the CLI was actually waiting for a keypress the whole time.

  This script removes every way that can happen:

    1. --non-interactive                 -> the CLI errors out instead of
                                            waiting for input.
    2. CI / FIREBASE_CLI_DISABLE_PROMPTS -> skips first-run + analytics
                                            prompts.
    3. Output goes to deploy.log and is TAILED BY BYTE OFFSET, so you always
       see live progress and never lose a partially-written line.
    4. PROMPT DETECTION: if the log shows an interactive prompt and output
       then stops for -IdleKillSeconds, the script kills the whole process
       TREE and tells you exactly which line caused it.
    5. Watchdog: hard -TimeoutSeconds cap, exit code 124.

  Usage:
      powershell -ExecutionPolicy Bypass -File .\deploy.ps1
      powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -ApplyRules
#>

param(
    # Also apply the anti-fraud Firestore rules afterwards (points/tx
    # become server-only). Off by default so the app can never break.
    [switch]$ApplyRules,

    # Hard cap for a single firebase command, in seconds.
    [int]$TimeoutSeconds = 600,

    # If a prompt was printed and output then stalls this long, kill it.
    [int]$IdleKillSeconds = 45
)

$ErrorActionPreference = 'Continue'
$Project = 'flutter-offerwall-app'
$Root    = $PSScriptRoot
if ([string]::IsNullOrEmpty($Root)) { $Root = (Get-Location).Path }
Set-Location -LiteralPath $Root

function HR   { Write-Host ("-" * 64) }
function Ok   { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Bad  { param([string]$m) Write-Host "  [X]  $m" -ForegroundColor Red }
function Warn { param([string]$m) Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Info { param([string]$m) Write-Host "  .    $m" -ForegroundColor Gray }
function Step { param([string]$m) Write-Host ""; Write-Host $m -ForegroundColor Cyan; HR }

# Never let the CLI block on an interactive question.
$env:CI = 'true'
$env:FIREBASE_CLI_DISABLE_PROMPTS = '1'

# Strings the firebase CLI prints when it wants a keypress. If we see one of
# these and output then stops, we are definitively hung.
$PromptPattern = '(?i)(would you like|do you wish|do you want|select an option|' +
                 'enable (the|following)|to continue,|enter a value|choice \[|\(y/n\)|\(y/N\)|' +
                 'press any key|\[Y/n\]|\[y/N\])'

# ---------------------------------------------------------------- run helper
function Invoke-Live {
    param(
        [Parameter(Mandatory = $true)][string]$CommandLine,
        [Parameter(Mandatory = $true)][string]$LogFile,
        [int]$LimitSeconds = 600
    )

    if (Test-Path -LiteralPath $LogFile) {
        Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
    }

    # NOTE: do not name this $args - that is a PowerShell automatic variable.
    $cmdArgs = '/c ' + $CommandLine + ' > "' + $LogFile + '" 2>&1'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName         = 'cmd.exe'
    $psi.Arguments        = $cmdArgs
    $psi.UseShellExecute  = $false
    $psi.CreateNoWindow   = $true
    $psi.WorkingDirectory = $Root

    $proc   = [System.Diagnostics.Process]::Start($psi)
    $procId = $proc.Id

    function Stop-Tree {
        param([int]$TargetId)
        # /T kills children too. $proc.Kill() alone leaks the node.js child.
        try { & taskkill /T /F /PID $TargetId 2>&1 | Out-Null } catch { }
    }

    $start      = Get-Date
    $offset     = [long]0
    $pending    = ''
    $lastOutput = Get-Date
    $killed     = $false
    $promptLine = ''
    $reason     = ''

    while ($true) {
        $exited = $false
        try { $exited = $proc.HasExited } catch { $exited = $true }
        if ($exited) { break }

        Start-Sleep -Milliseconds 1000

        # ---- read only the NEW bytes; keeps partial lines across polls ----
        if (Test-Path -LiteralPath $LogFile) {
            $fs = $null
            try {
                $fs = [System.IO.File]::Open($LogFile,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::ReadWrite)
                if ($fs.Length -gt $offset) {
                    [void]$fs.Seek($offset, [System.IO.SeekOrigin]::Begin)
                    $sr    = New-Object System.IO.StreamReader($fs)
                    $chunk = $sr.ReadToEnd()
                    $offset = $fs.Length
                    $sr.Dispose()
                } else {
                    $chunk = ''
                }
            } catch {
                $chunk = ''
            } finally {
                if ($fs -ne $null) { $fs.Dispose() }
            }

            if ($chunk.Length -gt 0) {
                $lastOutput = Get-Date
                $pending += $chunk

                $nl = $pending.LastIndexOf("`n")
                if ($nl -ge 0) {
                    $complete = $pending.Substring(0, $nl)
                    $pending  = $pending.Substring($nl + 1)
                    foreach ($ln in ($complete -split "`n")) {
                        $line = $ln.TrimEnd("`r")
                        Write-Host ('  | ' + $line) -ForegroundColor DarkGray
                        if ($line -match $PromptPattern) { $promptLine = $line }
                    }
                }
            }
        }

        $idle = ((Get-Date) - $lastOutput).TotalSeconds

        # ---- definitive hang: CLI asked a question, then went silent ----
        if ($promptLine -ne '' -and $idle -gt $IdleKillSeconds) {
            Write-Host ""
            Warn "the CLI printed an interactive prompt and then stopped for $([int]$idle)s"
            Info ("prompt was: " + $promptLine.Trim())
            Info "this is the classic Windows firebase-CLI hang. killing the process tree."
            Stop-Tree -TargetId $procId
            $killed = $true
            $reason = 'interactive prompt'
            break
        }

        # ---- hard watchdog ----
        if (((Get-Date) - $start).TotalSeconds -gt $LimitSeconds) {
            Write-Host ""
            Warn "exceeded the $LimitSeconds s watchdog. killing the process tree."
            Stop-Tree -TargetId $procId
            $killed = $true
            $reason = 'timeout'
            break
        }
    }

    try { $proc.WaitForExit(5000) | Out-Null } catch { }

    # ---- flush whatever arrived after the final poll ----
    if ($pending -ne '') {
        Write-Host ('  | ' + $pending.TrimEnd("`r`n")) -ForegroundColor DarkGray
    }
    if (Test-Path -LiteralPath $LogFile) {
        try {
            $fs = [System.IO.File]::Open($LogFile,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite)
            if ($fs.Length -gt $offset) {
                [void]$fs.Seek($offset, [System.IO.SeekOrigin]::Begin)
                $sr    = New-Object System.IO.StreamReader($fs)
                $rest  = $sr.ReadToEnd()
                $sr.Dispose()
                foreach ($ln in ($rest -split "`n")) {
                    if ($ln.Trim().Length -gt 0) {
                        Write-Host ('  | ' + $ln.TrimEnd("`r")) -ForegroundColor DarkGray
                    }
                }
            }
            $fs.Dispose()
        } catch { }
    }

    $code = 124
    if (-not $killed) { try { $code = $proc.ExitCode } catch { $code = 1 } }

    return @{
        ExitCode = $code
        Killed   = $killed
        Reason   = $reason
        LogFile  = $LogFile
    }
}

function Show-LogTail {
    param([string]$LogFile, [int]$Lines = 40)
    if (-not (Test-Path -LiteralPath $LogFile)) { return }
    Write-Host ""
    Write-Host "  ---- last $Lines lines of $(Split-Path -Leaf $LogFile) ----" -ForegroundColor Yellow
    $all = @(Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue)
    $from = [Math]::Max(0, $all.Count - $Lines)
    for ($i = $from; $i -lt $all.Count; $i++) {
        Write-Host ('  ' + $all[$i]) -ForegroundColor Yellow
    }
    Write-Host "  ------------------------------------------" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- STEP 0
Step 'STEP 0 - tools'
foreach ($t in @('node', 'npm', 'firebase')) {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        Bad "$t not found"
        if ($t -eq 'firebase') { Info 'fix: npm install -g firebase-tools' }
        exit 1
    }
}
Ok ("node     " + ((& node -v) | Select-Object -First 1))
Ok ("firebase " + ((& firebase --version) | Select-Object -First 1))

if (-not (Test-Path -LiteralPath (Join-Path $Root 'firebase.json'))) {
    Bad "firebase.json not found in $Root - run this from the repo root"
    exit 1
}
Ok 'repo root verified'

# ---------------------------------------------------------------- STEP 1
Step 'STEP 1 - firebase login'
$loginOut = (& firebase login:list 2>&1 | Out-String)
if ($loginOut -match 'No authorized accounts') {
    Bad 'not logged in'; Info 'fix: firebase login'; exit 1
}
Ok 'logged in'

# ---------------------------------------------------------------- STEP 2
Step 'STEP 2 - build functions'
Push-Location -LiteralPath (Join-Path $Root 'functions')
& npm install --silent 2>&1 | Select-Object -Last 2
& npm run build 2>&1 | Select-Object -Last 3
Pop-Location
if (-not (Test-Path -LiteralPath (Join-Path $Root 'functions\lib\index.js'))) {
    Bad 'TypeScript compile failed - functions/lib/index.js missing'; exit 1
}
Ok 'TypeScript compiled'

# ---------------------------------------------------------------- STEP 3
Step "STEP 3 - deploy Cloud Functions ($Project)"
Info 'live output streams below. a stuck prompt is killed automatically.'
Info 'first run usually takes 3-6 minutes.'
Write-Host ""

$res = Invoke-Live -CommandLine ("firebase --non-interactive deploy --only functions --project " + $Project + " --force") `
                   -LogFile (Join-Path $Root 'deploy.log') `
                   -LimitSeconds $TimeoutSeconds

if ($res.Killed) {
    Write-Host ""
    Bad "deploy aborted by the script ($($res.Reason))"
    Show-LogTail -LogFile $res.LogFile
    Info 'the log above is the whole story - copy it back if it is unclear.'
    exit 1
}
if ($res.ExitCode -ne 0) {
    Write-Host ""
    Bad "deploy failed (exit $($res.ExitCode))"
    Show-LogTail -LogFile $res.LogFile
    exit 1
}
Ok 'functions deployed'

# ---------------------------------------------------------------- STEP 4
Step 'STEP 4 - verify the 3 endpoints'
Start-Sleep -Seconds 3
$alive = 0
foreach ($fn in @('offerwallPostback', 'claimOffer', 'requestPayout')) {
    $url = "https://us-central1-$Project.cloudfunctions.net/$fn"
    try {
        $r = Invoke-WebRequest -Uri $url -Method Post -TimeoutSec 20 `
             -ContentType 'application/json' -Body '{"data":{}}' -UseBasicParsing
        $code = [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } else { $code = 0 }
    }
    if ($code -in @(400, 401, 403, 500)) { Ok "$fn -> HTTP $code (live)"; $alive++ }
    elseif ($code -eq 404)               { Bad "$fn -> HTTP 404 (not deployed)" }
    else                                 { Warn "$fn -> HTTP $code" }
}
if ($alive -eq 3) { Ok 'all 3 functions are live' } else { Warn "$alive/3 responding" }

# ---------------------------------------------------------------- STEP 5
Step 'STEP 5 - anti-fraud Firestore rules'
if (-not $ApplyRules) {
    Warn 'SKIPPED (safe default) - the app keeps working end to end'
    Info 'points/tx stay client-writable until you opt in.'
    Info 're-run with -ApplyRules once every credit path is server-backed:'
    Info "  powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -ApplyRules"
} else {
    $rules = Join-Path $Root 'firestore.rules'
    $bak   = Join-Path $Root 'firestore.rules.clientonly.bak'
    $anti  = Join-Path $Root 'firestore.rules.antifraud'

    if (-not (Test-Path -LiteralPath $anti)) {
        Bad "missing $anti - cannot apply anti-fraud rules"; exit 1
    }
    Copy-Item -LiteralPath $rules -Destination $bak  -Force
    Copy-Item -LiteralPath $anti  -Destination $rules -Force

    $r2 = Invoke-Live -CommandLine ("firebase --non-interactive deploy --only firestore:rules --project " + $Project + " --force") `
                      -LogFile (Join-Path $Root 'rules.log') -LimitSeconds 180
    if ($r2.ExitCode -eq 0) {
        Ok 'anti-fraud rules deployed - points/tx are now server-only'
    } else {
        Warn 'rules deploy failed - restoring the client-writable version'
        Copy-Item -LiteralPath $bak -Destination $rules -Force
        Show-LogTail -LogFile $r2.LogFile -Lines 25
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  DONE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Info 'logs: deploy.log, rules.log'
