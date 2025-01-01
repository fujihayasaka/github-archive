# typed: true
# frozen_string_literal: true

class Orgs::AuditLogExportLogsController < Orgs::Controller
  include AuditLogExportHelper
  before_action :audit_log_export_required
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
    if GitHub.audit_log_export_enabled? && export_logs_enabled?(this_organization)
      exports = get_exports(this_organization)
      render "orgs/audit_log/export_logs", \
        formats: [:html], \
        locals: { \
          organization: this_organization, \
          exports: exports.sorted, \
          json_exports: exports.to_json, \
          chunks_per_download: chunks_per_download_from_param(params[:cpd]),  \
          download_web_export_url: org_audit_log_export_url(this_organization), \
          download_git_export_url: org_audit_log_git_event_export_url(this_organization), \
        }
    else
      render_404
    end
  end
end
