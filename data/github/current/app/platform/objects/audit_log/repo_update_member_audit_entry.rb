# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class RepoUpdateMemberAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a repo.update_member event."

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

        implements_node_with_document_id(prefix: "RUMAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData
        implements Platform::Interfaces::AuditLog::RepositoryAuditEntryData

        url_fields prefix: :repository_member_permission, null: true, description: "The HTTP URL for the user's repository permission.", deprecated: Helpers::AuditLog::DeprecationNotice do |audit_entry|
          Promise.all([
            Loaders::ActiveRecord.load(::Organization, audit_entry.get(:org_id)),
            Loaders::ActiveRecord.load(::User, audit_entry.get(:user_id)),
            Loaders::ActiveRecord.load(::Repository, audit_entry.get(:repo_id)),
          ]).then do |org, user, repository|
            if repository
              repository.async_owner.then do |repo_owner|
                template_org = org&.display_login
                template_user = user&.display_login
                template_repository = repository&.name

                if repo_owner == org && template_org.present? && template_user.present? && template_repository.present?
                  template = Addressable::Template.new("/orgs/{org}/people/{user}/repositories/{org}/{repository}")
                  template.expand(
                    org: template_org,
                    user: template_user,
                    repository: template_repository,
                  )
                end
              end
            end
          end
        end

        field :permission, Platform::Enums::AuditLog::RepoUpdateMemberAuditEntryPermission, null: true, description: "The permission level the user has on the repository", deprecated: Helpers::AuditLog::DeprecationNotice
        def permission
          @object.get :new_permission
        end

        field :permission_was, Platform::Enums::AuditLog::RepoUpdateMemberAuditEntryPermission, null: true, description: "The former permission level the user had on the repository", deprecated: Helpers::AuditLog::DeprecationNotice
        def permission_was
          @object.get :old_permission
        end
      end
    end
  end
end
