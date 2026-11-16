-- =====================================================================
-- Setup script: runs on every install AND every upgrade.
-- Write every statement so it is safe to run again.
-- Docs: https://docs.snowflake.com/en/developer-guide/native-apps/creating-setup-script
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Application role: what the consumer's roles are allowed to use
-- ---------------------------------------------------------------------
CREATE APPLICATION ROLE IF NOT EXISTS app_public;

-- ---------------------------------------------------------------------
-- 2. Schemas
--    core      = VERSIONED: code (UI, procedures, functions).
--                Recreated with each version, so upgrades swap code cleanly.
--    app_state = normal schema: data and settings.
--                Survives upgrades. Always use IF NOT EXISTS here.
-- ---------------------------------------------------------------------
CREATE OR ALTER VERSIONED SCHEMA core;
GRANT USAGE ON SCHEMA core TO APPLICATION ROLE app_public;

CREATE SCHEMA IF NOT EXISTS app_state;

CREATE TABLE IF NOT EXISTS app_state.weather_log (
    city        STRING,
    observed_at TIMESTAMP_LTZ,
    payload     VARIANT
);

CREATE TABLE IF NOT EXISTS app_state.spec_events (
    spec_name   STRING,
    status      STRING,
    payload     STRING,
    received_at TIMESTAMP_LTZ
);

-- ---------------------------------------------------------------------
-- 3. External access (manifest v2 + app specification)
--    The app creates the network rule and EAI itself.
--    The EAI is NOT usable until the consumer approves the app spec.
--    HOST_PORTS in the spec must match the network rule VALUE_LIST exactly.
--    Docs: https://docs.snowflake.com/en/developer-guide/native-apps/requesting-app-specs-eai
-- ---------------------------------------------------------------------
CREATE OR REPLACE NETWORK RULE app_state.open_meteo_rule
  TYPE = HOST_PORT
  MODE = EGRESS
  VALUE_LIST = ('api.open-meteo.com');

-- EAIs are account-level objects in the consumer account: prefix the name
-- so it can't collide with the consumer's own integrations.
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION weather_app_open_meteo_eai
  ALLOWED_NETWORK_RULES = (app_state.open_meteo_rule)
  ENABLED = TRUE;

ALTER APPLICATION SET SPECIFICATION open_meteo_spec
  TYPE = EXTERNAL_ACCESS
  LABEL = 'Open-Meteo weather API'
  DESCRIPTION = 'Lets the app read current weather from api.open-meteo.com'
  HOST_PORTS = ('api.open-meteo.com');

-- ---------------------------------------------------------------------
-- 4. Lifecycle callback for app spec approve / decline
--    Signature: (name, status, payload) as strings.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE core.on_spec_update(name STRING, status STRING, payload STRING)
  RETURNS STRING
  LANGUAGE SQL
  EXECUTE AS OWNER
AS
$$
BEGIN
  INSERT INTO app_state.spec_events (spec_name, status, payload, received_at)
    SELECT :name, :status, :payload, CURRENT_TIMESTAMP();
  RETURN 'recorded ' || :name || ' = ' || :status;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Python UDF that calls the external API through the EAI
--    Handler file is staged at /python/weather.py
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.get_current_weather(lat FLOAT, lon FLOAT)
  RETURNS VARIANT
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('requests')
  IMPORTS = ('/python/weather.py')
  EXTERNAL_ACCESS_INTEGRATIONS = (weather_app_open_meteo_eai)
  HANDLER = 'weather.get_current_weather';

-- ---------------------------------------------------------------------
-- 6. SQL stored procedure: set-based work, bound variables (no string-built SQL)
--    Owner's rights is the default, and the "owner" here is the app itself.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE core.log_weather(city STRING, lat FLOAT, lon FLOAT)
  RETURNS STRING
  LANGUAGE SQL
  EXECUTE AS OWNER
AS
$$
BEGIN
  INSERT INTO app_state.weather_log (city, observed_at, payload)
    SELECT :city, CURRENT_TIMESTAMP(), core.get_current_weather(:lat, :lon);
  RETURN 'Logged weather for ' || :city;
END;
$$;
GRANT USAGE ON PROCEDURE core.log_weather(STRING, FLOAT, FLOAT) TO APPLICATION ROLE app_public;

-- ---------------------------------------------------------------------
-- 7. Python stored procedure using Snowpark (lazy DataFrame, runs as one query)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE core.weather_summary()
  RETURNS TABLE (city STRING, readings NUMBER, avg_temp_c FLOAT, last_seen TIMESTAMP_LTZ)
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  IMPORTS = ('/python/summary.py')
  HANDLER = 'summary.run'
  EXECUTE AS OWNER;
GRANT USAGE ON PROCEDURE core.weather_summary() TO APPLICATION ROLE app_public;

-- ---------------------------------------------------------------------
-- 8. Streamlit UI (warehouse runtime)
-- ---------------------------------------------------------------------
CREATE OR REPLACE STREAMLIT core.ui
  FROM '/streamlit'
  MAIN_FILE = 'streamlit_app.py';
GRANT USAGE ON STREAMLIT core.ui TO APPLICATION ROLE app_public;
