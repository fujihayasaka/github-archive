# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    module Organizations
      class ScheduledPlanDowngradeJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

        locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
        schedule interval: 24.hours, condition: -> { GitHub.copilot_for_business_enabled? }

        exempt_from_tenant_context_requirement

        sig { void }
        def perform
          GitHub.logger.info("Starting Copilot scheduled plan downgrade job")
          GitHub.logger.info("Loading organizations with scheduled downgrades")

          org_ids = Copilot::Configuration.pending_downgrades("Organization")

          GitHub.logger.with_named_tags(
            "code.function" => "perform",
            "gh.copilot.scheduled_plan_downgrade_job.orgs_count" => org_ids.count
          ) do
            GitHub.logger.info("Processing organizations with scheduled downgrades")

            orgs = ::Organization.where(id: org_ids)

            orgs.each do |org|
              copilot_org = Copilot::Organization.new(org)

              copilot_org.copilot_plan_downgrade!

              GitHub.logger.info("Processed downgrade for org #{org.id}")
            end
          end
        end
      end
    end
  end
end
