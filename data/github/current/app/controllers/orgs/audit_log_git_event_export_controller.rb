# typed: true
# frozen_string_literal: true

class Orgs::AuditLogGitEventExportController < Orgs::Controller
  include AuditLogExportHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :read_org_audit_logs_permission_required
  before_action :audit_log_export_required
  before_action :audit_log_git_event_export_required

  allow_verified_fetch only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:status]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :status], optional: true

  def show
    export = this_organization.audit_log_git_event_exports.find_by!(actor_id: current_user.id, token: params[:token])
    if params.has_key?(:verify_truncate) && params[:verify_truncate]
      respond_with_audit_log_truncate_status(export)
    else
      render_audit_log_export(export, params.slice(:start, :length).permit(:start, :length).to_h)
    end
  end

  def create
    options = {
      actor: current_user,
      start: parse_user_time(params[:start]),
      end: parse_user_time(params[:end]),
    }

    export = this_organization.audit_log_git_event_exports.create(options)

    fetch_url = org_audit_log_git_event_export_url(token: export.token)
    verify_url = org_audit_log_git_event_export_url(token: export.token, verify_truncate: true)
    status_url = org_audit_log_git_event_export_status_url(token: export.token)

    respond_with_audit_log_export(export: export, export_url: fetch_url, status_url: status_url, verify_url: verify_url)
  end

  def status # rubocop:todo GitHub/UseRestfulActions
    export = this_organization.audit_log_git_event_exports.find_by_token!(params[:token])
    respond_with_audit_log_export_status(export)
  end

  def parse_user_time(param) # rubocop:todo GitHub/UseRestfulActions
    zone = current_user&.time_zone || Time.zone
    zone.parse(param).utc
  end
end
