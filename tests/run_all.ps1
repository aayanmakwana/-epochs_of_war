# Runs the full headless test suite.
#   powershell -ExecutionPolicy Bypass -File tests\run_all.ps1            # everything
#   powershell -ExecutionPolicy Bypass -File tests\run_all.ps1 -Filter step3
# Exit code 0 = all passed.
param(
    [string]$Filter = "",
    [string]$Godot = ""
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
if ($Godot -eq "") {
    $Godot = Get-ChildItem -Path (Join-Path $root "tools\godot") -Filter "Godot_v4*_console.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Godot -or -not (Test-Path $Godot)) {
    Write-Host "Godot console binary not found in tools\godot. Pass -Godot <path>."
    exit 2
}
$logDir = Join-Path $root "tests\logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$errorPattern = "SCRIPT ERROR|Parse Error|Compile Error|ERROR:|Failed to load script"
$failed = @()

function Invoke-Godot([string[]]$GodotArgs, [string]$LogName) {
    $log = Join-Path $logDir $LogName
    & $Godot @GodotArgs *> $log
    $code = $LASTEXITCODE
    return @{ Code = $code; Log = $log; Text = (Get-Content $log -Raw) }
}

Write-Host "== Import (builds .godot cache / class_name registry) =="
$r = Invoke-Godot @("--headless", "--path", $root, "--import") "import.log"
if ($r.Text -match $errorPattern) {
    Write-Host "Import reported errors, see $($r.Log)"
    Select-String -Path $r.Log -Pattern $errorPattern | Select-Object -First 20 | ForEach-Object { Write-Host "  $($_.Line)" }
    $failed += "import"
}

Write-Host "== Smoke: run main scene headless for 120 frames =="
$r = Invoke-Godot @("--headless", "--path", $root, "--quit-after", "120") "smoke.log"
if ($r.Text -match $errorPattern) {
    Write-Host "  FAIL (errors in output, see $($r.Log))"
    Select-String -Path $r.Log -Pattern $errorPattern | Select-Object -First 20 | ForEach-Object { Write-Host "  $($_.Line)" }
    $failed += "smoke"
} else {
    Write-Host "  PASS"
}

$tests = Get-ChildItem -Path (Join-Path $root "tests") -Filter "test_*.gd" | Where-Object { $_.Name -ne "test_base.gd" } | Sort-Object Name
foreach ($t in $tests) {
    if ($Filter -ne "" -and $t.Name -notlike "*$Filter*") { continue }
    $r = Invoke-Godot @("--headless", "--path", $root, "-s", "res://tests/$($t.Name)") ($t.BaseName + ".log")
    $ok = ($r.Code -eq 0) -and ($r.Text -match "RESULT: PASS") -and -not ($r.Text -match "SCRIPT ERROR|Parse Error|Compile Error")
    if ($ok) {
        $summary = ([regex]::Match($r.Text, "--- (\d+) passed, (\d+) failed ---")).Value
        Write-Host "== $($t.Name): PASS $summary"
    } else {
        Write-Host "== $($t.Name): FAIL (exit $($r.Code), log $($r.Log))"
        Get-Content $r.Log | Select-Object -Last 25 | ForEach-Object { Write-Host "    $_" }
        $failed += $t.Name
    }
}

if ($failed.Count -gt 0) {
    Write-Host "FAILED: $($failed -join ', ')"
    exit 1
}
Write-Host "ALL TESTS PASSED"
exit 0
