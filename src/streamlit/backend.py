"""One interface, two backends.

- SnowflakeBackend: used when the app runs inside Snowflake (Native App).
- LocalBackend:     used on your laptop, so you can build the UI without
                    burning credits. It calls the same weather.py handler
                    directly and keeps the log in memory.

The UI (streamlit_app.py) only talks to this interface, so moving from
local to Snowflake doesn't change the UI code.
"""
from __future__ import annotations

import datetime as dt
import os
import sys

import pandas as pd

SPEC_NAME = "OPEN_METEO_SPEC"


def get_backend(state: dict):
    try:
        from snowflake.snowpark.context import get_active_session

        return SnowflakeBackend(get_active_session())
    except Exception:
        return LocalBackend(state)


class SnowflakeBackend:
    mode = "snowflake"

    def __init__(self, session):
        self.session = session

    def spec_status(self) -> str:
        import snowflake.permissions as permissions

        for spec in permissions.get_application_specifications():
            if str(spec.get("name", "")).upper() == SPEC_NAME:
                return str(spec.get("status", "UNKNOWN")).upper()
        return "NOT_FOUND"

    def request_spec_review(self) -> None:
        import snowflake.permissions as permissions

        permissions.request_application_specification_review([SPEC_NAME])

    def log_weather(self, city: str, lat: float, lon: float) -> str:
        # session.call binds the arguments: no string-built SQL
        return self.session.call("core.log_weather", city, lat, lon)

    def summary(self) -> pd.DataFrame:
        return self.session.sql("CALL core.weather_summary()").to_pandas()


class LocalBackend:
    mode = "local"

    def __init__(self, state: dict):
        # Reuse the exact handler that the UDF runs in Snowflake
        here = os.path.dirname(os.path.abspath(__file__))
        sys.path.insert(0, os.path.join(here, "..", "python"))
        from weather import get_current_weather

        self._fetch = get_current_weather
        self._log = state.setdefault("weather_log", [])

    def spec_status(self) -> str:
        return "APPROVED"  # no app specs locally

    def request_spec_review(self) -> None:
        pass

    def log_weather(self, city: str, lat: float, lon: float) -> str:
        payload = self._fetch(lat, lon)
        self._log.append(
            {"city": city, "observed_at": dt.datetime.now(), "payload": payload}
        )
        return f"Logged weather for {city}"

    def summary(self) -> pd.DataFrame:
        columns = ["CITY", "READINGS", "AVG_TEMP_C", "LAST_SEEN"]
        if not self._log:
            return pd.DataFrame(columns=columns)
        df = pd.DataFrame(self._log)
        df["temp_c"] = df["payload"].apply(lambda p: p.get("temperature_2m"))
        out = (
            df.groupby("city")
            .agg(
                READINGS=("city", "size"),
                AVG_TEMP_C=("temp_c", "mean"),
                LAST_SEEN=("observed_at", "max"),
            )
            .reset_index()
            .rename(columns={"city": "CITY"})
            .sort_values("LAST_SEEN", ascending=False)
        )
        return out[columns]
