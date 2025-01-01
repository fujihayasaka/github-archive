# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    class SummaryLoaderJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      schedule interval: 24.hours, condition: -> { GitHub.copilot_for_business_enabled? }
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_metrics_summary_loader_job
      exempt_from_tenant_context_requirement

      sig { void }
      def perform
        if GitHub.flipper[:copilot_metrics_batched_summary_job].enabled?
          Copilot::Metrics::BatchedSummaryJob.perform_later(start_dates: [last_monday.to_s])
        else
          legacy_job_loading
        end
      end

      private

      sig { void }
      def legacy_job_loading
        org_ids = Copilot::Seat.where.not(organization_id: nil).distinct.pluck(:organization_id)
        GitHub.logger.info("Queueing Copilot::Metrics::SummaryJob for #{org_ids.count} organizations. Start date: #{last_monday}")

        org_ids.each do |id|
          GitHub.logger.with_named_tags("gh.copilot.owner.id": id, "gh.copilot.owner.type": "Organization") do
            GitHub.logger.info("Queueing Copilot::Metrics::SummaryJob for organization")
            Copilot::Metrics::SummaryJob.perform_later(owner_id: id, start_date: last_monday.to_s)
          end
        end
      end

      sig { returns(Date) }
      def last_monday
        Date.current.beginning_of_week(:monday) - 7
      end
    end
  end
end
