-- 1) Drop (if exists) and create a fresh table
DROP TABLE IF EXISTS my_logs;

CREATE TABLE my_logs (
  branch   TEXT,
  commit   TEXT,
  filename TEXT,
  snapshot TIMESTAMP,
  stage    TEXT,
  status   INT,
  sysname  TEXT,
  text     TEXT
);

-- 2) Insert rows from a JSON file on the server’s filesystem
WITH raw AS (
  -- Read the entire file into a JSON value (must be superuser or have the role's file-access privileges)
  SELECT pg_read_file('/Users/jbrazeal/Downloads/data.out')::json AS doc
)
INSERT INTO my_logs
SELECT 
  elem ->> 'branch'   AS branch,
  elem ->> 'commit'   AS commit,
  elem ->> 'filename' AS filename,
  (elem ->> 'snapshot')::timestamp AS snapshot,
  elem ->> 'stage'    AS stage,
  (elem ->> 'status')::int        AS status,
  elem ->> 'sysname'  AS sysname,
  elem ->> 'text'     AS text
FROM raw,
     json_array_elements(doc) AS elem;

-- 3) Optionally check
SELECT * FROM my_logs;
