# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgAddBillingManagerAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.add_billing_manager"

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

        implements_node_with_document_id(prefix: "OABMAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :invitation_email, String, null: true, description: "The email address used to invite a billing manager for the organization."
        def invitation_email
          @object.get(:invitation_email)
        end
      end
    end
  end
end
