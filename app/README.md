# Weather Native App (template)

This app reads current weather from the Open-Meteo API and keeps a small log inside the app.

## After installing

1. Open the app and go to the **Security** / **Permissions** area in Snowsight, or use the button in the app.
2. Review and approve the app specification **Open-Meteo weather API**. It allows outbound calls to `api.open-meteo.com` only.
3. Open the Streamlit UI, pick a city and fetch the weather.

Until the specification is approved, the app shows a "waiting for approval" message and makes no external calls.

## Approve with SQL instead

```sql
SHOW SPECIFICATIONS IN APPLICATION weather_app;
ALTER APPLICATION weather_app APPROVE SPECIFICATION open_meteo_spec SEQUENCE_NUMBER = 1;
```

The role running this needs the `MANAGE APPLICATION SPECIFICATIONS` privilege on the account.
