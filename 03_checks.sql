-- run after 01 and 02, every row should say PASS

SELECT 'about 25,000 applications generated' AS test,
       CASE WHEN COUNT(*) BETWEEN 20000 AND 32000 THEN 'PASS' ELSE 'FAIL' END AS result,
       COUNT(*)::text AS detail
FROM lnd.app_analysis

UNION ALL
SELECT 'all applications submitted in 2025',
       CASE WHEN MIN(submitted_at) >= '2025-01-01' AND MAX(submitted_at) < '2026-01-01' THEN 'PASS' ELSE 'FAIL' END,
       MIN(submitted_at)::date::text || ' to ' || MAX(submitted_at)::date::text
FROM lnd.app_analysis

UNION ALL
SELECT 'stages always in order',
       CASE WHEN COUNT(*) FILTER (WHERE assigned_at < submitted_at
                                     OR decided_at < assigned_at
                                     OR disbursed_at < decided_at) = 0
            THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*) FILTER (WHERE assigned_at < submitted_at
                           OR decided_at < assigned_at
                           OR disbursed_at < decided_at)::text || ' rows'
FROM lnd.app_analysis

UNION ALL
SELECT 'only approved applications are disbursed',
       CASE WHEN COUNT(*) FILTER (WHERE is_disbursed = 1 AND decision <> 'Approved') = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*) FILTER (WHERE is_disbursed = 1 AND decision <> 'Approved')::text || ' rows'
FROM lnd.app_analysis

UNION ALL
SELECT 'approved amount never above requested',
       CASE WHEN COUNT(*) FILTER (WHERE amount_approved > amount_requested) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*) FILTER (WHERE amount_approved > amount_requested)::text || ' rows'
FROM lnd.app_analysis

UNION ALL
SELECT 'approval rate realistic (55 to 75%)',
       CASE WHEN SUM(is_approved)::numeric / NULLIF(SUM(is_decided), 0) BETWEEN 0.55 AND 0.75
            THEN 'PASS' ELSE 'FAIL' END,
       to_char(100.0 * SUM(is_approved) / NULLIF(SUM(is_decided), 0), 'FM990.0') || '%'
FROM lnd.app_analysis

UNION ALL
SELECT 'Kolkata is the slowest hub',
       CASE WHEN (SELECT hub_name FROM lnd.app_analysis WHERE is_decided = 1
                  GROUP BY hub_name
                  ORDER BY percentile_cont(0.5) WITHIN GROUP (ORDER BY tat_hours) DESC
                  LIMIT 1) = 'Kolkata' THEN 'PASS' ELSE 'FAIL' END,
       'slowest by median TAT';

-- numbers to check the tableau tiles against: November 2025.
-- the targets below are the default values of the tableau parameters (in hours).
SELECT COUNT(*)                                                         AS applications,
       round(100.0 * SUM(is_approved) / NULLIF(SUM(is_decided), 0), 1)  AS approval_pct,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY tat_hours)::numeric, 1) AS median_tat_h,
       round(100.0 * COUNT(*) FILTER (WHERE tat_hours <= CASE product
                                                     WHEN 'Credit Card'      THEN 8
                                                     WHEN 'Two-Wheeler Loan' THEN 12
                                                     WHEN 'Personal Loan'    THEN 24
                                                     WHEN 'Business Loan'    THEN 72
                                                     ELSE 120 END) / NULLIF(SUM(is_decided), 0), 1) AS within_sla_pct,
       round(100.0 * COUNT(*) FILTER (WHERE hours_to_assign <= 2) / NULLIF(SUM(is_assigned), 0), 1) AS assigned_within_120min_pct,
       round(SUM(amount_disbursed) / 10000000.0, 2)                     AS disbursed_crore
FROM lnd.app_analysis
WHERE submitted_month = '2025-11-01';