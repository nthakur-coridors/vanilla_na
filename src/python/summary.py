"""Handler for core.weather_summary (Python stored procedure, Snowpark).

Every call below only builds a query plan (lazy evaluation). Snowflake runs
it as one SQL query when the caller consumes the returned DataFrame, so the
raw log never leaves the warehouse.
"""
from snowflake.snowpark import Session
from snowflake.snowpark import functions as F


def run(session: Session):
    log = session.table("app_state.weather_log")

    return (
        log.with_column("temp_c", F.col("payload")["temperature_2m"].cast("float"))
        .group_by("city")
        .agg(
            F.count(F.lit(1)).alias("readings"),
            F.avg("temp_c").alias("avg_temp_c"),
            F.max("observed_at").alias("last_seen"),
        )
        .select("city", "readings", "avg_temp_c", "last_seen")
        .sort(F.col("last_seen").desc())
    )
