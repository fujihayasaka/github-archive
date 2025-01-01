# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgUnblockUserAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.unblock_user"

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

        implements_node_with_document_id(prefix: "OUUAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :blocked_user_name, String, null: true, description: "The username of the blocked user.", deprecated: Helpers::AuditLog::DeprecationNotice
        def blocked_user_name
          @object.get(:blocked_user)
        end

        field :blocked_user_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the blocked user.", deprecated: Helpers::AuditLog::DeprecationNotice
        def blocked_user_database_id
          @object.get(:blocked_user_id)
        end

        field :blocked_user, Platform::Objects::User, null: true, description: "The user being unblocked by the organization.", deprecated: Helpers::AuditLog::DeprecationNotice
        def blocked_user
          Loaders::ActiveRecord.load(::User, @object.get(:blocked_user_id))
        end

        url_fields prefix: :blocked_user, null: true, description: "The HTTP URL for the blocked user.", deprecated: Helpers::AuditLog::DeprecationNotice do |audit_entry|
          Loaders::ActiveRecord.load(::User, audit_entry.get(:blocked_user_id)).then do |blocked_user|
            blocked_user&.permalink(include_host: false)
          end
        end

        field :is_spammy, Boolean, null: true, visibility: :internal, description: "Whether the blocking User or Organization was marked spammy.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_spammy
          !!@object.get(:spammy)
        end
      end
    end
  end
end
