# typed: true
# frozen_string_literal: true

class ExemptionRequestEmailJob < ApplicationJob

  PERFORM_REQUEST_TYPES = [
    "push_ruleset_bypass",
    SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
    CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
  ]

  queue_as :mailers

  retry_on ActiveJob::DeserializationError
  retry_on_dirty_exit

  sig { params(request: Exemptions::ExemptionRequest).void }
  def perform(request)

    return unless PERFORM_REQUEST_TYPES.include?(request.request_type)

    notification_configuration = request.evaluator&.request_notification_configuration(request)
    return if notification_configuration.nil?

    user_ids = request.evaluator&.notification_user_ids(request)
    return unless user_ids&.any?

    users = User.where(id: user_ids)
    users.each do |user|
      ExemptionRequestMailer.push_bypass(
        user,
        request,
        notification_configuration[:subject],
        notification_configuration[:reason],
        notification_configuration[:permalink],
      ).deliver_now
    end
  end
end
