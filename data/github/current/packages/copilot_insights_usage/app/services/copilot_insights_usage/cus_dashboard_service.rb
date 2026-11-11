# typed: true
# frozen_string_literal: true

module CopilotInsightsUsage
  # Fetches dashboard data from the Copilot Usage Service HTTP API,
  # delegating to DashboardService with CusUsageReport as the data source.
  class CusDashboardService
    def self.call(business: nil, organization: nil, days:)
      DashboardService.call(
        business: business,
        organization: organization,
        days: days,
        report_class: CopilotInsightsUsage::CusUsageReport
      )
    end
  end
end
