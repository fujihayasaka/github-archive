# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgCancelInvitationAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.cancel_invitation event."

        visibility :under_development
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

        implements_node_with_document_id(prefix: "OCIAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :organization_invitation, Platform::Objects::OrganizationInvitation, null: true, description: "The cancelled organization invitation.", deprecated: Helpers::AuditLog::DeprecationNotice
        def organization_invitation
          Loaders::ActiveRecord.load(::OrganizationInvitation, @object.get(:invitation_id))
        end

        field :email, String, null: true, description: "The email address of the organization invitation.", deprecated: Helpers::AuditLog::DeprecationNotice
        def email
          @object.get(:email)
        end

        field :is_spammy, Boolean, visibility: :internal, null: true, description: "Whether the inviting User or Organization was marked spammy.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_spammy
          @object.get(:spammy) == "true"
        end
      end
    end
  end
end
