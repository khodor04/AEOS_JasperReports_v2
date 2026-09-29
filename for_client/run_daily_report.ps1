<#
Wrapper for scheduled/unattended runs of generate_first_in_last_out.ps1.
Always generates YESTERDAY's report (the last fully-completed day) - the
interactive script prompts for dates when run manually, but Task Scheduler
has no console to answer prompts, so this always passes explicit dates.

Also enforces a 90-day retention policy on $OutDir: any file older than 90
days (by last-write time) gets deleted after each run, so the folder doesn't
grow forever.

Set the $OutDir / $RetentionDays below as needed.
#>

$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutDir         = Join-Path $ScriptDir "DailyReports"
$RetentionDays  = 90

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$outFile   = Join-Path $OutDir "FirstInLastOut_$yesterday.csv"

& (Join-Path $ScriptDir "generate_first_in_last_out.ps1") -DateFrom $yesterday -DateTo $yesterday -OutFile $outFile

$cutoff = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem -Path $OutDir -File | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
    Write-Host "Deleting (older than $RetentionDays days): $($_.Name)"
    Remove-Item $_.FullName -Force
}
