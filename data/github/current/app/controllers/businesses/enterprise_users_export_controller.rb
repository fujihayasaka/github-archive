# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseUsersExportController < Businesses::BusinessController
  include VerifiedFetchDependency
  include EnterpriseUsersExportHelper

  before_action :business_access_required
  before_action :require_enterprise_users_export_enabled

  allow_verified_fetch only: [:create, :show]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
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
      report_type: report_type
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
      export_url: enterprise_users_export_enterprise_url(token: export.token)
  end

  private

  def require_enterprise_users_export_enabled
    render_404 unless this_business.enterprise_users_export_enabled?
  end
end
