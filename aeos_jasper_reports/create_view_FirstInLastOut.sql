USE aeosdb;
GO

CREATE OR ALTER VIEW dbo.vw_FirstInLastOut AS
SELECT
    c.objectid                          AS carrier_id,
    LTRIM(RTRIM(c.lastname))            AS last_name,
    LTRIM(RTRIM(c.initials))            AS initials,
    c.personnelnr                       AS file_number,
    dep.name                            AS department,
    badges.card_number                  AS card_number,
    CAST(el.timestamp AS DATE)          AS activity_date,
    MIN(CASE WHEN el.intvalue = 1 THEN el.timestamp END) AS first_in,
    MAX(CASE WHEN el.intvalue = 2 THEN el.timestamp END) AS last_out,
    DATEDIFF(MINUTE,
        MIN(CASE WHEN el.intvalue = 1 THEN el.timestamp END),
        MAX(CASE WHEN el.intvalue = 2 THEN el.timestamp END)) AS duration_minutes,
    COUNT(el.objectid)                  AS event_count
FROM        dbo.eventlog      el
JOIN        dbo.eventtype     et  ON et.objectid  = el.eventtype
                                 AND et.eventcategory = 1        -- access granted only
JOIN        dbo.carrier       c   ON c.objectid   = el.carrierid
                                 AND c.carriertype = 1           -- employees only
                                 AND c.removaldate IS NULL
LEFT JOIN   dbo.department    dep ON dep.objectid  = c.departmentobjectid
OUTER APPLY (
    SELECT STRING_AGG(x.badgenumber, ', ') AS card_number
    FROM (
        SELECT DISTINCT tk.badgenumber
        FROM   dbo.tokenassignment ta
        JOIN   dbo.token           tk ON tk.objectid = ta.identifierobjectid
        WHERE  ta.carrierobjectid = c.objectid AND ta.withdrawn = 0
    ) x
) badges
GROUP BY
    c.objectid, c.lastname, c.initials, c.personnelnr,
    dep.name, badges.card_number, CAST(el.timestamp AS DATE);
GO
