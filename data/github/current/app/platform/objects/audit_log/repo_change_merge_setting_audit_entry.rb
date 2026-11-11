# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class RepoChangeMergeSettingAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a repo.change_merge_setting event."

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

        implements_node_with_document_id(prefix: "RCMSAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::RepositoryAuditEntryData
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :is_enabled, Boolean, null: true, description: "Whether the change was to enable (true) or disable (false) the merge type", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_enabled
          @object.get(:enabled)
        end

        field :merge_type, Enums::AuditLog::RepoChangeMergeSettingAuditEntryMergeType, null: true, description: "The merge method affected by the change", deprecated: Helpers::AuditLog::DeprecationNotice
        def merge_type
          @object.get :merge_type
        end
      end
    end
  end
end
