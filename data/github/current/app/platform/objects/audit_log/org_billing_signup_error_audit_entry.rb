# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgBillingSignupErrorAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.billing_signup_error"

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

        implements_node_with_document_id(prefix: "OBSEAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :email, String, null: true, description: "The billing email address for the Organization."
        def email
          @object.get(:email)
        end

        field :error, String, null: true, visibility: :internal, description: "The error that occurred during the signup process."
        def error
          @object.get(:error)
        end

        field :billing_plan, Platform::Enums::AuditLog::OrgBillingSignupErrorAuditEntryBillingPlan, null: true, description: "The billing plan for the Organization."
        def billing_plan
          @object.get(:plan)
        end
      end
    end
  end
end
