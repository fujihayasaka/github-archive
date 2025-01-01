# typed: true
# frozen_string_literal: true

class Orgs::AuditLogExportController < Orgs::Controller
  include AuditLogExportHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :read_org_audit_logs_permission_required
  before_action :audit_log_export_required

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
    only: [:export_status]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :export_status],
    optional: true

  def show
    export = this_organization.audit_log_web_exports.find_by_export_id!(params[:export_id])
    if params.has_key?(:verify_truncate) && params[:verify_truncate]
      respond_with_audit_log_truncate_status(export)
    else
      render_audit_log_export(export, params.slice(:start, :length).permit(:start, :length).to_h)
    end
  end

  def export_status # rubocop:todo GitHub/UseRestfulActions
    export = this_organization.audit_log_web_exports.find_by_export_id!(params[:export_id])
    respond_with_audit_log_export_status(export)
  end

  def create
    options = {
      actor: current_user,
      format_type: params[:export_format],
      phrase: params[:q],
    }

    export = this_organization.audit_log_web_exports.create(options)
    if export.persisted?
      export.start_export
    end

    respond_with_audit_log_export \
      export: export,
      export_url: org_audit_log_export_url(
        export_id: export.export_id,
      ),
      status_url: org_audit_log_export_status_url(
        export_id: export.export_id
      ),
      verify_url: org_audit_log_export_url(
        export_id: export.export_id,
        verify_truncate: true,
      )
  end
end
