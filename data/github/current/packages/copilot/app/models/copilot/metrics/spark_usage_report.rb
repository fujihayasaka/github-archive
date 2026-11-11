# typed: strict
# frozen_string_literal: true

module Copilot::Metrics
  # SparkUsageReport fetches usage data from the Spark ETL Kusto cluster.
  # It inherits all behavior from UsageReport but uses a different Kusto client.
  class SparkUsageReport < UsageReport
    sig { params(enterprise_id: T.nilable(Integer), organization_id: T.nilable(Integer)).void }
    def initialize(enterprise_id: nil, organization_id: nil)
      super(
        enterprise_id: enterprise_id,
        organization_id: organization_id,
        kusto_client_provider: Azure::SparkUsageReportsKustoClientProvider
      )
    end
  end
end
