# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotInsightsUsageController < Stafftools::Businesses::CopilotInsightsBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Copilot,
        only: [:show, :export_files]

      # `show` and `export_files` actions are inherited from
      # Stafftools::Businesses::CopilotInsightsBaseController
      # and use the below hooks to customize behavior for this page.

      sig { returns(T.nilable(String)) }
      def self.react_bundle_name
        "copilot-insights-usage"
      end

      private

      sig { override.returns(String) }
      def copilot_insights_route_id = "stafftoolsCopilotUsageRoute"

      sig { override.returns(CopilotInsightsUsage::Shared::MetricsKey) }
      def copilot_insights_metrics_key = MetricsKey::UsageMetrics

      sig { override.returns(String) }
      def copilot_insights_title = "Copilot Usage Metrics - Stafftools"

      sig { override.returns(String) }
      def copilot_insights_export_files_url = export_files_stafftools_copilot_insights_usage_path(this_business)
    end
  end
end
