# typed: true
# frozen_string_literal: true

module Orgs
  class AuditLogController < Controller
    include AuditLogExportHelper
    include AuditLogHelper

    before_action :read_org_audit_logs_permission_required
    before_action :ensure_trade_restrictions_allows_org_settings_access

    javascript_bundle :settings
    javascript_bundle :"audit-log"

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Mysql2,
      only: [:results]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Billing,
      ApplicationRecord::Repositories,
      ApplicationRecord::Copilot,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Repositories,
      only: [:suggestions]

    def index
      render_elasticsearch_auditlogs
    end

    def render_elasticsearch_auditlogs # rubocop:todo GitHub/UseRestfulActions
      view = create_view_model(
        Orgs::AuditLog::IndexPageView,
        organization: this_organization,
        query: params[:q],
        page: page,
        after: params[:after],
        before: params[:before],
        git_export_enabled: git_export_enabled?,
        export_logs_enabled: export_logs_enabled?(this_organization),
        show_feedback_survey: show_feedback_survey?,
      )
      render "orgs/audit_log/index", locals: { view: view }
    end

    def results # rubocop:todo GitHub/UseRestfulActions
      view = create_view_model(
        Orgs::AuditLog::ResultsView,
        organization: this_organization,
        query: params[:q],
        page: page,
        after: params[:after],
        before: params[:before],
        git_export_enabled: git_export_enabled?,
        export_logs_enabled: export_logs_enabled?(this_organization)
      )
      render partial: "orgs/audit_log/search_results", locals: { view: view }
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
          render partial: "orgs/audit_log/suggestions", locals: {
            view: create_view_model(Orgs::AuditLog::SuggestionsView,
              organization: this_organization,
              filter: filter
            )
          }
        end
      end
    end

    protected

    def page
      params[:page].present? ? params[:page] : 1
    end

    def git_export_enabled?
      this_organization.business_plus? && audit_log_git_event_export_enabled?
    end

    def show_feedback_survey?
      GitHub.flipper[:audit_log_org_feedback_survey].enabled?(this_organization)
    end
  end
end
