DECLARE @P_DATE_FROM DATETIME = '2026-06-24 00:00:00';
DECLARE @P_DATE_TO   DATETIME = '2026-06-25 23:59:59';
DECLARE @P_NAME_FILTER VARCHAR(50) = '%';
DECLARE @P_CARD_NUMBER VARCHAR(50) = '%';
DECLARE @P_FILE_NUMBER VARCHAR(50) = '%';

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
FROM        eventlog         el
JOIN        eventtype        et  ON et.objectid  = el.eventtype
                                AND et.eventcategory = 1
JOIN        carrier          c   ON c.objectid   = el.carrierid
                                AND c.carriertype = 1
                                AND c.removaldate IS NULL
LEFT JOIN   department       dep ON dep.objectid  = c.departmentobjectid
OUTER APPLY (
    SELECT STRING_AGG(x.badgenumber, ', ') AS card_number
    FROM (
        SELECT DISTINCT tk.badgenumber
        FROM   tokenassignment ta
        JOIN   token           tk ON tk.objectid = ta.identifierobjectid
        WHERE  ta.carrierobjectid = c.objectid AND ta.withdrawn = 0
    ) x
) badges
WHERE
    el.timestamp >= @P_DATE_FROM
    AND el.timestamp <= @P_DATE_TO
    AND (LTRIM(RTRIM(c.lastname)) + ' ' + LTRIM(RTRIM(c.initials))) LIKE @P_NAME_FILTER
    AND (badges.card_number LIKE @P_CARD_NUMBER OR badges.card_number IS NULL)
    AND (c.personnelnr      LIKE @P_FILE_NUMBER OR c.personnelnr      IS NULL)
GROUP BY
    c.objectid, c.lastname, c.initials, c.personnelnr,
    dep.name, badges.card_number, CAST(el.timestamp AS DATE)
ORDER BY c.lastname, c.initials, CAST(el.timestamp AS DATE);
