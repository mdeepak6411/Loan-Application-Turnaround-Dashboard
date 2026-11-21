-- one row per application with every time and flag tableau needs.
-- TAT (turnaround time) = hours from submission to credit decision.

DROP VIEW IF EXISTS lnd.app_analysis CASCADE;

CREATE VIEW lnd.app_analysis AS
SELECT
    a.app_id,
    h.hub_name,
    u.underwriter_name,
    u.team                                                    AS underwriter_team,
    a.channel,
    a.product,
    a.amount_requested,
    a.amount_approved,
    a.submitted_at,
    a.assigned_at,
    a.decided_at,
    a.disbursed_at,
    a.decision,
    a.submitted_at::date                                      AS submitted_date,
    date_trunc('week', a.submitted_at)::date                  AS submitted_week,
    date_trunc('month', a.submitted_at)::date                 AS submitted_month,
    EXTRACT(isodow FROM a.submitted_at)::int                  AS submitted_weekday_num,
    to_char(a.submitted_at, 'Dy')                             AS submitted_weekday,
    CASE WHEN a.disbursed_at IS NOT NULL                      THEN 'Disbursed'
         WHEN a.decision = 'Approved'                         THEN 'Approved, not disbursed'
         WHEN a.decision = 'Rejected'                         THEN 'Rejected'
         WHEN a.assigned_at IS NOT NULL                       THEN 'Under review'
         ELSE 'Waiting for assignment' END                    AS app_status,
    (a.assigned_at IS NOT NULL)::int                          AS is_assigned,
    (a.decided_at IS NOT NULL)::int                           AS is_decided,
    (a.decision = 'Approved')::int                            AS is_approved,
    (a.disbursed_at IS NOT NULL)::int                         AS is_disbursed,
    round(EXTRACT(epoch FROM (a.assigned_at - a.submitted_at)) / 3600.0, 2)  AS hours_to_assign,
    round(EXTRACT(epoch FROM (a.decided_at  - a.submitted_at)) / 3600.0, 2)  AS tat_hours,
    round(EXTRACT(epoch FROM (a.disbursed_at - a.decided_at)) / 3600.0, 2)   AS hours_to_disburse,
    CASE WHEN a.disbursed_at IS NOT NULL THEN a.amount_approved ELSE 0 END    AS amount_disbursed,
    -- applications still waiting for a decision at the snapshot
    CASE WHEN a.decided_at IS NULL
         THEN round(EXTRACT(epoch FROM (timestamp '2025-12-31 23:59:59' - a.submitted_at)) / 86400.0, 1)
    END                                                       AS days_pending,
    CASE WHEN a.decided_at IS NULL THEN a.amount_requested ELSE 0 END        AS amount_pending
FROM lnd.application a
JOIN lnd.hub h USING (hub_id)
LEFT JOIN lnd.underwriter u USING (underwriter_id);