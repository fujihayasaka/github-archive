# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class OrgTransformFromIndividualJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

      gate_with_feature_flag :copilot_org_transform_from_individual_job
      resolve_tenant_context do |args|
        ::Organization.find_by(id: args[:org_id])&.business
      end

      sig { params(org_id: Integer).void }
      def perform(org_id:)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.org.id" => org_id
        ) do
          GitHub.logger.info("Starting Copilot::SeatManagement::OrgTransformFromIndividualJob")

          org_from_user = ::Organization.where(id: org_id).first

          if org_from_user.nil?
            return handle_copilot_error(Copilot::Errors::OrgTransformFromIndividualError.new("Unable to find organization"), { "gh.org.id" => org_id })
          end

          with_write do
            # clean up any FreeUser records
            destroyed = Copilot::FreeUser.where(user_id: org_from_user.id).destroy_all
            if destroyed.any?
              GitHub.logger.info("Destroyed FreeUser records", "gh.copilot.org_transform.destroyed_free_users" => destroyed.count)
              GitHub.dogstats.count("copilot.org_transform.destroyed_free_users", destroyed.count)
            end

            # clean up any LimitedUser records
            destroyed = Copilot::LimitedUser.where(user_id: org_from_user.id).destroy_all
            if destroyed.any?
              GitHub.logger.info("Destroyed LimitedUser records", "gh.copilot.org_transform.destroyed_limited_users" => destroyed.count)
              GitHub.dogstats.count("copilot.org_transform.destroyed_limited_users", destroyed.count)
            end
          end

          copilot_user = Copilot::User.new(org_from_user)
          sub = copilot_user.copilot_active_subscription_item

          if sub.nil?
            GitHub.logger.info("No active subscription found, exiting")
            GitHub.dogstats.increment("copilot.org_transform.no_active_subscription")
            return
          end

          GitHub.logger.info("Cleaning up copilot subscription")
          with_write do
            # We have to explicitly call with `allow_cancelling_iap: true` since there is a chance that
            # the subscription was an in-app purchase. This override acknowledges that we are aware of the
            # potential consequences of cancelling an in-app purchase when we are not the source-of-truth
            # for the subscription (Apple or Google is).
            sub.cancel_and_refund!(organization: org_from_user, allow_cancelling_iap: true)
          end

          GitHub.dogstats.increment("copilot.org_transform.cancelled_subscription_item")
          GitHub.logger.info("Finished Copilot::SeatManagement::OrgTransformFromIndividualJob", "gh.copilot.org_transform.cancelled_subscription_item" => sub.id)
        end
      end
    end
  end
end
