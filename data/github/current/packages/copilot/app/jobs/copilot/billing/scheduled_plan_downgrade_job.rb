# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class ScheduledPlanDowngradeJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      schedule interval: 24.hours, condition: -> { GitHub.copilot_for_business_enabled? }
      gate_with_feature_flag :copilot_scheduled_plan_downgrade_job

      sig { void }
      def perform
        GitHub.logger.info("Starting Copilot scheduled plan downgrade job")
        GitHub.logger.info("Loading businesses with scheduled downgrades")

        business_ids = Copilot::Configuration.pending_downgrades("Business")

        GitHub.logger.with_named_tags("code.function" => "perform", "gh.copilot.scheduled_plan_downgrade_job.businesses_count" => business_ids.count) do
          GitHub.logger.info("Processing businesses with scheduled downgrades")

          businesses = ::Business.where(id: business_ids)

          businesses.each do |business|
            copilot_business = Copilot::Business.new(business)

            copilot_business.copilot_plan_downgrade!

            GitHub.logger.info("Processed downgrade for business #{business.id}")
          end
        end
      end
    end
  end
end
