# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class RepoEnableAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a repo.enable event."

        visibility :internal
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

        implements_node_with_document_id(prefix: "REAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::RepositoryAuditEntryData

        field :visibility, Enums::RepositoryPrivacy, null: true, description: "The visibility of the repository"
        def visibility
          @object.get(:visibility)
        end
      end
    end
  end
end
