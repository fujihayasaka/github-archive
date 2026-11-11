# typed: true
# frozen_string_literal: true

# Hydro event subscriptions related to SSO redirect.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("sso_redirect.enable") do |payload|
    message = {
      business: serializer.business(payload[:business]),
      actor: serializer.user(payload[:actor]),
    }
    publish(message, schema: "github.sso_redirect.v0.Enable")
  end

  subscribe("sso_redirect.disable") do |payload|
    message = {
      business: serializer.business(payload[:business]),
      actor: serializer.user(payload[:actor]),
    }
    publish(message, schema: "github.sso_redirect.v0.Disable")
  end

  subscribe("sso_page.view") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(payload[:user]),
      org: serializer.organization(payload[:org]),
      business: serializer.business(payload[:business]),
    }

    publish(message, schema: "github.v1.SsoPageView", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
