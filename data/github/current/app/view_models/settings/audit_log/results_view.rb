# typed: true
# frozen_string_literal: true

module Settings
  module AuditLog
    class ResultsView < ::AuditLog::ResultsView

      def page_title
        "Security log"
      end

      def tips
        @tips ||= Settings::AuditLog::TipView.new(user: current_user)
      end

      def search_path(options = {})
        query = if options.present?
          { q: build_query_param(options) }
        else
          {}
        end

        urls.settings_user_audit_log_path(query)
      end

      def search_path_query(options)
        urls.settings_user_audit_log_path(options)
      end

      def suggestions_path
        urls.settings_user_audit_log_suggestions_path
      end

      def support_url
        "#{GitHub.help_url}/authentication/keeping-your-account-and-data-secure/reviewing-your-security-log#searching-your-security-log"
      end

      def results_path
        options = {
          q: query,
          after: after,
          before: before,
        }
        urls.settings_user_audit_log_results_path(options)
      end

      def export_path
        urls.settings_user_audit_log_export_path(format: :json)
      end

      def normalize(entries)
        AuditLogEntry.for_users(entries)
      end

      def next_page_link
        options = {
          q: query,
          after: after,
          before: before,
          page: page.to_i + 1,
        }
        urls.settings_user_audit_log_path(options)
      end

      def prev_page_link
        options = {
          q: query,
          after: after,
          before: before,
          page: page.to_i - 1,
        }
        urls.settings_user_audit_log_path(options)
      end

      def repository_management_query
        "action:repo.create action:repo.destroy action:repo.restore action:repo.access"
      end

      def billing_updates_query
        "action:payment_method action:billing.change_email"
      end

      def pat_activity_query
        "action:personal_access_token"
      end

      def copilot_activity_query
        "action:copilot"
      end

      def can_show_ip?
        false
      end

      private

      # Private: The organization scoped audit log ElasticSearch query.
      #
      # Returns Hash
      def es_query
        {
          current_user: current_user,
          actor_id: current_user.id,
          user_id: current_user.id,
          phrase: query,
          page: page,
          after: after,
          before: before,
          feature_flags: feature_flags,
          non_sso_org_ids: protected_org_ids,
          per_page: 25,
        }
      end

      def protected_org_ids
        cap_filter.unauthorized(current_user&.direct_and_indirect_orgs).resource_ids
      end

      def search_query
        @search_query ||= Audit::Driftwood::Query.new_user_query(es_query)
      end
    end
  end
end
