# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class AuditLogJson < Resolvers::Base
      include AuditLogHelper

      type Connections.define(Platform::Objects::AuditLog::JsonAuditEntry), null: false

      argument :query, String, "The query string to filter audit entries.", required: false, default_value: nil
      argument :order_by, Inputs::AuditLogOrder, "Ordering options for the returned audit log entries.", required: false,
        default_value: { field: "timestamp", direction: "DESC" }

      def resolve(query:, order_by:)
        unless Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to view audit logs.")
        end

        payload = GitHub.guarded_audit_log_staff_actor_entry(context[:viewer])
        if query
          GitHub.instrument("staff.search_audit_log", payload.merge(query: query))
        else
          GitHub.instrument("staff.view_audit_log", payload)
        end

        Audit::Driftwood::Query.new_stafftools_query(
          phrase: query,
          direction: order_by[:direction],
          current_user: context[:viewer],
        )
      end
    end
  end
end
