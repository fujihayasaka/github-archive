# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgRemoveMemberAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.remove_member event."

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

        implements_node_with_document_id(prefix: "ORMAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :reason, Platform::Enums::AuditLog::OrgRemoveMemberAuditEntryReason, null: true, description: "The reason for the member being removed.", deprecated: Helpers::AuditLog::DeprecationNotice
        def reason
          @object.get(:reason)
        end

        field :human_reason, String, null: true, visibility: :internal, description: "A descriptive reason for the member being removed.", deprecated: Helpers::AuditLog::DeprecationNotice
        def human_reason
          key = @object.get(:reason)
          Platform::Enums::AuditLog::OrgRemoveMemberAuditEntryReason::REASONS[key]
        end

        field :membership_types, [Platform::Enums::AuditLog::OrgRemoveMemberAuditEntryMembershipType], null: true, description: "The types of membership the member has with the organization.", deprecated: Helpers::AuditLog::DeprecationNotice
        def membership_types
          @object.get(:membership_types)
        end
      end
    end
  end
end
