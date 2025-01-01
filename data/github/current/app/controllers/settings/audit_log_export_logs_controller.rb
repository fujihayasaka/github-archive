# typed: true
# frozen_string_literal: true

class Settings::AuditLogExportLogsController < ApplicationController
  include AuditLogExportHelper
  before_action :login_required
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

  def target_for_conditional_access #rubocop:todo GitHub/UseRestfulActions
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  # If feature is enabled then show the view
  # else redirect to audit log
  def show
    if GitHub.audit_log_export_enabled? && export_logs_enabled?(current_user)
      exports = get_exports(current_user)
      render "settings/audit_log/export_logs", \
        locals: { \
          exports: exports.sorted, \
          json_exports: exports.to_json, \
          chunks_per_download: chunks_per_download_from_param(params[:cpd]),  \
          download_web_export_url: settings_user_audit_log_export_url(current_user), \
          download_git_export_url: "", \
        }
    else
      render_404
    end
  end
end
