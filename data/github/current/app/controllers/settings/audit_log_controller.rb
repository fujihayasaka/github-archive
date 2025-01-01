# typed: true
# frozen_string_literal: true

class Settings::AuditLogController < ApplicationController
  include AuditLogHelper

  before_action :login_required
  # cap enforcement not required because we use a filter for audit log entries
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  javascript_bundle :"audit-log"
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:results]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:suggestions]

  def index
    view = create_view_model(
      Settings::AuditLog::IndexPageView,
      query: params[:q],
      page: page,
      after: params[:after],
      before: params[:before],
      cap_filter: cap_filter,
      export_logs_enabled: export_logs_enabled?,
    )
    render "settings/audit_log/index", locals: { view: view }
  end

  def results # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Settings::AuditLog::ResultsView,
      query: params[:q],
      page: page,
      after: params[:after],
      before: params[:before],
      cap_filter: cap_filter,
      export_logs_enabled: export_logs_enabled?,
    )
    render partial: "settings/audit_log/search_results", locals: { view: view }
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
        render partial: "settings/audit_log/suggestions", locals: {
          view: create_view_model(Settings::AuditLog::SuggestionsView,
            filter: filter,
            cap_filter: cap_filter,
          ),
        }
      end
    end
  end

  protected

  def export_logs_enabled?
    GitHub.flipper[:audit_log_export_logs].enabled?(current_user)
  end

  def page
    params[:page].present? ? params[:page] : 1
  end
end
