# typed: true
# frozen_string_literal: true

module CopilotInsightsUsage
  # SparkDashboardService fetches dashboard data from the Spark ETL Kusto cluster.
  # It delegates to DashboardService but uses SparkUsageReport instead of UsageReport.
  class SparkDashboardService
    def self.call(business: nil, organization: nil, days:)
      DashboardService.call(
        business: business,
        organization: organization,
        days: days,
        report_class: ::Copilot::Metrics::SparkUsageReport
      )
    end
  end
end
