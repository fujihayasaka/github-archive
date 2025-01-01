# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class TeamUpdateRepositoryPermissionAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a team.update_repository_permission event."

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

        implements_node_with_document_id(prefix: "TURPAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData
        implements Platform::Interfaces::AuditLog::RepositoryAuditEntryData
        implements Platform::Interfaces::AuditLog::TeamAuditEntryData

        field :permission, Platform::Enums::AuditLog::TeamUpdateRepositoryPermissionAuditEntryPermission, null: true, description: "The permission level team members have on this repository", deprecated: Helpers::AuditLog::DeprecationNotice
        def permission
          permission = @object.get(:permission)
          case permission
          when "read"
            "pull"
          when "write"
            "push"
          else
            permission
          end
        end

        field :permission_was, Platform::Enums::AuditLog::TeamUpdateRepositoryPermissionAuditEntryPermission, null: true, description: "The former permission level team members had on this repository", deprecated: Helpers::AuditLog::DeprecationNotice
        def permission_was
          old_permission = @object.get(:old_permission)
          case old_permission
          when "read"
            "pull"
          when "write"
            "push"
          else
            old_permission
          end
        end

        field :is_ldap_mapped, Boolean, null: true, description: "Whether the team was mapped to an LDAP Group.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_ldap_mapped
          !!@object.get(:ldap_mapped)
        end
      end
    end
  end
end
