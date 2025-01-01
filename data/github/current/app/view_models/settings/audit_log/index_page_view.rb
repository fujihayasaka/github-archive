# typed: true
# frozen_string_literal: true

module Settings
  module AuditLog
    class IndexPageView < ::AuditLog::IndexPageView
      def page_title
        "Security log"
      end

      def results_path
        options = {
          q: query,
          after: after,
          before: before,
        }
        urls.settings_user_audit_log_results_path(options)
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
          per_page: 15,
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
