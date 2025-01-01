# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseUsersExportController < Stafftools::Businesses::BusinessBaseController
  include VerifiedFetchDependency
  include EnterpriseUsersExportHelper
  include BusinessesHelper

  allow_verified_fetch only: [:create, :show]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  # Download a finished report
  def show
    export = this_business.business_report_exports.find_by!(token: params[:token], report_type: report_type)
    render_export(export: export, stat_name: report_name)
  end

  # Create a report. This will return a JSON body with a URL to check on report status and download the report.
  def create
    options = {
      actor: current_user,
      report_type: report_type,
      triggered_via_stafftools: true
    }

    # Export from licensing page uses slightly different settings
    if params[:use_licensing_settings]
      options[:settings] = {
        include_nonlicensed_roles: false,
        include_users_removed_this_cycle: true
      }
    end

    export = this_business.business_report_exports.create(options)
    respond_with_enterprise_users_export \
      export: export,
      export_url: enterprise_users_export_stafftools_enterprise_url(token: export.token)
  end
end
