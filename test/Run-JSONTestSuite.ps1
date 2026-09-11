#Requires -Version 5.1
<#
.SYNOPSIS
    Test AHK20_JSON.ahk with nst/JSONTestSuite and write a Markdown report.

.DESCRIPTION
    Runs each JSON file in an isolated AutoHotkey v2 process through
    JSONTestAdapter.ahk. Writes reports/JSONTestSummary.md only.
#>

[CmdletBinding()]
param(
    [string]$AutoHotkeyExe = "",

    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 5,

    [bool]$EnableDebug = $false
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Quote-Argument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Value.Contains('"')) {
        throw "A command-line path contains an unsupported quote: $Value"
    }

    return '"' + $Value + '"'
}

function ConvertTo-MarkdownCell {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).
        Replace("\", "\\").
        Replace("|", "\|").
        Replace("`r", " ").
        Replace("`n", " ")
}

function Get-ExpectedResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    switch -Regex ($FileName) {
        '^y_' { return "MUST_ACCEPT" }
        '^n_' { return "MUST_REJECT" }
        '^i_' { return "IMPLEMENTATION_DEFINED" }
        default { return "UNKNOWN" }
    }
}

function Get-Verdict {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Actual
    )

    if ($Actual -eq "TIMEOUT" -or $Actual -eq "CRASH") {
        return "ERROR"
    }

    if ($Expected -eq "MUST_ACCEPT") {
        if ($Actual -eq "ACCEPT") { return "PASS" }
        return "FAIL"
    }

    if ($Expected -eq "MUST_REJECT") {
        if ($Actual -eq "REJECT") { return "PASS" }
        return "FAIL"
    }

    if ($Expected -eq "IMPLEMENTATION_DEFINED") {
        if ($Actual -eq "ACCEPT" -or $Actual -eq "REJECT") {
            return "INFO"
        }
    }

    return "ERROR"
}

function Get-ConsoleColor {
    param([string]$Verdict)

    switch ($Verdict) {
        "PASS"  { return "Green" }
        "FAIL"  { return "Red" }
        "INFO"  { return "Cyan" }
        "ERROR" { return "Magenta" }
        default { return "Gray" }
    }
}

$scriptDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
    $scriptDirectory = (Get-Location).ProviderPath
}

$repoRoot = Split-Path $scriptDirectory -Parent
$adapterPath = Join-Path $scriptDirectory "JSONTestAdapter.ahk"
$jsonLibraryPath = Join-Path $repoRoot "AHK20_JSON.ahk"
$testDirectory = Join-Path $scriptDirectory "JSONTestSuite\TestSamples"
$reportDirectory = Join-Path $scriptDirectory "reports"
$reportPath = Join-Path $reportDirectory "JSONTestSummary.md"
$logDirectory = Join-Path $repoRoot "log"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $logDirectory "Run-JSONTestSuite_$stamp.log"
$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
    "AHK-JSONTestSuite_" + [guid]::NewGuid().ToString("N")
)

if ([string]::IsNullOrWhiteSpace($AutoHotkeyExe)) {
    $candidates = @(
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe"
    )

    $AutoHotkeyExe = $candidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($AutoHotkeyExe)) {
        $command = Get-Command "AutoHotkey64.exe" -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $AutoHotkeyExe = $command.Source
        }
    }
}

foreach ($requiredFile in @($AutoHotkeyExe, $adapterPath, $jsonLibraryPath)) {
    if ([string]::IsNullOrWhiteSpace($requiredFile) -or
        -not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file not found: $requiredFile"
    }
}

if (-not (Test-Path -LiteralPath $testDirectory -PathType Container)) {
    throw "JSONTestSuite test directory not found: $testDirectory"
}

$AutoHotkeyExe = (Resolve-Path -LiteralPath $AutoHotkeyExe).Path
$testFiles = @(Get-ChildItem -LiteralPath $testDirectory -Filter "*.json" -File |
    Sort-Object Name)

if ($testFiles.Count -eq 0) {
    throw "No JSON test files found in: $testDirectory"
}

New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null

if ($EnableDebug) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

function Write-DebugLog {
    param([string]$Message)

    if ($EnableDebug) {
        $line = "{0:o} {1}" -f (Get-Date), $Message
        [System.IO.File]::AppendAllText(
            $logPath,
            $line + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
}

$startedAt = Get-Date
$results = New-Object "System.Collections.Generic.List[object]"
Write-DebugLog "Initialization complete; tests=$($testFiles.Count); timeout=$TimeoutSeconds"

Write-Host "Running $($testFiles.Count) JSONTestSuite cases with $AutoHotkeyExe"

try {
    for ($index = 0; $index -lt $testFiles.Count; $index++) {
        $testFile = $testFiles[$index]
        $resultFile = Join-Path $tempDirectory ("{0:D4}.txt" -f ($index + 1))
        $expected = Get-ExpectedResult $testFile.Name
        $actual = "CRASH"
        $exitCode = $null
        $errorType = ""
        $errorMessage = ""
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $process = $null

        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $AutoHotkeyExe
            $startInfo.Arguments = @(
                "/ErrorStdOut",
                (Quote-Argument $adapterPath),
                (Quote-Argument $testFile.FullName),
                (Quote-Argument $resultFile)
            ) -join " "
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.WorkingDirectory = $scriptDirectory

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo

            if (-not $process.Start()) {
                throw "Failed to start AutoHotkey."
            }

            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $actual = "TIMEOUT"
                $errorType = "Timeout"
                $errorMessage = "Exceeded $TimeoutSeconds second(s)."
                try { $process.Kill() } catch {}
                try { $process.WaitForExit(1000) | Out-Null } catch {}
            }
            else {
                $exitCode = $process.ExitCode

                if (-not (Test-Path -LiteralPath $resultFile -PathType Leaf)) {
                    throw "Adapter did not create a result file (exit code $exitCode)."
                }

                $text = [System.IO.File]::ReadAllText(
                    $resultFile,
                    [System.Text.UTF8Encoding]::new($false, $true)
                ).TrimStart([char]0xFEFF)

                if ([string]::IsNullOrWhiteSpace($text)) {
                    throw "Adapter result file is empty."
                }

                $fields = $text -split "`t", 3
                $status = $fields[0].Trim()

                if ($status -ne "ACCEPT" -and $status -ne "REJECT") {
                    throw "Unknown adapter status: $status"
                }

                $expectedExitCode = if ($status -eq "ACCEPT") { 0 } else { 1 }
                if ($exitCode -ne $expectedExitCode) {
                    throw "Adapter reported $status but exited with code $exitCode."
                }

                $actual = $status
                if ($fields.Count -ge 2) { $errorType = $fields[1] }
                if ($fields.Count -ge 3) { $errorMessage = $fields[2].TrimEnd() }
            }
        }
        catch {
            $actual = "CRASH"
            $errorType = $_.Exception.GetType().Name
            $errorMessage = $_.Exception.Message
        }
        finally {
            $stopwatch.Stop()
            if ($null -ne $process) { $process.Dispose() }
            if (Test-Path -LiteralPath $resultFile) {
                Remove-Item -LiteralPath $resultFile -Force
            }
        }

        $verdict = Get-Verdict $expected $actual
        $result = [PSCustomObject]@{
            FileName     = $testFile.Name
            Group        = $testFile.Name.Substring(0, 1)
            Expected     = $expected
            Actual       = $actual
            Verdict      = $verdict
            ExitCode     = $exitCode
            Milliseconds = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
            ErrorType    = $errorType
            ErrorMessage = $errorMessage
        }
        $results.Add($result)

        $progress = "[{0,3}/{1,3}] {2,-5} {3,-7} {4}" -f (
            $index + 1), $testFiles.Count, $verdict, $actual, $testFile.Name
        Write-Host $progress -ForegroundColor (Get-ConsoleColor $verdict)
        Write-DebugLog (
            "test=$($testFile.Name); expected=$expected; actual=$actual; " +
            "verdict=$verdict; exit=$exitCode; ms=$($result.Milliseconds); " +
            "type=$errorType; message=$errorMessage"
        )
    }
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}

$finishedAt = Get-Date
$duration = $finishedAt - $startedAt
$resultArray = $results.ToArray()

$passCount = @($resultArray | Where-Object Verdict -eq "PASS").Count
$failCount = @($resultArray | Where-Object Verdict -eq "FAIL").Count
$infoCount = @($resultArray | Where-Object Verdict -eq "INFO").Count
$errorCount = @($resultArray | Where-Object Verdict -eq "ERROR").Count
$acceptedCount = @($resultArray | Where-Object Actual -eq "ACCEPT").Count
$rejectedCount = @($resultArray | Where-Object Actual -eq "REJECT").Count
$timeoutCount = @($resultArray | Where-Object Actual -eq "TIMEOUT").Count
$crashCount = @($resultArray | Where-Object Actual -eq "CRASH").Count

$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine("# AHK20_JSON JSONTestSuite Report")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("## Run metadata")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("- Generated: $($finishedAt.ToString('yyyy-MM-dd HH:mm:ss'))")
[void]$builder.AppendLine("- AutoHotkey: $(ConvertTo-MarkdownCell $AutoHotkeyExe)")
[void]$builder.AppendLine('- JSON parser: AHK20_JSON.ahk')
[void]$builder.AppendLine('- Test directory: test/JSONTestSuite/TestSamples')
[void]$builder.AppendLine("- Timeout per test: $TimeoutSeconds second(s)")
[void]$builder.AppendLine("- Duration: $([Math]::Round($duration.TotalSeconds, 3)) second(s)")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("## Summary")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("| Total | PASS | FAIL | INFO | ERROR | Accepted | Rejected | Timeout | Crash |")
[void]$builder.AppendLine("|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
[void]$builder.AppendLine("| $($resultArray.Count) | $passCount | $failCount | $infoCount | $errorCount | $acceptedCount | $rejectedCount | $timeoutCount | $crashCount |")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("## Categories")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("| Category | Total | PASS | FAIL | INFO | ERROR | Accepted | Rejected |")
[void]$builder.AppendLine("|---|---:|---:|---:|---:|---:|---:|---:|")

foreach ($group in @("y", "n", "i")) {
    $items = @($resultArray | Where-Object Group -eq $group)
    $label = switch ($group) {
        "y" { "y_ must accept" }
        "n" { "n_ must reject" }
        "i" { "i_ implementation defined" }
    }
    $groupPass = @($items | Where-Object Verdict -eq "PASS").Count
    $groupFail = @($items | Where-Object Verdict -eq "FAIL").Count
    $groupInfo = @($items | Where-Object Verdict -eq "INFO").Count
    $groupError = @($items | Where-Object Verdict -eq "ERROR").Count
    $groupAccept = @($items | Where-Object Actual -eq "ACCEPT").Count
    $groupReject = @($items | Where-Object Actual -eq "REJECT").Count
    [void]$builder.AppendLine("| $label | $($items.Count) | $groupPass | $groupFail | $groupInfo | $groupError | $groupAccept | $groupReject |")
}

[void]$builder.AppendLine("")
[void]$builder.AppendLine("## Failures and errors")
[void]$builder.AppendLine("")
$problems = @($resultArray | Where-Object {
    $_.Verdict -eq "FAIL" -or $_.Verdict -eq "ERROR"
})

if ($problems.Count -eq 0) {
    [void]$builder.AppendLine("No conformance failures, crashes, or timeouts were found.")
}
else {
    [void]$builder.AppendLine("| File | Expected | Actual | Verdict | Error type | Error message |")
    [void]$builder.AppendLine("|---|---|---|---|---|---|")
    foreach ($problem in $problems) {
        [void]$builder.AppendLine("| $(ConvertTo-MarkdownCell $problem.FileName) | $($problem.Expected) | $($problem.Actual) | $($problem.Verdict) | $(ConvertTo-MarkdownCell $problem.ErrorType) | $(ConvertTo-MarkdownCell $problem.ErrorMessage) |")
    }
}

Write-Utf8NoBom -Path $reportPath -Content $builder.ToString()
Write-DebugLog "Report written: $reportPath; pass=$passCount; fail=$failCount; info=$infoCount; error=$errorCount"

Write-Host ""
Write-Host "Report: $reportPath"
Write-Host "PASS=$passCount FAIL=$failCount INFO=$infoCount ERROR=$errorCount"
if ($EnableDebug) { Write-Host "Debug log: $logPath" }

if ($failCount -gt 0 -or $errorCount -gt 0) {
    exit 1
}

exit 0
