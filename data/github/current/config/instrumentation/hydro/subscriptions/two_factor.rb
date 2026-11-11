# typed: strict
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("two_factor.sms_message_sent") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      hashed_sms_number: payload[:hashed_sms_number],
    }

    publish(message, schema: "github.v1.SmsMessageSent")
  end

  subscribe("two_factor_account_recovery.updated") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      action_type: payload[:action_type] || :ACTION_TYPE_UNKNOWN,
      evidence_type: payload[:evidence_type] || :EVIDENCE_TYPE_UNKNOWN,
    }

    publish(message, schema: "github.v1.TwoFactorRecoveryRequestChanged", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("automated_two_factor_account_recovery_request_review") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      review_required: payload[:review_required],
      reason_type: payload[:reason_type] || :REASON_TYPE_UNKNOWN,
      audit_log_event_type: payload[:audit_log_event_type],
      email_status_type: payload[:email_status_type] || :EMAIL_STATUS_TYPE_UNKNOWN,
      org_membership_type: payload[:org_membership_type] || :ORGANIZATION_MEMBERSHIP_TYPE_UNKNOWN,
    }

    publish(message, schema: "github.v1.AutomatedTwoFactorRecoveryRequestReview", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
