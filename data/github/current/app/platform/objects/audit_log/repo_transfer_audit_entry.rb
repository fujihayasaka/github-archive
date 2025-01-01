# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class RepoTransferAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a repo.transfer event."

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

        implements_node_with_document_id(prefix: "RTAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::RepositoryAuditEntryData

        field :owner_name, String, null: true, description: "The name of the owner of the repository"
        def owner_name
          @object.get :owner
        end

        field :owner_is_org, Boolean, null: true, description: "The owner of the repository is a organization"
        def owner_is_org
          @object.get :owner_is_org
        end

        field :owner_name_was, String, null: true, description: "The name of the former owner of the repository"
        def owner_name_was
          @object.get :old_user
        end

        field :owner_was_org, Boolean, null: true, description: "The former owner of the repository was a organization"
        def owner_was_org
          @object.get :owner_was_org
        end

        field :repository_name_was, String, null: true, description: "The former name of the repository"
        def repository_name_was
          if @object.get(:repo_was).present?
            @object.get(:repo_was)
          elsif @object.get(:old_user).present?
            # Try to generate former name by substituting the current owner name
            # with the former owner, assumes repo name has not changed.
            @object.get(:repo).sub(/\A[A-Za-z0-9]+(-[A-Za-z0-9]+)*\//, "#{@object.get(:old_user)}/")
          end
        end

        # internal only

        field :owner_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the owner of the repository"
        def owner_database_id
          @object.get :owner_id
        end

        field :owner_database_id_was, Integer, null: true, visibility: :internal, description: "The database ID of the former owner of the repository"
        def owner_database_id_was
          @object.get :old_user_id
        end
      end
    end
  end
end
