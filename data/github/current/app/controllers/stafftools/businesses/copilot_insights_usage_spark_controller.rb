# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotInsightsUsageSparkController < Stafftools::Businesses::CopilotInsightsBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Copilot,
        only: [:show, :export_files]

      sig { returns(T.nilable(String)) }
      def self.react_bundle_name
        "copilot-insights-usage"
      end

      # `show` and `export_files` actions are inherited from
      # Stafftools::Businesses::CopilotInsightsBaseController
      # and use the below hooks to customize behavior for this page.

      private

      sig { override.returns(String) }
      def copilot_insights_route_id = "stafftoolsCopilotUsageSparkRoute"

      sig { override.returns(CopilotInsightsUsage::Shared::MetricsKey) }
      def copilot_insights_metrics_key = MetricsKey::UsageMetrics

      sig { override.returns(String) }
      def copilot_insights_title = "Copilot Usage Metrics (Spark) - Stafftools"

      sig { override.returns(String) }
      def copilot_insights_export_files_url = export_files_stafftools_copilot_insights_usage_spark_path(this_business)

      sig { override.returns(T::Boolean) }
      def copilot_insights_spark? = true
    end
  end
end
