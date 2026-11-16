"""Handler for core.get_current_weather (Python UDF).

The UDF is created with EXTERNAL_ACCESS_INTEGRATIONS, so outbound HTTPS is
allowed only to the hosts in the app's network rule (api.open-meteo.com).

The same function is imported by the local backend, so the logic you test
on your laptop is the logic that runs in Snowflake.
"""
import requests

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"


def get_current_weather(lat: float, lon: float) -> dict:
    response = requests.get(
        OPEN_METEO_URL,
        params={
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,wind_speed_10m",
        },
        timeout=10,
    )
    response.raise_for_status()
    return response.json().get("current", {})
