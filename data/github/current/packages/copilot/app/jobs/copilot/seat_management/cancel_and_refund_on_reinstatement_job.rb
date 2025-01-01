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
          seat_assignment_id: T.nilable(Integer)
        ).void
      end
      def perform(user_id:, owner_id:, owner_type:, seat_assignment_id:)
        GitHub.logger.with_named_tags(
          "gh.user.id" => user_id,
          "gh.copilot.seat_assignment.id" => seat_assignment_id,
          "gh.copilot.seat_assignment.owner.type" => owner_type,
          "gh.copilot.seat_assignment.owner.id" => owner_id,
        ) do
          user = ::User.find_by(id: user_id)

          if user.nil?
            GitHub.logger.error("User not found, skipping cancellation and refund")
            return
          end

          # If there's no owner, the user's seat belongs to an enterprise
          organization = owner_type == "Organization" ? ::Organization.find_by(id: owner_id) : nil

          cancel_and_refund_user_subscription(user, organization)

          # FreeUser actually means complimentary access (ex: free educational, GitHub Star).
          # This would only be relevant if the user had their access revoked, regained their complementary status, and
          # then were reinstated within the same billing cycle
          free_user_records = Copilot::FreeUser.where(user_id: user_id)
          if free_user_records.any?
            with_write do
              free_user_records.destroy_all
            end
            if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, user, default: false)
              # we might have already done this if they also had a subscription item but we can do it again just in case
              Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(user))
            end
            GitHub.dogstats.increment("copilot.cancel_and_refund_on_reinstatement_job.free_user_destroyed")
            GitHub.logger.info("Destroyed FreeUser records for user on reinstatement")
          end
        end
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

        # if this is called and a subscription item exists and is refunded,
        # an individual_seat_converted event is emitted, which in turn causes the user settings cache to be rebuilt
        result = copilot_user.cancel_and_refund_active_subscription(
          organization: organization
        )

        if result.ok? && result.value!
          GitHub.logger.info("Triggered a cancellation and refunded request for Copilot Individual subscription")
          GitHub.dogstats.increment("copilot.subscription.cancel_and_refund_on_reinstatement_job.success")
        else
          # this isn't an error per se, we can get here if there was no subscription item to cancel
          GitHub.logger.info("Failed to cancel and refund Copilot Individual subscription or there was no subscription item")
          GitHub.dogstats.increment("copilot.subscription.cancel_and_refund_on_reinstatement_job.error")

          # we want to refresh the user's settings cache even if no subscription item was refunded,
          # if we're running this job we're adding a user back to an organization, reprovisioning the user, etc.
          # and new policies very likely apply to them.
          copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)

          if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, copilot_user.user_object, default: false)
            Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(copilot_user.user_object))
          end
        end
      end
    end
  end
end
