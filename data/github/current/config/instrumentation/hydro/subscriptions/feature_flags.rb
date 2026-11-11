# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("browser.feature_flag_decision") do |payload|
    octo_cookie = payload.dig(:client, :context, :octolytics_id)
    feature = payload[:feature]
    visitor = Analytics::Visitor.with_octolytics_id(octo_cookie)

    if feature && octo_cookie && visitor
      message = {
        feature_flag: feature,
        decision: payload.dig(:client, :context, :feature_flag_enabled) ? "ENABLED" : "DISABLED",
        visitor_id: visitor.id.to_s
      }

      publish(message, schema: "github.v1.FeatureFlagDecision", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    end
  end

  subscribe("browser.feature_gate_upsell.click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:client][:user]),
      feature_name: payload[:feature_name]&.upcase,
    }

    publish(message, schema: "github.v1.FeatureGateUpsellClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
