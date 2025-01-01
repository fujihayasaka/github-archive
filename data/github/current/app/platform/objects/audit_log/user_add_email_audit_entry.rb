# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class UserAddEmailAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a user.add_email event."

        visibility :under_development
        minimum_accepted_scopes ["read:user", "admin:enterprise"]


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

        implements_node_with_document_id(prefix: "UAEAE")
        implements Platform::Interfaces::AuditLog::AuditEntry

        field :email, String, null: true, description: "The added email address"
        def email
          @object.get :email
        end
      end
    end
  end
end
