-- =====================================================================
-- Checks to run after `snow app run`, as the consumer would see the app.
-- Docs: https://docs.snowflake.com/en/developer-guide/native-apps/installing-testing-application
-- =====================================================================

-- 1. Is the external access spec pending, approved or declined?
SHOW SPECIFICATIONS IN APPLICATION weather_app;

-- 2. Approve it (needs MANAGE APPLICATION SPECIFICATIONS on the account).
--    Take SEQUENCE_NUMBER from the SHOW output above.
ALTER APPLICATION weather_app APPROVE SPECIFICATION open_meteo_spec SEQUENCE_NUMBER = 1;

-- 3. What did the lifecycle callback record?
--    (app_state isn't granted to app_public, so use session debug mode)
SELECT SYSTEM$BEGIN_DEBUG_APPLICATION('weather_app');
SELECT * FROM weather_app.app_state.spec_events ORDER BY received_at DESC;
SELECT SYSTEM$END_DEBUG_APPLICATION();

-- 4. Call the app the way the UI does
CALL weather_app.core.log_weather('Pune', 18.52, 73.86);
CALL weather_app.core.weather_summary();

-- 5. Fresh-install test: an upgrade in place can hide setup-script bugs.
--    From the terminal:
--      snow app teardown
--      snow app run
