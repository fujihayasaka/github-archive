# typed: strict
# frozen_string_literal: true

# These are GlobalInstrumenter subscriptions that emit Hydro events related to Spark
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe(::Workbench::Events::GENERIC) do |payload|
    payload = T.let(payload, ::Workbench::TelemetryInstrumenter::Payload)

    publish(payload.as_hydro_message, schema: "spark_workbench.v0.Event")
  end

  subscribe(::Workbench::Events::RESTRICTED_GENERIC) do |payload|
    payload = T.let(payload, ::Workbench::TelemetryInstrumenter::Payload)

    publish(payload.as_hydro_message, schema: "spark_workbench.v0.RestrictedEvent")
  end

  subscribe(::Workbench::Events::CODESPACE) do |payload|
    payload = T.let(payload, ::Workbench::TelemetryInstrumenter::Payload)

    publish(payload.as_hydro_message, schema: "spark_workbench.v0.SparkCodespaceEvent")
  end

  subscribe(::Workbench::Events::RESTRICTED_CODESPACE) do |payload|
    payload = T.let(payload, ::Workbench::TelemetryInstrumenter::Payload)

    # This message is currently shared by both topics. It's up
    # to the event producer to ensure the event_data is valid for the event type.
    publish(payload.as_hydro_message, schema: "spark_workbench.v0.RestrictedSparkCodespaceEvent")
  end
end

# Event: a member is removed from the org
GlobalInstrumenter.subscribe("org.remove_member") do |_name, _start, _ending, _transaction_id, payload|
  next if GitHub.enterprise?

  user, organization = payload.values_at(:user, :org)
  user_id         = user&.id
  organization_id = organization&.id
  next unless user_id && organization_id

  SparkRuntime::FixSparkVisibilityJob.perform_later(user_id, organization_id)
end
