# typed: true
# frozen_string_literal: true

require "hydro/schemas/github/copilot/v3/copilot_token_service_seat_assignment_conversion_job_pb"

class HydroCopilotTokenServiceSeatAssignmentConversionJob < HydroMessageJob
  queue_as :hydro_copilot_token_service_seat_assignment_conversion_job

  retry_on_dirty_exit
  exempt_from_tenant_context_requirement

  # retry_on ExpectedError
  # discard_on IgnoredError

  # Public: process a Hydro message
  sig { void }
  def perform
    return unless FeatureFlag.vexi.enabled?(:copilot_token_service_auth_checks_and_seat_assignment_event_publishing, default: false)

    user_id = message[:user_id]
    return unless user_id

    headers = message[:headers].to_h.symbolize_keys

    GitHub.logger.with_named_tags(
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.user.id" => user_id,
    ) do
      GitHub.logger.info("Queueing seat assignment conversion job")

      # Note: User validation is handled by AccessSeatAssignmentConversionJob
      Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_later(
        user_id: user_id,
        headers: headers
      )
    end
  end
end
