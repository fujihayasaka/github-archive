# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("spam.notification") do |payload|
    message = {
      actor_login: payload[:actor].try(:login),
      channel: payload[:channel],
      message: payload[:message],
    }

    publish(message, schema: "hamzo.v0.ChatterboxNotification", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
