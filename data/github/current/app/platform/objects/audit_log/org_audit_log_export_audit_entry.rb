# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgAuditLogExportAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.audit_log_export"

        visibility :under_development
        minimum_accepted_scopes ["read:user", "admin:org", "admin:enterprise"]

        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, audit_entry)
          permission.async_api_can_access_audit_entry?(audit_entry)
        end

        # Determine whether the viewer can see this object (called internally).
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_viewer_can_see?(permission, audit_entry)
          permission.async_viewer_can_see_audit_entry?(audit_entry)
        end

        implements_node_with_document_id(prefix: "OALEAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :total_entries, Integer, null: true, description: "The total number of Audit Log entries that were exported."
        def total_entries
          @object.get(:total_entries)
        end

        field :query, String, null: true, description: "The search query used to filter Audit Log entries for export."
        def query
          @object.get(:phrase)
        end
      end
    end
  end
end
