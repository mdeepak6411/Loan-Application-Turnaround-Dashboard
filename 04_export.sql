-- copy the view into a table so pgAdmin Import/Export writes all of it
DROP TABLE IF EXISTS lnd.app_export;
CREATE TABLE lnd.app_export AS SELECT * FROM lnd.app_analysis ORDER BY app_id;
SELECT COUNT(*) FROM lnd.app_export;
