# AEOS JasperReports – Schema Reference & Deployment Notes
# Based on confirmed dbo schema from your MSSQL instance

## Table Mapping (actual column names verified)

### 01_PersonnelReport.jrxml
| Data | Table.Column |
|------|-------------|
| Person | `carrier.objectid`, `carrier.lastname`, `carrier.initials`, `carrier.middlename` |
| Employee number | `carrier.personnelnr` |
| Department | `department.name` via `carrier.departmentobjectid → department.objectid` |
| Company | `carrier.company` |
| Validity | `carrier.arrivaldatetime`, `carrier.leavedatetime` |
| Blocked | `authorizationprofile.blocked` via `carrier.profileobjectid` |
| Card number | `token.badgenumber`, `token.badgenumbernumeric` |
| Card type | `identifiertype.name` via `token.identifiertype_objectid` |
| Card assignment | `tokenassignment` (withdrawn=0 = active only) |
| Access templates | `authorizationtemplate.name` via `profile_template` |
| carrier.carriertype | 1=Employee, 2=Visitor, 3=Contractor, 4=Car |

### 02_FirstInLastOutReport.jrxml
| Data | Table.Column |
|------|-------------|
| Events | `eventlog.timestamp`, `eventlog.objectid` |
| Event type | `eventtype.name`, `eventtype.eventcategory` |
| eventcategory | 1=Access Granted, 2=Access Denied, 3=Alarm, 4=Comm |
| Direction | `eventlog.intvalue` (1=IN, 2=OUT — verified 2026-08-18, see note below) |
| Person | `eventlog.carrierid → carrier` |
| Card used | `eventlog.identifierid → token` |
| Entrance | `eventlog.entranceid → entrance` |

### 03_WhoIsInReport.jrxml
| Data | Table.Column |
|------|-------------|
| Presence | `presenceindication.carrieroid`, `.direction` (1=IN, 2=OUT) |
| Zone | `presenceindication.countzoneoid → zone.name` |
| Timestamp | `presenceindication.timestamp` |
| Note | No "PresenceState" table — report uses latest record per carrier per zone |

### 04_DeviceReport.jrxml
| Data | Table.Column |
|------|-------------|
| Controller | `aepu.hostname`, `aepu.aeosversion` |
| Discovery | `aepu.lasttimediscovered` (datetime2) |
| Readers | `accesspoint.accesspointname`, `accesspoint.type` linked via hostname |
| Entrance link | `accesspoint.entranceassignmentid → entrance.name` |

### 05_CircuitReport.jrxml
| Data | Table.Column |
|------|-------------|
| Component | `networkcomponent.componentname`, `.aeostype`, `.inputid`, `.label` |
| Controller | `networkcomponent.hostname` |
| Reader link | via matching `accesspoint.hostname` |
| aeostype values | Varies by firmware; examples: DOOR_CONTACT, REX, ALARM_INPUT, LOCK, READER |

### 06_AlarmReport.jrxml
| Data | Table.Column |
|------|-------------|
| Alarm | `alarm.objectid`, `.state`, `.statechangedate`, `.priority`, `.counter` |
| alarm.state | 0=Active, 1=Acknowledged, 2=Closed |
| Source event | `alarm.eventlog_oid → eventlog` |
| Alarm point | `alarm.alarmpointentry_oid → alarmpointentry → alarmpoint.name` |
| Event type | `eventlog.eventtype → eventtype.name` |
| Access point | `eventlog.accesspointid → accesspoint.accesspointname` |
| Entrance | `eventlog.entranceid → entrance.name` |
| Cardholder | `eventlog.carrierid → carrier` |
| ACK user | `alarm.user_oid → aeosuser.username` |

---

## Alarm Types by eventtype.name (verify with your data)
```sql
-- Run this to see your actual event types that generate alarms
SELECT et.objectid, et.name, et.eventcategory, et.alarm, et.priority
FROM   eventtype et
WHERE  et.alarm = 1
ORDER  BY et.eventcategory, et.name;
```

## Direction values in eventlog.intvalue — VERIFIED 2026-08-18
Ran the query below against live aeosdb data (eventcategory=1, granted access only):
intvalue=1 accounted for ~1.03M rows, intvalue=2 for ~976K rows, intvalue=0 for ~24K
(no-direction/single-reader doors). Checked hourly distribution across the full event
history: intvalue=1 events spike 07:00-10:00 (arrival), intvalue=2 events spike
16:00-18:00 (departure) — confirms **1=IN, 2=OUT** on this installation.

`presenceindication.direction` was also checked and rejected as a data source — that
table only holds ONE row per carrier (current/latest presence state), not a history,
so it can't be used to compute a daily First-In/Last-Out. It's fine for a
"who is in the building right now" report (03_WhoIsInReport) but not for this one.

```sql
-- Re-run any time to re-verify on a fresh install
SELECT DISTINCT el.intvalue, et.name, COUNT(*) AS cnt
FROM   eventlog  el
JOIN   eventtype et ON et.objectid = el.eventtype
WHERE  et.eventcategory = 1
GROUP  BY el.intvalue, et.name
ORDER  BY el.intvalue;
```

## Confirm carrier types
```sql
SELECT carriertype, COUNT(*) AS total
FROM   carrier
WHERE  removaldate IS NULL
GROUP  BY carriertype;
-- 1=Employee, 2=Visitor, 3=Contractor, 4=Car (standard AEOS)
```

## eventlog volume check (for date range planning)
```sql
SELECT CAST(timestamp AS DATE) AS log_date, COUNT(*) AS events
FROM   eventlog
GROUP  BY CAST(timestamp AS DATE)
ORDER  BY log_date DESC;
-- If high volume, check eventlogoverflow for archived records
```

---

## Compilation Steps — Windows Authentication login (RESOLVED 2026-08-18)

Windows-Integrated auth over JDBC needs a native DLL, not just the driver jar — this
was the missing piece. Both files are now bundled in `../jdbc_driver/`:
- `mssql-jdbc-13.4.0.jre11.jar` (the driver)
- `mssql-jdbc_auth-13.4.0.x64.dll` (enables `integratedSecurity=true`, 64-bit build)

That folder was added to your **User PATH** env var so the JVM can find the DLL at
runtime — restart Jaspersoft Studio (a fresh process) for it to pick this up.

1. In Jaspersoft Studio: Repository Explorer → right-click **Data Adapters** → New Data Adapter → **Database JDBC Connection**
2. Driver: `com.microsoft.sqlserver.jdbc.SQLServerDriver`; click the JDBC Driver dropdown → **Add** → browse to `jdbc_driver\mssql-jdbc-13.4.0.jre11.jar`
3. JDBC URL:
   `jdbc:sqlserver://localhost;databaseName=aeosdb;integratedSecurity=true;encrypt=false;trustServerCertificate=true;`
4. Leave Username/Password **blank** (that's the point of integrated security)
5. Test Connection — if it fails with `This driver is not configured for integrated authentication`, PATH changes alone weren't enough for the already-running Studio process. RESOLVED 2026-08-18 by: (a) copying `mssql-jdbc_auth-13.4.0.x64.dll` directly into Studio's bundled JDK bin folder — `Jaspersoft Studio\features\jdk.win32.win32.x86_64.feature_21.0.10.7\eclipsetemurin_jdk\bin\` (same directory as `java.exe`, always on the native search path regardless of PATH env timing), and (b) fixing a typo'd `-cp` line in `Jaspersoft Studio.ini` (`Kghai` → `Kghal`) that pointed at a nonexistent path. Requires a full Studio restart (quit via Task Manager if needed) after either change.
6. Open `02_FirstInLastOutReport.jrxml` → right-click → **Compile Report** → produces `.jasper` next to it (only shows once the file is part of a real Studio Project — see "Project setup" below)
7. Preview tab → pick the data adapter above → fill `P_DATE_FROM` / `P_DATE_TO` (format `yyyy-MM-dd HH:mm:ss`, e.g. `2026-06-24 00:00:00`) → Run
8. To get it running inside AEOS itself: AEOS has its own Report Designs admin screen (backed by `dbo.reportdesign` / `dbo.reportjob`) — upload the `.jrxml` there. Exact menu path wasn't verified against your AEOS web UI; confirm under System Setup / Reports.

## Project setup in Jaspersoft Studio
The `.jrxml` files must live inside a real Studio **Project** (File → New → Project → JasperReports Project) for right-click actions like Compile Report to appear — opening a loose file via File → Open File isn't enough. Studio's project wizard doesn't always expose a Browse/location field, so the simplest path: create the project (lands under `C:\Users\Kghal\JaspersoftWorkspace\<ProjectName>\`), then copy the `.jrxml` files from this folder into that project folder, and Refresh (F5) in the Project Explorer.

## Excel / Power Query — run the SQL directly, no Jasper or Python needed
Excel can hit `aeosdb` natively via Windows auth:
1. Data tab → Get Data → From Database → From SQL Server Database
2. Server: `localhost`; Database: `aeosdb` (or leave blank)
3. Expand **Advanced options** → paste the full contents of `FirstInLastOut_standalone_query.sql` (the `DECLARE ... SELECT ...` script) into the SQL statement box
4. OK → choose **Windows** authentication when prompted (same as SSMS) → Load
5. To change the date range: Data → Queries & Connections → right-click the query → Edit → edit the two `DECLARE @P_DATE_FROM` / `@P_DATE_TO` lines → Close & Load
6. Data → Refresh All to re-pull anytime — this is manual/on-demand only, not scheduled. For hands-off recurring generation, use `generate_first_in_last_out.py` or an AEOS report job instead.

## dbo.vw_FirstInLastOut — SQL view (created 2026-08-18)
Same logic as `FirstInLastOut_standalone_query.sql`, saved as a live view in `aeosdb`.
DDL script: `create_view_FirstInLastOut.sql` (re-run anytime to update the view definition).

Usage:
```sql
SELECT * FROM dbo.vw_FirstInLastOut
WHERE activity_date BETWEEN '2026-06-24' AND '2026-06-25'
ORDER BY last_name, initials;
```

**Performance caveat (accepted tradeoff, chosen deliberately over a table-valued
function):** SQL views can't take parameters, so the date filter above is applied
*after* the view's internal GROUP BY — every query against this view scans and
aggregates the entire `eventlog` table (2M+ rows and growing) before filtering by
date. Fine at current volume; if it gets noticeably slow as history grows, the fix
is converting this to an inline table-valued function (`dbo.fn_FirstInLastOut(@from,@to)`)
so the date filter pushes down before aggregation — ask if you want that built.

This view is the simplest option to point Excel/Power Query at directly (no need to
paste the full query text — just `SELECT * FROM dbo.vw_FirstInLastOut WHERE ...`).

## PowerShell CSV/Excel generator — no Excel, Python, or Jasper needed
`generate_first_in_last_out.ps1` (in the parent `AEOS_JasperReports_v2` folder) is a
fully self-contained report generator, built when the client PC turned out to have
neither Excel nor Python installed. Uses only .NET assemblies already built into
Windows PowerShell 5.1 — zero external dependencies.

- Connects via `System.Data.SqlClient`, queries `dbo.vw_FirstInLastOut`
- Prompts for `-DateFrom`/`-DateTo` if not passed as arguments (format `YYYY-MM-DD`)
- Outputs **both** a `.csv` and a styled `.xlsx` (dark blue header row, frozen pane,
  column widths) — the `.xlsx` is hand-built via `System.IO.Compression.ZipFile` +
  raw OOXML XML (same technique `openpyxl` uses internally), so it doesn't need
  Excel, an internet-installed module, or any other tool present on the machine
- Structural validation done 2026-08-18: valid ZIP, every XML part is well-formed,
  correct `[Content_Types].xml`/relationships. Could not visually confirm rendering
  in Excel itself (GUI apps don't launch in the sandboxed dev environment used to
  build this), but the OOXML structure is spec-correct.

`for_client\generate_first_in_last_out.ps1` is the same script pointed at a
placeholder server (`CHANGE_ME_TO_CLIENT_SQL_SERVER_HOSTNAME_OR_IP` — must be edited
before use) with a distinct password from the one used on the primary server.

## dbo.AeosReportReader — dedicated low-privilege SQL login (created 2026-08-18)
Client PCs aren't always on the same Windows domain as the DB server, so Windows
Integrated Auth isn't always usable — this login exists so the PowerShell/Excel
routes work via SQL Authentication instead. Deliberately scoped to the bare minimum:
`GRANT SELECT` on `dbo.vw_FirstInLastOut` only — verified it's denied on every other
table (tested against `dbo.carrier` directly, got "SELECT permission was denied").

**Do not use `sa` for this or anything client-facing** — full server-wide admin,
wrong blast radius for a single report's read access.

DDL: `create_report_login.sql` (this server, password set via `CHANGE_ME_STRONG_PASSWORD`
placeholder — edit before running) and `for_client\02_create_report_login.sql`
(separate placeholder password for the client's server — different login, different
server, intentionally not reusing a credential across two unrelated production
systems). Mixed Mode auth
must be enabled on the target server first (`SELECT SERVERPROPERTY('IsIntegratedSecurityOnly')`
should return `0`).

## for_client\ folder — full handoff package for a separate client AEOS install
The client has their own AEOS server with its own `aeosdb`, not this one. Contents:
1. `01_create_view_FirstInLastOut.sql` — creates the view, run first
2. `02_create_report_login.sql` — creates the login + grants, run second (needs
   sysadmin/db_owner on their end; needs Mixed Mode auth enabled)
3. `generate_first_in_last_out.ps1` — edit the `$Server` placeholder before use

The `.jrxml`/`.jasper` (for the AEOS-native Jasper route) does NOT depend on the
view — it has the full query embedded and only touches base tables, so the same
compiled `.jasper` should work as-is on the client's install without changes,
*provided* their `eventlog.intvalue` convention matches (see below).

## AEOS Report Designs upload — ongoing issue, NOT YET RESOLVED (2026-08-18)
Uploading `02_FirstInLastOutReport.jasper` via AEOS's Reports → Designs screen
(`/aeos/report/DesignEdit.po`, `DesignEditSession`) produced a sequence of issues:

1. First attempts: `NullPointerException` — `jasperFile` was null server-side,
   meaning the file never actually left the browser (multipart form issue).
2. Later attempt: succeeded with no error — **confirmed via direct DB query** that
   the file IS fully and correctly stored: `SELECT DATALENGTH(template) FROM
   dbo.reportdesign WHERE objectid = 57` returned exactly **28366**, a byte-for-byte
   match with the compiled `.jasper` file size. So the upload mechanism itself does
   work, at least sometimes — the earlier NPEs were a real but inconsistent bug in
   the upload form (possibly file input state getting cleared on page re-render
   between steps; never fully root-caused).
3. **Current blocker**: the saved design (name "1", objectid 57, valid template
   blob) does not appear in the design-selection dropdown on the Reports → Reports
   → "Add report" screen, which only shows `-` (empty). This happens even though
   it's the *only* design in the system, so it's not a case of ours being filtered
   out among others - the dropdown doesn't show anything. Ruled out caching (full
   logout/login, hard refresh - no change). Root cause NOT identified - likely
   something in AEOS's own application logic when populating that dropdown
   (a validation/license/category check invisible from the database), not a schema
   or data problem. `dbo.reportdesign` only has 4 columns (`name`, `template`,
   `objectid`, `uniqueid`) - no category/type field that could explain the filtering
   from the DB side.
4. **Explicitly ruled out**: manually inserting rows into `reportdesign`/`reportjob`
   as a bypass. `dbo.objectid` is AEOS's global object-ID allocator, shared across
   every entity type in the live system (employees, cards, alarms, doors, etc via
   named "rangers" like `employeeranger`). A hand-crafted `objectid` risks colliding
   with an ID AEOS issues later for something unrelated, which could disrupt object
   creation across the whole live access-control system - not worth the risk,
   especially since we already proved a fully valid `reportdesign` row (created via
   AEOS's own official path, not a manual insert) still doesn't fix the actual
   problem, so a raw insert into `reportjob` likely wouldn't either.

**Next step**: this looks like it needs Nedap/AEOS vendor support - the diagnosable
surface from the database side is exhausted. If escalating, the byte-perfect
`DATALENGTH` match is strong evidence to hand them: the file is stored correctly,
their own report-selection UI just isn't recognizing it as usable.

## Daily scheduled generation (set up 2026-08-18)
`run_daily_report.ps1` wraps `generate_first_in_last_out.ps1` for unattended runs -
Task Scheduler has no console to answer the interactive date prompts, so this always
passes explicit dates. Deliberately generates **yesterday's** date, not "today's" -
a trigger at 00:00:00 fires the instant a new day starts, so "today" has zero data
at that moment; yesterday is the last fully-completed day.

Registration (run once):
```powershell
$scriptPath = "C:\path\to\run_daily_report.ps1"
$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
Register-ScheduledTask -TaskName "AEOS_FirstInLastOut_Daily" -Action $action -Trigger $trigger -Description "Daily First In/Last Out report generation"
```
Tested and registered on the primary server 2026-08-18 (trigger verified via
`Export-ScheduledTask`: `StartBoundary` 00:00:00, `DaysInterval` 1). Registered
without `-RunLevel Highest` since the dev session lacked admin rights - runs as
`InteractiveToken` under the current user, meaning **it only fires while that user
is logged in** (won't survive a full logout/reboot with nobody logged in). For
unattended execution after reboot with no one logged in, re-register with stored
credentials and `-RunLevel Highest` (needs admin).

## Parameter input for alarm state filter
- P_ALARM_STATE = -1 → All alarms
- P_ALARM_STATE =  0 → Active (not yet ACK'd)
- P_ALARM_STATE =  1 → Acknowledged
- P_ALARM_STATE =  2 → Closed
