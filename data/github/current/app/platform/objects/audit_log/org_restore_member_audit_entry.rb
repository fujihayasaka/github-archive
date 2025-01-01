# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgRestoreMemberAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.restore_member event."

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

        implements_node_with_document_id(prefix: "ORSMAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :restored_memberships, [Platform::Unions::AuditLog::OrgRestoreMemberAuditEntryMembership], null: true, description: "Restored organization membership objects.", deprecated: Helpers::AuditLog::DeprecationNotice
        def restored_memberships
          # Restored memberships start out as raw hashes and we need to return
          # a AuditEntry like interface for the union interfaces to be able to
          # access this data.
          @object.get(:restored_memberships).compact.collect do |membership|
            ::Audit::Elastic::Hit.new(membership)
          end
        end

        field :restored_memberships_count, Integer, null: true, description: "The number of restored memberships.", deprecated: Helpers::AuditLog::DeprecationNotice
        def restored_memberships_count
          @object.get(:restored_memberships_count)
        end

        field :restored_repositories_count, Integer, null: true, description: "The number of repositories of the restored member.", deprecated: Helpers::AuditLog::DeprecationNotice
        def restored_repositories_count
          @object.get(:restored_repos_count)
        end

        field :restored_issue_assignments_count, Integer, null: true, description: "The number of issue assignments for the restored member.", deprecated: Helpers::AuditLog::DeprecationNotice
        def restored_issue_assignments_count
          @object.get(:restored_issue_assignments_count)
        end

        field :restored_repository_watches_count, Integer, null: true, description: "The number of watched repositories for the restored member.", deprecated: Helpers::AuditLog::DeprecationNotice
        def restored_repository_watches_count
          @object.get(:restored_repo_watches_count)
        end

        field :restored_repository_stars_count, Integer, null: true, description: "The number of starred repositories for the restored member.", deprecated: Helpers::AuditLog::DeprecationNotice
        def restored_repository_stars_count
          @object.get(:restored_repo_stars_count)
        end

        field :restored_custom_email_routings_count, Integer, null: true, description: "The number of custom email routings for the restored member.", deprecated: Helpers::AuditLog::DeprecationNotice
        def restored_custom_email_routings_count
          @object.get(:restored_custom_email_routings_count)
        end
      end
    end
  end
end
