-- Dedicated low-privilege SQL login for the First In/Last Out report.
-- Can only SELECT from dbo.vw_FirstInLastOut - nothing else in aeosdb, no other databases.
-- Run 01_create_view_FirstInLastOut.sql FIRST - this script grants on that view.
-- Requires SQL Server Mixed Mode authentication to be enabled (Server Properties > Security).

USE master;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'AeosReportReader')
BEGIN
    CREATE LOGIN [AeosReportReader] WITH PASSWORD = N'CHANGE_ME_STRONG_PASSWORD',
        CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
END
GO

USE aeosdb;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'AeosReportReader')
BEGIN
    CREATE USER [AeosReportReader] FOR LOGIN [AeosReportReader];
END
GO

-- Only grant SELECT on the one view - not db_datareader, not any table directly
GRANT SELECT ON dbo.vw_FirstInLastOut TO [AeosReportReader];
GO
