# typed: strict
# frozen_string_literal: true

module Copilot
  module BusinessTrials
    class UpgradeCleanupJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

      sig { params(organization_id: Integer).void }
      def perform(organization_id)
        GitHub.logger.with_named_tags("code.namespace" => self.class.name, "code.function" => "perform", "gh.org.id" => organization_id) do

          # clean up existing free users and CfI subscriptions
          GitHub.logger.info("Deleting any FreeUser records")
          organization = ::Organization.find(organization_id)
          user_ids = Copilot::Seat.for_organization(organization).pluck(:assigned_user_id)

          with_write do
            Copilot::FreeUser.where(user_id: user_ids).destroy_all
          end

          GitHub.logger.info("Deleting any CfI subscriptions")
          ::User.find(user_ids).each do |user|
            GitHub.logger.with_named_tags("gh.user.id" => user.id) do
              result = with_write do
                Copilot::User.new(user).cancel_and_refund_active_subscription(organization: organization)
              end
              refunding = result.value!
              unless refunding
                GitHub.logger.error("Could not refund user's CfI subscription")
                GitHub.dogstats.increment "copilot.business_trials_upgrade_cleanup_job.refund_failed"
              end
            end
          end
        end
      end
    end
  end
end
