# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class TeamRenameAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a team.rename event."

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

        implements_node_with_document_id(prefix: "TRAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData
        implements Platform::Interfaces::AuditLog::TeamAuditEntryData

        field :name_was, String, null: true, description: "The former name of the team.", deprecated: Helpers::AuditLog::DeprecationNotice
        def name_was
          @object.get :name_was
        end

        field :is_ldap_mapped, Boolean, null: true, description: "Whether the team was mapped to an LDAP Group.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_ldap_mapped
          !!@object.get(:ldap_mapped)
        end
      end
    end
  end
end
