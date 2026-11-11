# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotMetricsReportsController < Stafftools::Businesses::BusinessBaseController
      include ::CopilotInsightsUsage::Stafftools

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Copilot,
        ApplicationRecord::Collab,
        only: [:show]

      before_action :site_admin_only

      def show
        export_files = if GitHub::AppEnvironment.production? || GitHub::AppEnvironment.test?
          {
            enterprise: get_enterprise_export_files_from_usage_service,
            users: get_users_export_files_from_usage_service
          }
        else
          # In development, return sample file URLs
          {
            enterprise: [
              { "name" => "testEnterpriseFile1.ndjson", "url" => "https://example.com/testEnterpriseFile.ndjson" },
              { "name" => "testEnterpriseFile2.ndjson", "url" => "https://example.com/testEnterpriseFile2.ndjson" },
            ],
            users: [
              { "name" => "testUsersFile1.ndjson", "url" => "https://example.com/testUsersFile.ndjson" },
              { "name" => "testUsersFile2.ndjson", "url" => "https://example.com/testUsersFile2.ndjson" },
            ]
          }
        end

        render "stafftools/businesses/copilot_metrics/reports/show", locals: {
          export_files: export_files,
        }
      end

      private

      def get_enterprise_export_files_from_usage_service
        get_export_files_from_usage_service(
          "/enterprises/#{this_business.id}/copilot/metrics/reports/enterprise-28-day/latest",
          "enterprise_report",
          entity_id: this_business.id,
          entity_type: "enterprise"
        )
      end

      def get_users_export_files_from_usage_service
        get_export_files_from_usage_service(
          "/enterprises/#{this_business.id}/copilot/metrics/reports/users-28-day/latest",
          "users_report",
          entity_id: this_business.id,
          entity_type: "enterprise"
        )
      end
    end
  end
end
