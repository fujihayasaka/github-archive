# typed: true
# frozen_string_literal: true

class Businesses::AuditLogController < Businesses::BusinessController
  include AuditLogExportHelper
  include ApplicationController::VerifiedFetchDependency

  before_action do
    T.bind(self, Businesses::AuditLogController)

    if this_business&.feature_flag_enabled?(:use_biz_audit_log_fgp_ui, default: false)
      business_permission_required(:read_enterprise_audit_logs)
    else
      # this experiment runs the logic in `business_owner_required` and `business_permission_required`
      # we can't experiment with those directly because we can only call `render_404` once.
      domain = Authz.domain # ensure domain is initialized to avoid counting init in experiment perf
      allowed = Scientist.run "biz_audit_log_fgp_ui_experiment" do |e|
        e.use { this_business&.owner?(current_user) }
        e.try do
          next false unless this_business && current_user
          domain.check_allowed(T.must(current_user), :read_enterprise_audit_logs, this_business)
        end
      end
      render_404 unless allowed
    end
  end

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
end
