# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("browser.global_header.user_menu_dropdown.click") do |payload|
    user = User.find_by(id: payload[:user_id])

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(user),
      target: payload[:target],
      request_url: payload[:request_url],
    }

    publish(message, schema: "github.v1.GlobalHeaderUserMenuClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
