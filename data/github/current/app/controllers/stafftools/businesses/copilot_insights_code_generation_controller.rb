# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotInsightsCodeGenerationController < Stafftools::Businesses::BusinessBaseController
      include ::Copilot::Businesses::InsightsExport
      include ::CopilotInsightsUsage::Params

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Collab,
        ApplicationRecord::Copilot,
        only: [:show, :export_files]

      before_action :site_admin_only
      before_action :ensure_feature_enabled
      before_action :canonicalize_query_params

      def show
        result = ::CopilotInsightsUsage::DashboardService.call(business: this_business, days: days)
        code_generation_metrics = result.code_generation_metrics
        display_flags = result.display_flags

        add_client_feature_flag([:copilot_insights_usage_export_ndjson], entity: this_business)

        respond_with_react(
          payload: {
            stafftoolsCopilotCodeGenerationRoute: {
              copilotLicenseManagementLink: stafftools_enterprise_licensing_path(this_business),
              exportFilesUrl: export_files_stafftools_copilot_insights_code_generation_path(this_business),
              displayBlankslate: display_flags[:blankslate],
              displayError: display_flags[:error],
              codeGenerationMetrics: code_generation_metrics,
              slug: this_business&.slug,
              canonicalQueryParams: @canonical_params,
            }
          },
          title: "Copilot Code Generation Metrics - Stafftools",
          layout: "layouts/stafftools/business"
        )
      end

      def export_files # rubocop:todo GitHub/UseRestfulActions
        begin
          export_files = generate_export_files(this_business)
          render json: { export_files: export_files }
        rescue => e
          Failbot.report(e)
          render json: { error: "Unable to fetch export files" }, status: :internal_server_error
        end
      end

      def ensure_feature_enabled # rubocop:todo GitHub/UseRestfulActions
        stafftools_flag_enabled = FeatureFlag.vexi.enabled?(:copilot_insights_code_generation_stafftools, current_user, default: false) ||
                                  FeatureFlag.vexi.enabled?(:copilot_insights_code_generation_stafftools, this_business, default: false)
        insights_flag_enabled = FeatureFlag.vexi.enabled?(:copilot_usage_lines_of_code, current_user, default: false) ||
                                FeatureFlag.vexi.enabled?(:copilot_usage_lines_of_code, this_business, default: false)

        render_404 unless stafftools_flag_enabled && insights_flag_enabled
      end
    end
  end
end
