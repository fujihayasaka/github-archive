# typed: true
# frozen_string_literal: true

module Copilot
  module Metrics
    class ReportLinkJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      # Define retryable errors that might occur during report link processing
      RETRYABLE_ERRORS = [
        ActiveRecord::Deadlocked,
        ActiveRecord::LockWaitTimeout,
        Faraday::Error,
        Timeout::Error,
        Copilot::Metrics::UsageReport::NoDataAvailableError
      ].freeze

      # Retry up to 3 times with exponential backoff
      retry_on *T.unsafe(RETRYABLE_ERRORS), wait: :polynomially_longer, attempts: 3 do |job, error|
        GitHub.dogstats.increment("copilot.metrics.report_link_job.retries_exhausted", tags: [
          "partition_number:#{job.arguments.dig(1, "partition_number") || "unknown"}",
          "error_class:#{error.class.name.underscore}"
        ])

        GitHub.logger.error("ReportLinkJob exceeded maximum retries", {
          "code.namespace" => self.class.name,
          "error_class" => error.class.name,
          "error_message" => error.message,
          "job_arguments" => job.arguments
        })
      end

      exempt_from_tenant_context_requirement

      sig { params(total_partitions: Integer, partition_number: Integer).void }
      def perform(total_partitions:, partition_number:)
        # This will fetch the latest business report end dates for all businesses who's id % total_partitions equals partition_number
        # This is used to distribute the workload across multiple job instances
        begin
          business_report_end_dates = Copilot::Metrics::UsageReport.get_latest_dates(
            number_of_partitions: total_partitions,
            partition_number: partition_number
          )
        rescue Copilot::Metrics::UsageReport::NoDataAvailableError => e
          GitHub.logger.info("No data available for ReportLinkJob", {
            "code.namespace" => self.class.name,
            "error_class" => e.class.name,
            "error_message" => e.message,
            "total_partitions" => total_partitions,
            "partition_number" => partition_number
          })
          raise e
        end

        # For each business_id, and latest_date we will fetch the blob names for each report type and store them in the database
        business_report_end_dates.each do |obj|
          business_id = obj[:business_id]
          latest_date = obj[:latest_date]
          next if business_id.nil?
          next if latest_date.nil?

          business_report_export = CopilotInsightsUsage::ReportExport.new(
            enterprise_id: business_id,
            date: latest_date,
            container_name: "enterprise-28-day-report"
          )

          users_report_export = CopilotInsightsUsage::ReportExport.new(
            enterprise_id: business_id,
            date: latest_date,
            container_name: "enterprise-users-28-day"
          )

          business_report_links = business_report_export.list
          users_report_links = users_report_export.list

          ActiveRecord::Base.connected_to(role: :writing) do
            Copilot::MetricsReportLink.upsert_latest!(
              business_id: business_id,
              report_type: :enterprise_28_day,
              report_end_day: latest_date,
              download_links: business_report_links.map(&:name)
            ) unless business_report_links.empty?

            Copilot::MetricsReportLink.upsert_latest!(
              business_id: business_id,
              report_type: :users_28_day,
              report_end_day: latest_date,
              download_links: users_report_links.map(&:name)
            ) unless users_report_links.empty?
          end
        end
      end
    end
  end
end
