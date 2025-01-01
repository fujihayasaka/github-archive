# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgRemoveOutsideCollaboratorAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.remove_outside_collaborator event."

        minimum_accepted_scopes ["admin:org", "admin:enterprise"]


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

        implements_node_with_document_id(prefix: "OROCAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :reason, Platform::Enums::AuditLog::OrgRemoveOutsideCollaboratorAuditEntryReason, null: true, description: "The reason for the outside collaborator being removed from the Organization."
        def reason
          @object.get(:reason)
        end

        field :human_reason, String, null: true, visibility: :internal, description: "A descriptive reason for the outside collaborator being removed from the Organization."
        def human_reason
          Platform::Enums::AuditLog::OrgRemoveOutsideCollaboratorAuditEntryReason::REASONS[@object.get(:reason)]
        end

        field :membership_types, [Platform::Enums::AuditLog::OrgRemoveOutsideCollaboratorAuditEntryMembershipType], null: true, description: "The types of membership the outside collaborator has with the organization."
        def membership_types
          Array(@object.get(:membership_types))
        end
      end
    end
  end
end
