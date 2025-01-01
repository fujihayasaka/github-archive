# typed: true
# frozen_string_literal: true

module Orgs
  module AuditLog
    class ResultsView < ::AuditLog::ResultsView
      attr_reader :organization

      def page_title
        "Audit log"
      end

      def tips
        @tips ||= Orgs::AuditLog::TipView.new(organization: organization, user: current_user)
      end

      def search_path(options = {})
        query = if options.present?
          { q: build_query_param(options) }
        else
          {}
        end

        urls.settings_org_audit_log_path(organization, query)
      end

      def search_path_query(options)
        urls.settings_org_audit_log_path(organization, options)
      end

      def results_path
        options = {
          q: query,
          after: after,
          before: before,
          organization_id: organization.display_login,
        }
        urls.settings_org_audit_log_results_path(options)
      end

      def suggestable_qualifiers
        [
          { value: "action:", description: "filter by action" },
          { value: "actor:", description: "filter by author" },
          { value: "country:", description: "filter by country" },
          { value: "created:", description: "filter by created date" },
          { value: "operation:", description: "filter by operation" },
          { value: "org:", description: "filter by organization" },
          { value: "repo:", description: "filter by repository" },
          { value: "user:", description: "filter by user" },
          { value: "hashed_token:", description: "filter by access token" },
        ] + flagged_suggestable_qualifiers
      end

      def flagged_suggestable_qualifiers
        qualifiers = []
        qualifiers << { value: "token_id:", description: "filter by token ID" }  if can_show_token_id?
        qualifiers
      end

      def suggestions_path
        urls.settings_org_audit_log_suggestions_path(organization)
      end

      def support_url
        "#{GitHub.help_url}/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/reviewing-the-audit-log-for-your-organization#searching-the-audit-log"
      end

      def export_path
        urls.org_audit_log_export_path(organization, format: :json)
      end

      def export_git_event_path
        urls.org_audit_log_git_event_export_path(organization, format: :json)
      end

      def filters_partial
        "orgs/audit_log/search_filters"
      end

      def normalize(entries)
        AuditLogEntry.for_orgs(entries)
      end

      def prev_page_params
        urls.settings_org_audit_log_path(page_params(before: prev_cursor))
      end

      def next_page_params
        urls.settings_org_audit_log_path(page_params(after: next_cursor))
      end

      def next_page_link
        options = page_params.merge({ page: page.to_i + 1 })
        urls.settings_org_audit_log_path(options)
      end

      def prev_page_link
        options = page_params.merge({ page: page.to_i - 1 })
        urls.settings_org_audit_log_path(options)
      end

      def hook_activity_query
        "action:hook"
      end

      def pat_activity_query
        "action:personal_access_token"
      end

      def copilot_activity_query
        "action:copilot"
      end

      # REMOVE THIS AFTER SSO AUDIT DETAILS SHIPS
      def can_view_sso?
        business.present? && GitHub.flipper[:audit_sso_disclosure].enabled?(business)
      end

      # REMOVE THIS AFTER SSO AUDIT DETAILS SHIPS
      def business
        @business ||= organization.business
      end

      def can_show_ip?
        return true if GitHub.enterprise?
        return @can_show_ip if defined?(@can_show_ip)
        @can_show_ip = organization&.can_enable_audit_log_ip_disclosure? && organization&.source_ip_disclosure_enabled?
      end

      def can_show_token_id?
        GitHub.flipper[:audit_log_token_id].enabled?(organization) ||
          GitHub.flipper[:audit_log_token_id].enabled?(organization.business)
      end

      private

      def page_params(after: "", before: "")
        pg_params = {}
        pg_params[:organization_id] = organization.display_login
        pg_params[:q] = query if active_search?
        pg_params[:after] = after unless after.blank?
        pg_params[:before] = before unless before.blank?
        pg_params
      end

      # Private: The organization scoped audit log ElasticSearch query.
      #
      # Returns Hash
      def es_query
        {
          current_user: current_user,
          org_id: organization.id,
          phrase: query,
          page: page,
          after: after,
          before: before,
          feature_flags: feature_flags,
          per_page: 25,
        }
      end
    end
  end
end
