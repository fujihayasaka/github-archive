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
        ApplicationRecord::Copilot,
        only: [:show, :export_files]

      before_action :site_admin_only
      before_action :canonicalize_query_params

      def show
        result = ::CopilotInsightsUsage::DashboardService.call(business: this_business, days: days)
        usage_metrics = result.usage_metrics
        display_flags = result.display_flags

        respond_with_react(
          payload: {
            stafftoolsCopilotUsageRoute: {
              copilotLicenseManagementLink: stafftools_enterprise_licensing_path(this_business),
              exportFilesUrl: export_files_stafftools_copilot_insights_usage_path(this_business),
              displayBlankslate: display_flags[:blankslate],
              displayError: display_flags[:error],
              usageMetrics: usage_metrics,
              slug: this_business&.slug,
              canonicalQueryParams: @canonical_params,
            }
          },
          title: "Copilot Usage Metrics - Stafftools",
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
    end
  end
end
