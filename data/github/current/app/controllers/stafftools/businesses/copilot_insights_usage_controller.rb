# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotInsightsUsageController < Stafftools::Businesses::BusinessBaseController
      include ::Copilot::Businesses::InsightsExport
      include ::CopilotInsightsUsage::Params
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        only: [:show, :export_files]

      before_action :site_admin_only
      before_action :ensure_feature_enabled
      before_action :canonicalize_query_params

      def show
        result = ::CopilotInsightsUsage::DashboardService.call(business: this_business, days: days)
        usage_metrics = result.usage_metrics
        display_blankslate = result.display_blankslate
        display_error = result.display_error

        respond_with_react(
          payload: {
            stafftoolsCopilotUsageRoute: {
              copilotLicenseManagementLink: stafftools_enterprise_licensing_path(this_business),
              exportFilesUrl: export_files_stafftools_copilot_insights_usage_path(this_business),
              displayBlankslate: display_blankslate,
              displayError: display_error,
              usageMetrics: usage_metrics,
              slug: this_business&.slug,
              canonicalQueryParams: @canonical_params,
            }
          },
          title: "Copilot Metrics Dashboard - Stafftools",
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

      private

      def ensure_feature_enabled
        insights_flag_enabled = FeatureFlag.vexi.enabled?(:copilot_insights_usage, current_user, default: false) ||
                                FeatureFlag.vexi.enabled?(:copilot_insights_usage, this_business, default: false)

        render_404 unless insights_flag_enabled
      end
    end
  end
end
