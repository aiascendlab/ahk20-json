#Requires -Version 5.1
<#
.SYNOPSIS
    Run AHK20_JSON unit tests and the CI example.

.PARAMETER Suite
    Also run JSONTestSuite (318 isolated processes).
#>
[CmdletBinding()]
param(
    [switch]$Suite
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repoRoot

function Get-AutoHotkeyExe {
    $candidates = @(
        $env:AHK20_JSON_AHK,
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe"
    )

    foreach ($path in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and
            (Test-Path -LiteralPath $path -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    $command = Get-Command "AutoHotkey64.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "AutoHotkey v2 executable not found. Install AHK v2 or set AHK20_JSON_AHK."
}

function Invoke-Ahk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Missing script: $ScriptPath"
    }

    $process = Start-Process -FilePath $script:AutoHotkeyExe -ArgumentList @(
        "/ErrorStdOut",
        $ScriptPath
    ) -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "Failed ($($process.ExitCode)): $ScriptPath"
    }
}

$script:AutoHotkeyExe = Get-AutoHotkeyExe
Write-Host "AutoHotkey: $script:AutoHotkeyExe"

Invoke-Ahk (Join-Path $repoRoot "test\JSON_full_test.ahk")
Invoke-Ahk (Join-Path $repoRoot "examples\basic.ahk")

if ($Suite) {
    $runner = Join-Path $repoRoot "test\Run-JSONTestSuite.ps1"
    & $runner
    if ($LASTEXITCODE -ne 0) {
        throw "JSONTestSuite failed with exit $LASTEXITCODE"
    }
}

Write-Host "check passed"
exit 0
