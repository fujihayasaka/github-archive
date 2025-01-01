# typed: true
# frozen_string_literal: true

class Settings::AuditLogExportController < ApplicationController
  include AuditLogExportHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :audit_log_export_required

  allow_verified_fetch only: [:create]

  # CAP enforcement not required because this is a use case for filtering - see the :non_sso_org_ids option
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:export_status]

  def show
    export = current_user.audit_log_web_exports.find_by_export_id!(params[:export_id])
    if params.has_key?(:verify_truncate) && params[:verify_truncate]
      respond_with_audit_log_truncate_status(export)
    else
      render_audit_log_export(export, params.slice(:start, :length).permit(:start, :length).to_h)
    end
  end

  def export_status # rubocop:todo GitHub/UseRestfulActions
    export = current_user.audit_log_web_exports.find_by_export_id!(params[:export_id])
    respond_with_audit_log_export_status(export)
  end

  def create
    options = {
      actor: current_user,
      format_type: params[:export_format],
      phrase: params[:q],
    }

    if FeatureFlag.vexi.enabled?(:audit_user_export_cap_filtering, current_user, default: false)
      ids = cap_filter.unauthorized(current_user&.direct_and_indirect_orgs).resource_ids
      options[:non_sso_org_ids] = ids unless ids.blank?
    end

    export = current_user.audit_log_web_exports.create(options)
    if export.persisted?
      export.start_export
    end

    respond_with_audit_log_export \
      export: export,
      export_url: settings_user_audit_log_export_url(
        export_id: export.export_id,
      ),
      status_url: settings_user_audit_log_export_status_url(
        export_id: export.export_id
      ),
      verify_url: settings_user_audit_log_export_url(
        export_id: export.export_id,
        verify_truncate: true,
      )
  end
end
