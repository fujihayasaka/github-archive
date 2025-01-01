# typed: true
# frozen_string_literal: true

module Copilot
  module Metrics
    class ReportLinkJobOrchestrationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      schedule interval: 12.hours

      exempt_from_tenant_context_requirement

      PARTITION_NUMBER = 9

      sig { void }
      def perform
        return if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
        (0..PARTITION_NUMBER).each do |partition|
          Copilot::Metrics::ReportLinkJob.perform_later(
            total_partitions: PARTITION_NUMBER + 1,
            partition_number: partition
          )
        end
      end
    end
  end
end
