# typed: true
# frozen_string_literal: true

class Businesses::AuditLogExportLogsController < Businesses::BusinessController
  include AuditLogExportHelper
  before_action :business_owner_required
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  # If feature is enabled then show the view
  # else redirect to audit log
  def show
    if GitHub.audit_log_export_enabled? && export_logs_enabled?(this_business)
      exports = get_exports(this_business)
      render "businesses/audit_log/export_logs", \
        locals: { \
          business: this_business, \
          exports: exports.sorted, \
          json_exports: exports.to_json, \
          chunks_per_download: chunks_per_download_from_param(params[:cpd]),  \
          download_web_export_url: settings_audit_log_export_enterprise_url(this_business), \
          download_git_export_url: settings_audit_log_git_event_export_enterprise_url(this_business), \
        }
    else
      render_404
    end
  end
end
