# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class ProjectCreateAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a project.create"

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

        implements_node_with_document_id(prefix: "PCAE")
        implements Platform::Interfaces::AuditLog::AuditEntry

        field :project_name, String, null: false, description: "The name of the new project."
        def project_name
          @object.get :project
        end

        field :project_database_id, Integer, null: false, description: "The database ID of the project."
        def project_database_id
          @object.get :project_id
        end
      end
    end
  end
end
