# typed: strict
# frozen_string_literal: true

module Workbench
  # Event names correspond to hydro schemas
  module Events
    # catchall event, corresponds to spark_workbench.v0.Event
    GENERIC = "workbench.event"
    # restricted catchall event, corresponds to spark_workbench.v0.RestrictedEvent
    RESTRICTED_GENERIC = "workbench.restricted_event"
    # catchall for telemetry emitted from codespaces, corresponds to spark_workbench.v0.SparkCodespaceEvent
    CODESPACE = "workbench.codespace_event"
    # restricted catchall for telemetry emitted from codespaces, corresponds to spark_workbench.v0.RestrictedSparkCodespaceEvent
    RESTRICTED_CODESPACE = "workbench.restricted_codespace_event"

    # Telemetry events
    DEV_COMPUTE_DURATION = "workbench.dev_compute_duration"
    SPARK_USAGE_BLOCKED = "workbench.spark_usage_blocked"
    AT_CODESPACE_COMPUTE_LIMIT = "at_codespace_compute_limit"
    AT_CODESPACE_SESSION_LIMIT = "at_codespace_session_limit"
  end
end
