# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotInsightsCodeGenerationController < Stafftools::Businesses::CopilotInsightsBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Collab,
        ApplicationRecord::Copilot,
        only: [:show, :export_files]

      sig { returns(T.nilable(String)) }
      def self.react_bundle_name
        "copilot-insights-code-generation"
      end

      # `show` and `export_files` actions are inherited from
      # Stafftools::Businesses::CopilotInsightsBaseController
      # and use the below hooks to customize behavior for this page.

      private

      sig { override.returns(String) }
      def copilot_insights_route_id = "stafftoolsCopilotCodeGenerationRoute"

      sig { override.returns(CopilotInsightsUsage::Shared::MetricsKey) }
      def copilot_insights_metrics_key = MetricsKey::CodeGenerationMetrics

      sig { override.returns(String) }
      def copilot_insights_title = "Copilot Code Generation Metrics - Stafftools"

      sig { override.returns(String) }
      def copilot_insights_export_files_url = export_files_stafftools_copilot_insights_code_generation_path(this_business)
    end
  end
end
