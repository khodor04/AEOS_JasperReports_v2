# AEOS JasperReports v2

JasperReports report definitions and standalone report generators for [AEOS](https://www.nedapsecurity.com/access-control/aeos/), Nedap's access control system, backed by a Microsoft SQL Server (`aeosdb`) database.

## What's here

### `aeos_jasper_reports/`
The core Jasper report designs and their supporting SQL:

| Report | Purpose |
|---|---|
| `01_PersonnelReport.jrxml` | Employee/carrier roster with department, card, and access template info |
| `02_FirstInLastOutReport.jrxml` (+ `.jasper`) | Daily first-in / last-out attendance report |
| `03_WhoIsInReport.jrxml` | Who is currently present, by zone |
| `04_DeviceReport.jrxml` | Controllers and readers |
| `05_CircuitReport.jrxml` | Wired components (door contacts, REX, alarm inputs, locks) per controller |
| `06_AlarmReport.jrxml` | Alarm history with state/priority filtering |

`FirstInLastOut_standalone_query.sql` and `create_view_FirstInLastOut.sql` are the raw query and the `dbo.vw_FirstInLastOut` view the First In/Last Out report is built on.

`SCHEMA_REFERENCE.md` documents the actual `dbo` schema mapping used by each report, verified column meanings (e.g. `eventlog.intvalue` direction codes), and Jaspersoft Studio compilation/deployment notes.

### Standalone generators (no AEOS report engine required)
Three independent ways to produce the First In/Last Out report without going through AEOS's own Jasper integration:

- **`generate_first_in_last_out.ps1`** — self-contained PowerShell 5.1 script using only built-in .NET assemblies (`System.Data.SqlClient`, `System.IO.Compression`). Outputs both `.csv` and a hand-built `.xlsx`. No Excel, Python, or extra modules needed.
- **`generate_first_in_last_out.py`** — Python/`pyodbc`/`openpyxl` equivalent.
- **`run_daily_report.ps1`** — wraps the PowerShell generator for unattended daily runs via Task Scheduler (always pulls *yesterday's* completed day).

### `for_client/`
A full handoff package for deploying the First In/Last Out report against a separate client's AEOS install (their own server, their own `aeosdb`): the view DDL, a dedicated low-privilege login, the PowerShell generator, and the same schema reference doc.

### `jdbc_driver/`
The Microsoft JDBC driver (`mssql-jdbc-13.4.0.jre11.jar`) and its native auth DLL, needed for Windows Integrated Authentication from Jaspersoft Studio.

## Setup

1. **Create the reporting view and login** on the target SQL Server:
   ```sql
   -- run in order
   :r create_view_FirstInLastOut.sql   -- (or aeos_jasper_reports\create_view_FirstInLastOut.sql)
   :r create_report_login.sql
   ```
   Edit the `PASSWORD` placeholder in `create_report_login.sql` before running — Mixed Mode authentication must be enabled on the server first.

2. **Generate a report** with any of the standalone generators:
   ```powershell
   .\generate_first_in_last_out.ps1 -DateFrom 2026-06-24 -DateTo 2026-06-25
   ```
   Edit the `$Server`/`$Password` defaults at the top of the script for your environment, or pass them as parameters.

   Or via Jaspersoft Studio: import the `.jrxml` files into a Studio project and compile/preview against a JDBC connection using the driver in `jdbc_driver/`. See `aeos_jasper_reports/SCHEMA_REFERENCE.md` for the full walkthrough.

## Notes

- Report output (`DailyReports/`, ad-hoc `FirstInLastOut_*.csv/.xlsx`) is git-ignored since it contains real employee data.
- Every credential in this repo is a placeholder — real passwords are set locally when running the SQL scripts and never committed.
