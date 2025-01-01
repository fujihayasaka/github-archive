# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgCreateAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.create event."

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

        implements_node_with_document_id(prefix: "OCAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :billing_plan, Platform::Enums::AuditLog::OrgCreateAuditEntryBillingPlan, null: true, description: "The billing plan for the Organization."
        def billing_plan
          @object.get(:plan)
        end

        field :terms_of_service_sha, String, null: true, visibility: :internal, description: "The SHA hash value for the terms of service when the organization was created."
        def terms_of_service_sha
          @object.get(:tos_sha)
        end
      end
    end
  end
end
