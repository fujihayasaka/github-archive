# typed: true
# frozen_string_literal: true

require "hydro/schemas/github/copilot/v3/copilot_token_service_activate_pending_auth_checks_pb"

class HydroCopilotTokenServiceActivatePendingAuthChecksJob < HydroMessageJob
  queue_as :hydro_copilot_token_service_activate_pending_auth_checks

  exempt_from_tenant_context_requirement
  retry_on_dirty_exit

  # retry_on ExpectedError
  # discard_on IgnoredError

  # Public: process a Hydro message
  sig { void }
  def perform
    return unless FeatureFlag.vexi.enabled?(:copilot_token_service_auth_checks_and_seat_assignment_event_publishing, default: false)

    user_id = message[:user_id]
    return unless user_id

    user = User.find_by(id: user_id)
    return unless user

    GitHub.logger.with_named_tags(
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.user.id" => user_id,
    ) do
      GitHub.logger.info("Activating pending auth checks")

      copilot_user = Copilot::User.new(user)
      with_write do
        copilot_user.activate_pending_auth_checks!
      end
    end
  end
end
