# Loan Application Turnaround Dashboard

Are we deciding on loan applications fast enough to win the customer? A credit operations dashboard for a made-up digital lender, built with PostgreSQL and Tableau Public.

**Live dashboard:** [Loan Application Turnaround on Tableau Public](https://public.tableau.com/views/LoanApplicationTurnaroundDashboard/LoanApplicationTurnaround)

![Dashboard](docs/dashboard.png)

## The question

In digital lending, an applicant who waits too long for a decision applies somewhere else. Turnaround time (TAT) is a revenue number, not only an operations number. This dashboard shows a head of credit operations how fast applications are picked up and decided, whether decisions land within target, and exactly where the delays are: which hub, which underwriter, which stage.

## Key findings (November 2025, default targets)

- **79.8% of decisions were made within target**, down 2.3 points on October.
- **Median turnaround was 11.9 hours**, 9.4% slower than October, during the festive-season peak in applications.
- **Kolkata is the slowest hub**: 2.1 hours waiting for an underwriter plus 11.7 hours of underwriting, against about 9 hours in total at Mumbai.
- **One underwriter is far behind**: Underwriter 06 decides under 40% of applications within target, against 79% across all underwriters.
- **88 applications (about ₹29 crore) were still waiting for a decision at year end**, 2 of them for more than 7 days.

## What the dashboard does

| Section | What it answers |
| --- | --- |
| KPI row | Applications, approval rate, median turnaround and amount disbursed, each against last month, plus the share decided within target |
| Weekly trend | Are we keeping pace with demand? (report month shaded) |
| Outcome donut | Where did this month's applications end up? |
| TAT vs target histogram | How far off target are decisions, with every product on one scale (100% = exactly on target) |
| Pending queue | What is still waiting for a decision, and for how long |
| Hub stages | Where the time goes: waiting for an underwriter vs being underwritten |
| Underwriter dot plot | Which underwriters miss target |

**Interactive:** the user sets a turnaround target per product (credit card, two-wheeler, personal, business and home loan) and an assignment target with sliders. Every chart recalculates, so a manager can test a faster promise and see where it would break. Clicking a hub filters the detailed charts.

## How the data was generated

The data is generated in PostgreSQL with realistic patterns built in:

- 6 processing hubs, 14 underwriters in two teams, 5 products, 4 channels, about 24,500 applications across 2025
- Volume grows through the year, is lower at weekends and peaks in October and November (festive season)
- Time to assignment follows an exponential distribution (`-ln(random())`), three times longer at weekends and slower at the slow hub
- Decision time depends on the product and on each underwriter's speed
- Approval probability depends on the channel; partner (DSA) applications are approved least
- A year-end snapshot sets anything after 31 Dec 2025 to NULL, so there is a real pending queue
- `setseed` makes the data repeatable: every run gives the same numbers

## How it was built

1. **Generate** (`01_generate_data.sql`): hubs, underwriters and applications with four timestamps each (submitted, assigned, decided, disbursed).
2. **Model** (`02_app_view.sql`): one analysis view with status, hours to assign, turnaround hours, hours to disburse and the pending amount. No targets are hard-coded in SQL; they are Tableau parameters.
3. **Check** (`03_checks.sql`): 7 data quality checks (volume, date range, stage order, approval logic, amounts, approval rate, slowest hub) plus the November numbers used to reconcile the Tableau tiles.
4. **Export** (`04_export.sql`): copies the view into a table for a complete CSV export.
5. **Tableau Public**: parameters for the report month and all six targets, LOD expressions (EXCLUDE) for the donut, month-on-month change fields, dual-axis donuts and area chart, reference bands and lines, filter and highlight actions.

## KPI definitions

| KPI | Definition |
| --- | --- |
| Applications | Applications submitted in the report month |
| Approval rate | Approved decisions / all decisions |
| Median turnaround (TAT) | Median hours from submission to credit decision |
| Within target | Share of decisions made within the target hours for that product |
| Picked up within target | Share of applications assigned to an underwriter within the assignment target |
| Amount disbursed | Approved amount sent to customers, in ₹ crore |
| TAT vs target | Decision hours / target hours (1.0 = exactly on target) |

## How to run

1. In pgAdmin, run `sql/00_create_database.sql` on the default `postgres` database.
2. Open a Query Tool on `lending_ops` and run `01`, `02` and `03` in order. All checks should say PASS.
3. Run `04_export.sql`, then export `lnd.app_export` to CSV with pgAdmin's Import/Export (header on).
4. Connect Tableau Public to the CSV.

## Tools

PostgreSQL 18, pgAdmin 4, Tableau Public

## Author

**Deepak Mishra**, Tableau Developer, Tableau Desktop Specialist

[LinkedIn](https://www.linkedin.com/in/md64) | [Portfolio](https://portfolio-deepak6411.netlify.app/) | [Tableau Public](https://public.tableau.com/app/profile/deepak.mishra6411)
