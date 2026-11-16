"""Streamlit UI for the weather Native App.

Run locally:   streamlit run src/streamlit/streamlit_app.py
In Snowflake:  deployed by `snow app run` as core.ui
"""
import streamlit as st

from backend import get_backend

CITIES = {
    "Pune": (18.52, 73.86),
    "Bengaluru": (12.97, 77.59),
    "London": (51.51, -0.13),
    "New York": (40.71, -74.01),
}

st.title("Weather Native App")

backend = get_backend(st.session_state)
st.caption(f"Running in **{backend.mode}** mode")

# --- 1. External access must be approved before any API call -------------
status = backend.spec_status()
if status != "APPROVED":
    st.warning(
        f"External access to api.open-meteo.com is **{status}**. "
        "Approve the app specification to start fetching weather."
    )
    if st.button("Review external access request"):
        backend.request_spec_review()
    st.stop()

# --- 2. Fetch and log ----------------------------------------------------
city = st.selectbox("City", list(CITIES))
if st.button("Fetch current weather"):
    lat, lon = CITIES[city]
    try:
        st.success(backend.log_weather(city, lat, lon))
    except Exception as exc:  # surface the real error while developing
        st.error(f"Call failed: {exc}")

# --- 3. Summary (computed in the warehouse via Snowpark) -----------------
st.subheader("Readings so far")
st.dataframe(backend.summary(), use_container_width=True)
