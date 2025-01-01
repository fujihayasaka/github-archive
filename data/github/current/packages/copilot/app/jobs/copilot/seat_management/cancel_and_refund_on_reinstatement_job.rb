# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # This job is responsible for cancelling and refunding active Copilot for Individual subscriptions
    # when a user's seat assignment access is reinstated. This ensures users don't have both
    # Copilot for Individual and Copilot for Business subscriptions active at the same time.
    class CancelAndRefundOnReinstatementJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers

      gate_with_feature_flag :copilot_cancel_and_refund_on_reinstatement_job

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      retry_on_dirty_exit

      resolve_tenant_context do |args|
        user_id = args[:user_id]
        user = ::User.find_by(id: user_id)
        return nil if user.nil?

        owner_id = args[:owner_id]
        owner_type = args[:owner_type]

        if owner_type == "Organization"
          ::Organization.find_by(id: owner_id)&.business
        else
          # If no organization, use the user's enterprise if available
          ::Business.find_by(id: owner_id)
        end
      end

      sig do
        params(
          user_id: Integer,
          owner_id: Integer,
          owner_type: String,
          seat_assignment_id: Integer
        ).void
      end
      def perform(user_id:, owner_id:, owner_type:, seat_assignment_id:)
        user = ::User.find_by(id: user_id)

        if user.nil?
          GitHub.logger.error("User not found, skipping cancellation and refund",
            "gh.user.id" => user_id,
            "gh.copilot.seat_assignment.id" => seat_assignment_id,
            "gh.copilot.seat_assignment.owner.type" => owner_type,
            "gh.copilot.seat_assignment.owner.id" => owner_id,
          )
          return
        end

        # If there's no owner, the user's seat belongs to an enterprise
        organization = owner_type == "Organization" ? ::Organization.find_by(id: owner_id) : nil
        cancel_and_refund_user_subscription(user, organization)
      end

      private

      sig do
        params(
          user: ::User,
          organization: T.nilable(::Organization)
        ).void
      end
      def cancel_and_refund_user_subscription(user, organization)
        copilot_user = Copilot::User.new(user)

        result = copilot_user.cancel_and_refund_active_subscription(
          organization: organization
        )

        if result.ok? && result.value!
          GitHub.logger.info("Triggered a cancellation and refunded request for Copilot Individual subscription")
          GitHub.dogstats.increment("copilot.subscription.cancel_and_refund_on_reinstatement_job.success")
        else
          GitHub.logger.error("Failed to cancel and refund Copilot Individual subscription")
          GitHub.dogstats.increment("copilot.subscription.cancel_and_refund_on_reinstatement_job.error")
        end
      end
    end
  end
end
