-- made-up but realistic loan application data for a digital lender:
-- 6 processing hubs, 14 underwriters, about 25,000 applications in 2025.
-- every application goes submitted -> assigned -> decided -> (if approved) disbursed.
-- setseed makes it repeatable: run it twice, get the same numbers.
CREATE DATABASE lending_ops;

DROP SCHEMA IF EXISTS lnd CASCADE;
CREATE SCHEMA lnd;

SELECT setseed(0.27);

-- processing hubs. speed above 1 = slower
CREATE TABLE lnd.hub (
    hub_id     int PRIMARY KEY,
    hub_name   text NOT NULL,
    daily_apps numeric NOT NULL,
    speed      numeric NOT NULL
);
INSERT INTO lnd.hub VALUES
    (1, 'Mumbai',    16, 0.9),
    (2, 'Bengaluru', 15, 0.8),
    (3, 'Delhi NCR', 14, 1.0),
    (4, 'Pune',       9, 1.1),
    (5, 'Hyderabad', 10, 1.0),
    (6, 'Kolkata',    7, 1.8);   -- the slow hub

-- underwriters. odd ids retail credit, even ids SME credit.
-- two of them are much slower than the rest
CREATE TABLE lnd.underwriter (
    underwriter_id   int PRIMARY KEY,
    underwriter_name text NOT NULL,
    team             text NOT NULL,
    hub_id           int NOT NULL REFERENCES lnd.hub,
    speed            numeric NOT NULL
);
INSERT INTO lnd.underwriter
SELECT u,
       'Underwriter ' || lpad(u::text, 2, '0'),
       CASE WHEN u % 2 = 1 THEN 'Retail Credit' ELSE 'SME Credit' END,
       ((u - 1) % 6) + 1,
       CASE u WHEN 6 THEN 2.3 WHEN 9 THEN 1.7 ELSE 0.8 + (u % 3) * 0.1 END
FROM generate_series(1, 14) AS u;

CREATE TABLE lnd.application (
    app_id            int PRIMARY KEY,
    hub_id            int NOT NULL REFERENCES lnd.hub,
    underwriter_id    int REFERENCES lnd.underwriter,
    channel           text NOT NULL,
    product           text NOT NULL,
    amount_requested  numeric(14,2) NOT NULL,
    submitted_at      timestamp NOT NULL,
    assigned_at       timestamp,
    decided_at        timestamp,
    decision          text,
    amount_approved   numeric(14,2),
    disbursed_at      timestamp
);

INSERT INTO lnd.application
WITH days AS (
    SELECT d::date AS day,
           CASE EXTRACT(isodow FROM d) WHEN 7 THEN 0.4 WHEN 6 THEN 0.7 ELSE 1.0 END
           * (1 + 0.20 * (EXTRACT(month FROM d) - 1) / 11.0)        -- volume grows through the year
           * CASE WHEN EXTRACT(month FROM d) IN (10, 11) THEN 1.2 ELSE 1 END  -- festive season
           AS day_factor
    FROM generate_series('2025-01-01'::date, '2025-12-31'::date, interval '1 day') AS d
),
slots AS (
    SELECT d.day, h.hub_id, h.speed AS hub_speed,
           floor(h.daily_apps * d.day_factor * (0.7 + random() * 0.6))::int AS n
    FROM days d CROSS JOIN lnd.hub h
),
apps AS (
    SELECT s.day, s.hub_id, s.hub_speed,
           random() AS r_ch, random() AS r_pr, random() AS r_amt, random() AS r_time,
           random() AS r_asg, random() AS r_dec, random() AS r_ok, random() AS r_dis,
           random() AS r_uw, random() AS r_appr
    FROM slots s
    CROSS JOIN LATERAL generate_series(1, GREATEST(s.n, 0)) AS g
),
typed AS (
    SELECT a.*,
           CASE WHEN a.r_ch < 0.40 THEN 'Mobile App'
                WHEN a.r_ch < 0.60 THEN 'Website'
                WHEN a.r_ch < 0.85 THEN 'Branch'
                ELSE 'Partner (DSA)' END AS channel,
           CASE WHEN a.r_pr < 0.40 THEN 'Personal Loan'
                WHEN a.r_pr < 0.65 THEN 'Credit Card'
                WHEN a.r_pr < 0.80 THEN 'Business Loan'
                WHEN a.r_pr < 0.90 THEN 'Home Loan'
                ELSE 'Two-Wheeler Loan' END AS product
    FROM apps a
),
priced AS (
    SELECT t.*,
           round((CASE t.product
               WHEN 'Personal Loan'    THEN 50000   + t.r_amt * 950000
               WHEN 'Credit Card'      THEN 25000   + t.r_amt * 275000
               WHEN 'Business Loan'    THEN 200000  + t.r_amt * 4800000
               WHEN 'Home Loan'        THEN 1000000 + t.r_amt * 14000000
               ELSE 50000 + t.r_amt * 150000 END)::numeric, -3) AS amount_requested,
           -- typical hours an underwriter needs to decide, by product
           CASE t.product
               WHEN 'Credit Card'      THEN 4
               WHEN 'Two-Wheeler Loan' THEN 6
               WHEN 'Personal Loan'    THEN 12
               WHEN 'Business Loan'    THEN 40
               ELSE 90 END AS decide_hours,
           -- chance of approval differs by channel
           CASE t.channel
               WHEN 'Mobile App'    THEN 0.68
               WHEN 'Website'       THEN 0.62
               WHEN 'Branch'        THEN 0.74
               ELSE 0.52 END AS approve_prob,
           t.day + interval '7 hours' + t.r_time * interval '15 hours' AS submitted_at
    FROM typed t
),
staffed AS (
    SELECT p.*, u.underwriter_id, u.speed AS uw_speed
    FROM priced p
    JOIN LATERAL (
        -- pick one of the hub's underwriters at random
        SELECT underwriter_id, speed FROM lnd.underwriter
        WHERE hub_id = p.hub_id
        ORDER BY underwriter_id
        OFFSET floor(p.r_uw * (SELECT COUNT(*) FROM lnd.underwriter w WHERE w.hub_id = p.hub_id))::int
        LIMIT 1
    ) u ON true
),
timed AS (
    SELECT s.*,
           -- waiting to be picked up: quick, slower at slow hubs and on weekends
           s.submitted_at + interval '1 hour' * (
               -ln(GREATEST(s.r_asg, 0.0001)) * 1.5 * s.hub_speed
               * CASE WHEN EXTRACT(isodow FROM s.submitted_at) IN (6, 7) THEN 3 ELSE 1 END
           ) AS assigned_at
    FROM staffed s
),
decided AS (
    SELECT t.*,
           t.assigned_at + interval '1 hour' * (
               t.decide_hours * (0.3 + -ln(GREATEST(t.r_dec, 0.0001)) * 0.7) * t.uw_speed
           ) AS decided_at,
           CASE WHEN t.r_appr < t.approve_prob THEN 'Approved' ELSE 'Rejected' END AS decision
    FROM timed t
)
SELECT row_number() OVER (ORDER BY submitted_at)::int,
       hub_id, underwriter_id, channel, product, amount_requested,
       submitted_at, assigned_at, decided_at, decision,
       CASE WHEN decision = 'Approved'
            THEN round((amount_requested * (0.75 + r_ok * 0.25))::numeric, -3) END,
       CASE WHEN decision = 'Approved'
            THEN decided_at + interval '1 hour' *
                 (CASE WHEN product = 'Home Loan' THEN 72 ELSE 6 END * (0.5 + r_dis * 1.5)) END
FROM decided;

-- snapshot at the end of 2025: anything after that has not happened yet
UPDATE lnd.application SET disbursed_at = NULL WHERE disbursed_at > '2025-12-31 23:59:59';
UPDATE lnd.application SET decided_at = NULL, decision = NULL, amount_approved = NULL, disbursed_at = NULL
WHERE decided_at > '2025-12-31 23:59:59';
UPDATE lnd.application SET assigned_at = NULL, underwriter_id = NULL
WHERE assigned_at > '2025-12-31 23:59:59';

CREATE INDEX ix_app_submitted ON lnd.application (submitted_at);
ANALYZE lnd.application;

SELECT COUNT(*) AS applications,
       COUNT(assigned_at) AS assigned,
       COUNT(decided_at)  AS decided,
       COUNT(disbursed_at) AS disbursed,
       MIN(submitted_at)::date AS first_day, MAX(submitted_at)::date AS last_day
FROM lnd.application;