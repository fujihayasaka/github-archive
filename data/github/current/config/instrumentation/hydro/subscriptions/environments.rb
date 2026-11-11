# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("environment.deleted") do |payload|
    deleted_env = payload[:deleted_environment]
    deleted_env_next_global_id = GitHub.enterprise? ? deleted_env&.global_relay_id : deleted_env&.next_global_id

    message = {
      actor: serializer.user(payload[:actor]),
      deleted_environment: serializer.environment(deleted_env, overrides: { next_global_id: deleted_env_next_global_id }),
    }
    publish(message, schema: "github.v1.EnvironmentDeleted", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
