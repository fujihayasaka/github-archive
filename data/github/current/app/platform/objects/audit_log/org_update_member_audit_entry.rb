# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgUpdateMemberAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.update_member event."

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

        implements_node_with_document_id(prefix: "OUMAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :permission, Platform::Enums::AuditLog::OrgUpdateMemberAuditEntryPermission, null: true, description: "The new member permission level for the organization.", deprecated: Helpers::AuditLog::DeprecationNotice
        def permission
          @object.get(:permission)
        end

        field :permission_was, Platform::Enums::AuditLog::OrgUpdateMemberAuditEntryPermission, null: true, description: "The former member permission level for the organization.", deprecated: Helpers::AuditLog::DeprecationNotice
        def permission_was
          @object.get(:old_permission)
        end
      end
    end
  end
end
