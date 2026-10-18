#Requires -Version 5.1
<#
  Rewards Hub - Cloud Functions one-shot deploy (Windows PowerShell)
  -------------------------------------------------------------------
  Usage:
      powershell -ExecutionPolicy Bypass -File .\deploy_all.ps1

  Prereqs:
      - Node.js 20+           https://nodejs.org
      - firebase-tools        npm install -g firebase-tools
      - firebase login        (sign in with your OWN Google account)
#>

$ErrorActionPreference = 'Continue'
$Project = 'flutter-offerwall-app'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

function HR   { Write-Host ("-" * 62) }
function Ok   { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Bad  { param([string]$m) Write-Host "  [X]  $m" -ForegroundColor Red }
function Warn { param([string]$m) Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Info { param([string]$m) Write-Host "  .    $m" -ForegroundColor Gray }
function Step { param([string]$m) Write-Host ""; Write-Host $m -ForegroundColor Cyan; HR }

# ---------------------------------------------------------------- STEP 0
Step 'STEP 0 - check tools'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Bad 'node not found'
    Info 'install Node.js 20+ from https://nodejs.org'
    exit 1
}
Ok ("node " + (& node -v))

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Bad 'npm not found (comes with Node.js)'
    exit 1
}
Ok ("npm " + ((& npm -v) | Select-Object -First 1))

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Bad 'firebase CLI not found'
    Info 'install: npm install -g firebase-tools'
    exit 1
}
Ok ("firebase " + ((& firebase --version) | Select-Object -First 1))

if (-not (Test-Path -LiteralPath (Join-Path $Root 'firebase.json'))) {
    Bad "firebase.json not found in: $Root"
    Info 'run this script from the repo root (cd FlutterOfferwallApp)'
    exit 1
}
Ok 'repo root verified (firebase.json found)'

# ---------------------------------------------------------------- STEP 1
Step 'STEP 1 - firebase login'

$loginOut = (& firebase login:list 2>&1 | Out-String)
if ($loginOut -match 'No authorized accounts' -or $loginOut -match 'not logged in') {
    Bad 'not logged in'
    Info 'run: firebase login'
    Info '(a browser opens - sign in with your own Google account)'
    exit 1
}
Ok 'logged in'

# ---------------------------------------------------------------- STEP 2
Step 'STEP 2 - project access'

$projOut = (& firebase projects:list --non-interactive 2>&1 | Out-String)
if ($projOut -match [regex]::Escape($Project)) {
    Ok "project reachable: $Project"
} else {
    Bad "cannot access project '$Project'"
    Info 'check that you signed in with the account that owns this project'
    exit 1
}

# ---------------------------------------------------------------- STEP 3
Step 'STEP 3 - npm install (functions)'

Push-Location -LiteralPath (Join-Path $Root 'functions')
& npm install --silent 2>&1 | Select-Object -Last 3
$rc = $LASTEXITCODE
if ($rc -eq 0) {
    Ok 'npm install done'
} else {
    Bad 'npm install failed'
    Pop-Location
    exit 1
}

# ---------------------------------------------------------------- STEP 4
Step 'STEP 4 - TypeScript build'

& npm run build 2>&1 | Select-Object -Last 5
Pop-Location

if (Test-Path -LiteralPath (Join-Path $Root 'functions\lib\index.js')) {
    Ok 'compiled -> functions\lib\index.js'
} else {
    Bad 'compile failed'
    exit 1
}

# ---------------------------------------------------------------- STEP 5
Step 'STEP 5 - secret OFFERWALL_SECRET'

& firebase functions:secrets:access OFFERWALL_SECRET --project $Project *> $null
if ($LASTEXITCODE -eq 0) {
    Ok 'secret already exists - skipped'
} else {
    $secretVal = ''
    try {
        $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = New-Object 'System.Byte[]' 32
        $rng.GetBytes($bytes)
        $secretVal = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    } catch {
        $secretVal = ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
    }

    $tmp = Join-Path $env:TEMP ("offerwall_secret_" + [guid]::NewGuid().ToString('N') + ".txt")
    [System.IO.File]::WriteAllText($tmp, $secretVal)

    & firebase functions:secrets:set OFFERWALL_SECRET --project $Project "--data-file=$tmp" 2>&1 |
        Select-Object -Last 3
    $setRc = $LASTEXITCODE
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

    if ($setRc -eq 0) {
        Ok 'secret created (32 random bytes)'
    } else {
        Warn 'auto-create failed - register it manually:'
        Write-Host ("     OFFERWALL_SECRET = " + $secretVal) -ForegroundColor Yellow
        Info 'manual: firebase functions:secrets:set OFFERWALL_SECRET'
    }
}

# ---------------------------------------------------------------- STEP 6
Step "STEP 6 - deploy Cloud Functions ($Project)"

Info 'if asked to enable APIs -> click "Enable" (first run only)'
Info 'this takes 3-5 minutes, please wait...'
Write-Host ""

& firebase deploy --only functions --project $Project 2>&1 | Select-Object -Last 30

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Bad 'function deploy failed (see log above)'
    Info "tip: 'API has not been used' -> enable it in the console, then re-run"
    exit 1
}
Ok 'functions deployed'

# ---------------------------------------------------------------- STEP 7
Step 'STEP 7 - apply anti-fraud Firestore rules'

$rules = Join-Path $Root 'firestore.rules'
$anti  = Join-Path $Root 'firestore.rules.antifraud'
$bak   = Join-Path $Root 'firestore.rules.clientonly.bak'

if (Test-Path -LiteralPath $anti) {
    Copy-Item -LiteralPath $rules -Destination $bak  -Force
    Copy-Item -LiteralPath $anti  -Destination $rules -Force

    & firebase deploy --only firestore:rules --project $Project 2>&1 | Select-Object -Last 8

    if ($LASTEXITCODE -eq 0) {
        Ok 'anti-fraud rules deployed (points/tx are now server-only)'
        Info "backup saved: firestore.rules.clientonly.bak"
    } else {
        Warn 'rules deploy failed - restoring client-writable version'
        Copy-Item -LiteralPath $bak -Destination $rules -Force
    }
} else {
    Info 'firestore.rules.antifraud not found - skipped'
}

# ---------------------------------------------------------------- STEP 8
Step 'STEP 8 - verify'

& firebase functions:list --project $Project 2>&1 | Select-Object -Last 12
Write-Host ""
Info 'endpoints:'
foreach ($fn in @('offerwallPostback', 'claimOffer', 'requestPayout')) {
    Write-Host ("     https://us-central1-$Project.cloudfunctions.net/$fn")
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  DEPLOY COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:"
Write-Host "   1) confirm the 3 functions appear in STEP 8 list above"
Write-Host "   2) register the postback URL in your offerwall provider dashboard:"
Write-Host "      https://us-central1-$Project.cloudfunctions.net/offerwallPostback"
Write-Host "   3) tell the assistant it is deployed -> remote verification runs"
