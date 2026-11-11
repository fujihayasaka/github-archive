# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("octocaptcha.signup") do |payload|
    event_id = Base64.encode64("#{payload[:event_type]}-#{payload[:session_id]}-#{payload[:occurred_at].to_i}")
    message = {
      event_id: event_id,
      occurred_at: payload[:occurred_at],
      event_type: payload[:event_type],
      session_id: payload[:session_id],
      show_captcha: payload[:show_captcha],
      show_one_page_flow: true,
      validation_value: payload[:validation_value],
      validation_error: payload[:validation_error],
      signup_time: payload[:signup_time],
      funcaptcha_response: serializer.funcaptcha_response(payload[:funcaptcha_response]),
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(payload[:user]),
      source_page: payload[:source_page],
      email_address: payload[:email_address],
      raw_funcaptcha_response_data: payload[:funcaptcha_response] && payload[:funcaptcha_response].to_json,
      octo_id: payload[:octo_id],
    }

    publish(message, schema: "github.v1.OctocaptchaSignup", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("octocaptcha.log") do |payload|
    publish(payload, schema: "github.v1.OctocaptchaLog")
  end
end
