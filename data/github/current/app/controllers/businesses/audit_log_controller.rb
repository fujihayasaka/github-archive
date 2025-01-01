# typed: true
# frozen_string_literal: true

class Businesses::AuditLogController < Businesses::BusinessController
  include AuditLogExportHelper
  include AuditLogHelper
  include ReactHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :business_owner_required
  before_action :audit_log_export_required, only: [:export, :create_export, :export_status]
  before_action :audit_log_git_event_export_required, only: [:git_export, :create_git_export, :git_event_export_status]

  allow_verified_fetch only: [:create_export, :create_git_export]

  javascript_bundle :"audit-log"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:export]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:git_export]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:export_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:git_event_export_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    only: [:results]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:export, :export_status, :git_export, :git_event_export_status],
    optional: true

  def index
    view = create_view_model(
      Businesses::AuditLog::IndexPageView,
      business: this_business,
      query: params[:q],
      page: current_page,
      git_export_enabled: audit_log_git_event_export_enabled?,
      export_logs_enabled: export_logs_enabled?(current_business),
      show_feedback_survey: show_feedback_survey?,
      after: params[:after],
      before: params[:before],
    )
    render "businesses/audit_log/index", locals: { view: view }
  end

  def results # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Businesses::AuditLog::ResultsView,
      business: this_business,
      query: params[:q],
      page: current_page,
      git_export_enabled: audit_log_git_event_export_enabled?,
      export_logs_enabled: export_logs_enabled?(current_business),
      after: params[:after],
      before: params[:before],
    )
    render partial: "businesses/audit_log/search_results", locals: { view: view }
  rescue Driftwood::TwirpUtil::RateLimitedError
    render status: 429, plain: "You can't perform that action at this time. Please try again later."
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    headers["Cache-Control"] = "no-cache, no-store"

    if params.has_key?("query")
      filter = params["query"]
    else
      filter = ""
    end

    respond_to do |format|
      format.html do
        render partial: "businesses/audit_log/suggestions", locals: {
          view: create_view_model(Businesses::AuditLog::SuggestionsView,
              business: this_business,
              filter: filter
          )
        }
      end
    end
  end

  def export # rubocop:todo GitHub/UseRestfulActions
    export = this_business.audit_log_web_exports.find_by_export_id!(params[:export_id])
    if params.has_key?(:verify_truncate) && params[:verify_truncate]
      respond_with_audit_log_truncate_status(export)
    else
      render_audit_log_export(export, params.slice(:start, :length).permit(:start, :length).to_h)
    end
  end

  def create_export # rubocop:todo GitHub/UseRestfulActions
    options = {
      actor: current_user,
      format_type: params[:export_format],
      phrase: params[:q],
    }

    export = this_business.audit_log_web_exports.create(options)
    if export.persisted?
      export.start_export
    end

    if GitHub.audit_log_export_enabled? && export_logs_enabled?(current_business)
      if current_user&.feature_enabled?(:audit_log_react)
        exports = AuditLogExports.new([export], [])
        render(json: { errors: export.errors[:subject], exports: exports.to_json }, status: :ok)
      else
        if !export.errors[:subject].empty?
          head 429 # too many exports already
        else
          flash[:notice] = "Export job successfully created. You can view the status of the export on the 'Export History' page."
          redirect_to :back
        end
      end
    else
      respond_with_audit_log_export \
        export: export,
        export_url: settings_audit_log_export_enterprise_url(
          export_id: export.export_id,
        ),
        status_url: settings_audit_log_export_status_enterprise_url(
          export_id: export.export_id
        ),
        verify_url: settings_audit_log_export_enterprise_url(
          export_id: export.export_id,
          verify_truncate: true,
        )
    end
  end

  def git_export # rubocop:todo GitHub/UseRestfulActions
    export = this_business.audit_log_git_event_exports.find_by!(actor_id: current_user&.id, token: params[:token])
    if params.has_key?(:verify_truncate) && params[:verify_truncate]
      respond_with_audit_log_truncate_status(export)
    else
      render_audit_log_export(export, params.slice(:start, :length).permit(:start, :length).to_h)
    end
  end

  def create_git_export # rubocop:todo GitHub/UseRestfulActions
    options = {
      actor: current_user,
      start: parse_user_time(params[:start]),
      end: parse_user_time(params[:end]),
    }

    export = this_business.audit_log_git_event_exports.create(options)

    if GitHub.audit_log_export_enabled? && export_logs_enabled?(current_business)
      if current_user&.feature_enabled?(:audit_log_react)
        exports = AuditLogExports.new([], [export])
        render(json: { errors: export.errors[:subject], exports: exports.to_json }, status: :ok)
      else
        if !export.errors[:subject].empty?
          head 429 # too many exports already
        else
          flash[:notice] = "Export job successfully created. You can view the status of the git export on the 'Export History' page."
          redirect_to :back
        end
      end
    else
      respond_with_audit_log_export \
        export: export,
        export_url: settings_audit_log_git_event_export_enterprise_url(
          token: export.token,
        ),
        status_url: settings_audit_log_git_event_export_status_enterprise_url(token: export.token),
        verify_url: settings_audit_log_git_event_export_enterprise_url(
          token: export.token,
          verify_truncate: true,
        )
    end
  end

  def git_event_export_status # rubocop:todo GitHub/UseRestfulActions
    export = this_business.audit_log_git_event_exports.find_by_token!(params[:token])
    respond_with_audit_log_export_status(export)
  end

  def export_status # rubocop:todo GitHub/UseRestfulActions
    export = this_business.audit_log_web_exports.find_by_export_id!(params[:export_id])
    respond_with_audit_log_export_status(export)
  end

  def parse_user_time(param) # rubocop:todo GitHub/UseRestfulActions
    zone = current_user&.time_zone || Time.zone
    zone.parse(param)
  end

  private

  def show_feedback_survey?
    GitHub.flipper[:audit_log_business_feedback_survey].enabled?(current_business)
  end
end
