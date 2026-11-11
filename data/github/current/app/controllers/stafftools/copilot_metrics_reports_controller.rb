# typed: true
# frozen_string_literal: true

class Stafftools::CopilotMetricsReportsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods
  include ::CopilotInsightsUsage::Stafftools

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  before_action :ensure_user_exists
  before_action :ensure_usage_dashboard_entity_supported

  layout :content_layout

  def show
    export_files = if GitHub::AppEnvironment.production? || GitHub::AppEnvironment.test?
      {
        organization: get_organization_export_files_from_usage_service,
        users: get_users_export_files_from_usage_service
      }
    else
      # In development, return sample file URLs
      {
        organization: [
          { "name" => "testOrganizationFile1.ndjson", "url" => "https://example.com/testOrganizationFile.ndjson" },
          { "name" => "testOrganizationFile2.ndjson", "url" => "https://example.com/testOrganizationFile2.ndjson" },
        ],
        users: [
          { "name" => "testUsersFile1.ndjson", "url" => "https://example.com/testUsersFile.ndjson" },
          { "name" => "testUsersFile2.ndjson", "url" => "https://example.com/testUsersFile2.ndjson" },
        ]
      }
    end

    render "stafftools/copilot_metrics/reports/show", locals: {
      export_files: export_files,
    }, layout: content_layout
  end

  private

  def get_organization_export_files_from_usage_service
    get_export_files_from_usage_service(
      "/organizations/#{this_user.id}/copilot/metrics/reports/organization-28-day/latest",
      "organization_report",
      entity_id: this_user.id,
      entity_type: "organization"
    )
  end

  def get_users_export_files_from_usage_service
    get_export_files_from_usage_service(
      "/organizations/#{this_user.id}/copilot/metrics/reports/users-28-day/latest",
      "users_report",
      entity_id: this_user.id,
      entity_type: "organization"
    )
  end
end
