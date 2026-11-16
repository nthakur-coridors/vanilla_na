# Snowflake Native App template: Streamlit + External Access

A small Snowflake Native App that goes with the blog post
*Building a Snowflake Native App: Real-World Challenges and Lessons from Experience*.

It shows the pieces most real apps need, kept as small as possible:

| Piece | Where |
|---|---|
| Streamlit UI (warehouse runtime) | `src/streamlit/streamlit_app.py` |
| Local-first development (no credits) | `src/streamlit/backend.py` |
| Manifest v2 + automated privileges | `app/manifest.yml` |
| External Access Integration via app specification | `app/setup_script.sql` (section 3) |
| Lifecycle callback for spec approval | `app/setup_script.sql` (section 4) |
| Python UDF calling an external API | `src/python/weather.py` |
| SQL stored procedure with bound variables | `app/setup_script.sql` (section 6) |
| Python stored procedure with Snowpark | `src/python/summary.py` |
| Versioned schema for code, normal schema for state | `app/setup_script.sql` (section 2) |
| Manifest v1 + references alternative | `docs/alternative-manifest-v1-references.md` |

The external API is [Open-Meteo](https://open-meteo.com/), which needs no API key.

## Project layout

```
.
├── snowflake.yml                 # Snowflake CLI project definition
├── app/
│   ├── manifest.yml              # manifest v2, privileges, callbacks
│   ├── setup_script.sql          # runs on install and upgrade
│   └── README.md                 # shown to the consumer
├── src/
│   ├── streamlit/
│   │   ├── streamlit_app.py      # UI
│   │   ├── backend.py            # local vs Snowflake backend
│   │   └── environment.yml       # Streamlit packages in Snowflake
│   └── python/
│       ├── weather.py            # UDF handler (external call)
│       └── summary.py            # Snowpark procedure handler
├── scripts/
│   └── consumer_checks.sql       # test the app as a consumer
├── docs/
│   └── alternative-manifest-v1-references.md
└── requirements-local.txt
```

## 1. Run the UI locally first

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-local.txt
streamlit run src/streamlit/streamlit_app.py
```

Locally the app runs in **local** mode: it calls `weather.py` directly and
keeps the log in memory. Same UI, no Snowflake credits.

## 2. Deploy to Snowflake

You need [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)
with a connection configured, and a role that can create application packages.

```bash
snow app run          # create the package, upload files, install the app (dev mode)
snow app open         # open it in Snowsight
```

Then approve the external access request (in the app, in Snowsight, or with SQL):

```sql
SHOW SPECIFICATIONS IN APPLICATION weather_app;
ALTER APPLICATION weather_app APPROVE SPECIFICATION open_meteo_spec SEQUENCE_NUMBER = 1;
```

More checks: `scripts/consumer_checks.sql`.

## 3. Everyday commands

```bash
snow app run                  # deploy changes and upgrade the dev app
snow app deploy               # sync files to the stage + validate only
snow app validate             # validate the setup script
snow app events               # read logs from the event table
snow app teardown             # drop app + package (use before a fresh-install test)
snow app version create v1    # cut a version
snow app publish --version v1 --patch 0 --channel ALPHA
```

## Things to know

- `HOST_PORTS` in the app spec must match the network rule `VALUE_LIST` exactly
  (`api.open-meteo.com` and `api.open-meteo.com:443` are not treated as the same).
- The EAI exists after install but can't be used until the consumer approves the spec.
  The UI checks the status first and stops with a message instead of failing.
- The manifest `privileges` list can't change in a patch when using manifest v2.
- Keep data in `app_state` (normal schema). Anything in `core` (versioned) is replaced on upgrade.

## Status

This template follows the Snowflake documentation as of November 2026. The
local mode has been smoke-tested (UI + backend). Run `snow app run` and the
checks in `scripts/consumer_checks.sql` in your own account before using it
as a base for production work.
