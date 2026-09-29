<#
AEOS First IN / Last OUT report - CSV generator, no Excel/Python needed.
Self-contained: just run this one .ps1 file, it prompts for the date range.
Uses .NET SqlClient (built into Windows) with a dedicated low-privilege SQL
login that can only read this one report view.

Usage:
    .\generate_first_in_last_out.ps1                 # prompts for dates, uses defaults below
    .\generate_first_in_last_out.ps1 -DateFrom 2026-06-24 -DateTo 2026-06-25   # skip the prompts
#>

param(
    [string]$Server   = "CHANGE_ME_TO_CLIENT_SQL_SERVER_HOSTNAME_OR_IP",
    [string]$Database = "aeosdb",
    [string]$Username = "AeosReportReader",
    [string]$Password = "CHANGE_ME_STRONG_PASSWORD",
    [string]$DateFrom,
    [string]$DateTo,
    [string]$OutFile
)

if (-not $DateFrom) { $DateFrom = Read-Host "Start date (YYYY-MM-DD)" }
if (-not $DateTo)   { $DateTo   = Read-Host "End date, inclusive (YYYY-MM-DD)" }

try {
    $from = [datetime]::ParseExact($DateFrom, "yyyy-MM-dd", $null)
    $to   = [datetime]::ParseExact($DateTo,   "yyyy-MM-dd", $null).AddDays(1).AddSeconds(-1)
} catch {
    Write-Error "Dates must be in YYYY-MM-DD format."
    exit 1
}

if (-not $OutFile) {
    $OutFile = Join-Path (Get-Location) "FirstInLastOut_${DateFrom}_to_${DateTo}.csv"
}
$XlsxFile = [System.IO.Path]::ChangeExtension($OutFile, ".xlsx")

function New-XlsxReport {
    param([object[]]$Rows, [string]$Path, [string]$SheetName = "First In Last Out")

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    function Esc([string]$s) {
        if ($null -eq $s) { return "" }
        $s = $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'",'&apos;'
        return $s
    }

    $headers = @("File No","Last Name","First Name","Department","Card No","Date","First In","Last Out","Duration","Events")
    $colLetters = @("A","B","C","D","E","F","G","H","I","J")
    $colWidths  = @(12,20,18,30,16,12,12,12,14,10)

    $contentTypes = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
"@

    $rootRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
"@

    $workbookRels = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"@

    $workbookXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="$(Esc $SheetName)" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"@

    $stylesXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="10"/><name val="Calibri"/></font><font><sz val="10"/><b/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1A3A5C"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>
</styleSheet>
"@

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')

    # OOXML CT_Worksheet requires this element order: sheetViews before cols before sheetData
    [void]$sb.Append('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')

    [void]$sb.Append('<cols>')
    for ($i = 0; $i -lt $colWidths.Count; $i++) {
        $n = $i + 1
        [void]$sb.Append("<col min=`"$n`" max=`"$n`" width=`"$($colWidths[$i])`" customWidth=`"1`"/>")
    }
    [void]$sb.Append('</cols>')

    [void]$sb.Append('<sheetData>')

    [void]$sb.Append('<row r="1">')
    for ($i = 0; $i -lt $headers.Count; $i++) {
        [void]$sb.Append("<c r=`"$($colLetters[$i])1`" t=`"inlineStr`" s=`"1`"><is><t>$(Esc $headers[$i])</t></is></c>")
    }
    [void]$sb.Append('</row>')

    $r = 2
    foreach ($row in $Rows) {
        [void]$sb.Append("<row r=`"$r`">")
        $vals = @($row."File No", $row."Last Name", $row."First Name", $row."Department", $row."Card No", $row."Date", $row."First In", $row."Last Out", $row."Duration", $row."Events")
        for ($i = 0; $i -lt $vals.Count; $i++) {
            [void]$sb.Append("<c r=`"$($colLetters[$i])$r`" t=`"inlineStr`"><is><t>$(Esc $vals[$i])</t></is></c>")
        }
        [void]$sb.Append('</row>')
        $r++
    }

    [void]$sb.Append('</sheetData></worksheet>')
    $sheetXml = $sb.ToString()

    if (Test-Path $Path) { Remove-Item $Path -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    function Add-Part($archive, $entryName, $content) {
        $entry = $archive.CreateEntry($entryName)
        $stream = $entry.Open()
        $bytes = $utf8NoBom.GetBytes($content)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
    }

    Add-Part $zip "[Content_Types].xml" $contentTypes
    Add-Part $zip "_rels/.rels" $rootRels
    Add-Part $zip "xl/workbook.xml" $workbookXml
    Add-Part $zip "xl/_rels/workbook.xml.rels" $workbookRels
    Add-Part $zip "xl/styles.xml" $stylesXml
    Add-Part $zip "xl/worksheets/sheet1.xml" $sheetXml

    $zip.Dispose()
}

$query = @"
SELECT
    file_number   AS [File No],
    last_name     AS [Last Name],
    initials      AS [First Name],
    department    AS [Department],
    card_number   AS [Card No],
    activity_date AS [Date],
    first_in      AS [First In],
    last_out      AS [Last Out],
    CASE WHEN duration_minutes IS NULL THEN NULL
         ELSE RIGHT('0' + CAST(duration_minutes / 60 AS VARCHAR), 2) + ':' + RIGHT('0' + CAST(duration_minutes % 60 AS VARCHAR), 2)
    END AS [Duration],
    event_count   AS [Events]
FROM dbo.vw_FirstInLastOut
WHERE activity_date >= @DateFrom AND activity_date <= @DateTo
ORDER BY last_name, initials, activity_date
"@

if ($Username) {
    $connString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True;"
} else {
    $connString = "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True;"
}

try {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
    $conn.Open()

    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $query
    $cmd.Parameters.AddWithValue("@DateFrom", $from) | Out-Null
    $cmd.Parameters.AddWithValue("@DateTo", $to) | Out-Null

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $table = New-Object System.Data.DataTable
    $adapter.Fill($table) | Out-Null

    Write-Host "Fetched $($table.Rows.Count) rows."

    $rows = $table | ForEach-Object {
        [PSCustomObject]@{
            "File No"    = $_."File No"
            "Last Name"  = $_."Last Name"
            "First Name" = $_."First Name"
            "Department" = $_."Department"
            "Card No"    = $_."Card No"
            "Date"       = if ($_."Date" -is [datetime]) { $_."Date".ToString("dd/MM/yyyy") } else { $_."Date" }
            "First In"   = if ($_."First In" -is [datetime]) { $_."First In".ToString("HH:mm:ss") } else { $_."First In" }
            "Last Out"   = if ($_."Last Out" -is [datetime]) { $_."Last Out".ToString("HH:mm:ss") } else { $_."Last Out" }
            "Duration"   = $_."Duration"
            "Events"     = $_."Events"
        }
    }

    $rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
    Write-Host "Saved: $OutFile"

    New-XlsxReport -Rows $rows -Path $XlsxFile
    Write-Host "Saved: $XlsxFile"
} catch {
    Write-Error "Failed: $_"
    exit 1
} finally {
    if ($conn -and $conn.State -eq 'Open') { $conn.Close() }
}
