# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to Code Security.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("repository_code_security.enable") do |payload|
    message = {
      repository_id: payload[:repository_id],
      feature_enabled: true
    }

    # Using the repo id as partition key should ensure that events for a given repo are processed in order
    partition_key = payload[:repository_id]

    Hydro::PublishRetrier.publish(message,
      partition_key: partition_key,
      schema: "github.code_security.v1.CodeSecurityFeatureToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end

  subscribe("repository_code_security.disable") do |payload|
    message = {
      repository_id: payload[:repository_id],
      feature_enabled: false
    }

    # Using the repo id as partition key should ensure that events for a given repo are processed in order
    partition_key = payload[:repository_id]

    Hydro::PublishRetrier.publish(message,
      partition_key: partition_key,
      schema: "github.code_security.v1.CodeSecurityFeatureToggled",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end
end
