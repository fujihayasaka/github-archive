# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("browser.signup_interstitial.click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:client][:user]),
      target: payload[:event_target],
    }

    publish(message, schema: "github.v1.SignupInterstitialClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.authentication.click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      auth_type: payload[:auth_type].presence || :AUTH_TYPE_UNKNOWN,
      location_in_page: payload[:location_in_page],
    }
    if payload[:repository_id]
      repo = Repositories.domain.by_id(payload[:repository_id].to_i)
      message[:repository] = serializer.repository(repo) if repo
      message[:owner] = serializer.user(repo.owner) if repo&.owner
    end
    publish(message, schema: "github.v1.AuthenticationClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("suggested_username.publish") do |payload|
    message = {
      suggestion_count: payload[:suggestion_count],
      action: payload[:action],
      actor: {
        user_id: payload[:actor][:user_id],
        login: payload[:actor][:login],
      },
    }

    publish(message, schema: "github.suggested_username.v0.SuggestedUsername", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
