# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    class SummaryJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_metrics_summary_jobs
      resolve_tenant_context do |args|
        ::Organization.find_by(id: args[:owner_id])&.business
      end
      SUMMARY_RETENTION_DAYS = 100

      sig { params(owner_id: Integer, start_date: String).void }
      def perform(owner_id:, start_date:)
        # For now, we only support weekly summaries that start on a Monday and end on a Sunday.
        date = Date.parse(start_date)
        raise ArgumentError, "start_date must be a Monday" unless date.monday?

        owner = ::Organization.find(owner_id)
        create_metric_summary(owner: owner, start_date: date)
        delete_old_summaries(owner: owner)
      end

      private

      sig { params(owner: ::Organization, start_date: Date).void }
      def create_metric_summary(owner:, start_date:)
        Copilot::Metrics::CreateMetricSummary.call(owner: owner, start_date: start_date)
      end

      sig { params(owner: ::Organization).void }
      def delete_old_summaries(owner:)
        to_delete = Copilot::MetricSummary.where(owner: owner).where("start_date < ?", SUMMARY_RETENTION_DAYS.days.ago)

        GitHub.logger.with_named_tags("gh.copilot.owner.id": owner.id, "gh.copilot.owner.type": owner.class.to_s) do
          if to_delete.any?
            GitHub.logger.info("Deleting #{to_delete.count} metric summaries")
            with_write do
              to_delete.destroy_all
            end
          else
            GitHub.logger.info("No summaries to delete")
          end
        end
      end
    end
  end
end
