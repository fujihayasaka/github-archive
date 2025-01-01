# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class RepoTransferStartAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a repo.transfer_start event."

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

        implements_node_with_document_id(prefix: "RTSAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::RepositoryAuditEntryData

        field :requester_name, String, null: true, description: "The name of the user or organization that requested the transfer."
        def requester_name
          @object.get(:requester) || @object.get(:requester_login)
        end

        field :target_name, String, null: true, description: "The name of the user or organization that will receive the transfer request."
        def target_name
          @object.get(:target) || @object.get(:target_login)
        end

        # internal only

        field :requester_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the user or organization that requested the transfer."
        def requester_database_id
          @object.get :requester_id
        end

        field :target_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the user or organization that will receive the transfer request."
        def target_database_id
          @object.get :target_id
        end
      end
    end
  end
end
