USE ROLE SYSADMIN;
USE DATABASE PIPELINE_DB;
USE SCHEMA RAW;
USE WAREHOUSE PIPELINE_WH;

CREATE OR REPLACE STAGE PIPELINE_S3_STAGE
  URL = 's3://<BUCKET_NAME>/raw/'
  STORAGE_INTEGRATION = PIPELINE_S3_INTEGRATION
  FILE_FORMAT = CSV_FORMAT;

-- Snowpipe landing layer: every file becomes a row in STAGING_EVENTS.
-- The file name identifies which downstream target should receive the row.
CREATE OR REPLACE PIPE PIPELINE_PIPE
  AUTO_INGEST = TRUE
AS
COPY INTO STAGING_EVENTS (source_file, record_type, payload)
FROM (
  SELECT
    METADATA$FILENAME,
    CASE
      WHEN LOWER(METADATA$FILENAME) LIKE '%customers%' THEN 'CUSTOMER'
      WHEN LOWER(METADATA$FILENAME) LIKE '%orders%' THEN 'ORDER'
      ELSE 'UNKNOWN'
    END,
    ARRAY_CONSTRUCT($1, $2, $3, $4, $5)
  FROM @PIPELINE_S3_STAGE
)
PATTERN = '.*[.]csv';

-- S3 event notifications can be configured for AUTO_INGEST.
-- Until notifications are configured, manually scan an existing prefix:
-- ALTER PIPE PIPELINE_PIPE REFRESH;
