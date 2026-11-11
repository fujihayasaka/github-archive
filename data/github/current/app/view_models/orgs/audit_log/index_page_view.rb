# typed: true
# frozen_string_literal: true

module Orgs
  module AuditLog
    class IndexPageView < ::AuditLog::IndexPageView
      attr_reader :organization

      def page_title
        "Audit log"
      end

      def results_path
        options = {
          q: query,
          after: after,
          before: before,
          organization_id: organization.display_login,
          page: page,
        }
        urls.settings_org_audit_log_results_path(options)
      end

      private

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
          per_page: 15,
        }
      end
    end
  end
end
