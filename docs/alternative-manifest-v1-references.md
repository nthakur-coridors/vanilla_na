# Alternative: external access with manifest v1 + references

The template uses manifest v2 and an app specification. If you stay on
manifest v1, the consumer creates (or Snowsight creates for them) the EAI
and binds it to a **reference** you declare.

Full Snowflake example: https://docs.snowflake.com/en/developer-guide/native-apps/requesting-example-oauth

## manifest.yml

```yaml
manifest_version: 1
artifacts:
  setup_script: setup_script.sql
  readme: README.md
  default_streamlit: core.ui

references:
  - weather_eai:
      label: "Open-Meteo external access"
      description: "Needed to call api.open-meteo.com"
      privileges:
        - USAGE
      object_type: EXTERNAL ACCESS INTEGRATION
      register_callback: core.register_reference
      configuration_callback: core.get_config_for_ref
      required_at_setup: true
```

## setup_script.sql (callbacks)

```sql
-- Stores the consumer's binding
CREATE OR REPLACE PROCEDURE core.register_reference(ref_name STRING, operation STRING, ref_or_alias STRING)
  RETURNS STRING
  LANGUAGE SQL
AS
$$
BEGIN
  CASE (operation)
    WHEN 'ADD'    THEN SELECT SYSTEM$SET_REFERENCE(:ref_name, :ref_or_alias);
    WHEN 'REMOVE' THEN SELECT SYSTEM$REMOVE_REFERENCE(:ref_name, :ref_or_alias);
    WHEN 'CLEAR'  THEN SELECT SYSTEM$REMOVE_ALL_REFERENCES(:ref_name);
    ELSE RETURN 'unknown operation: ' || operation;
  END CASE;
  RETURN NULL;
END;
$$;
GRANT USAGE ON PROCEDURE core.register_reference(STRING, STRING, STRING) TO APPLICATION ROLE app_public;

-- Tells Snowsight which host ports the EAI needs
CREATE OR REPLACE PROCEDURE core.get_config_for_ref(ref_name STRING)
  RETURNS STRING
  LANGUAGE SQL
AS
$$
BEGIN
  CASE (UPPER(ref_name))
    WHEN 'WEATHER_EAI' THEN
      RETURN OBJECT_CONSTRUCT(
        'type', 'CONFIGURATION',
        'payload', OBJECT_CONSTRUCT(
          'host_ports', ARRAY_CONSTRUCT('api.open-meteo.com'),
          'allowed_secrets', 'NONE')
      )::STRING;
  END CASE;
  RETURN '';
END;
$$;
GRANT USAGE ON PROCEDURE core.get_config_for_ref(STRING) TO APPLICATION ROLE app_public;
```

The UDF then uses the reference instead of a named EAI:

```sql
EXTERNAL_ACCESS_INTEGRATIONS = (reference('weather_eai'))
```

Because the reference is bound after install, functions that use it are
usually created from the register callback (or a procedure the UI calls)
once the binding exists, not directly in the setup script.
