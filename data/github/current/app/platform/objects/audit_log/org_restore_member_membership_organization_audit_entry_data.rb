# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgRestoreMemberMembershipOrganizationAuditEntryData < Platform::Objects::AuditLog::Base
        description "Metadata for an organization membership for org.restore_member actions"

        minimum_accepted_scopes ["admin:org", "admin:enterprise"]

        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, audit_entry)
          # Access to this object is managed by its parent OrgRestoreMemberAuditEntry.
          true # rubocop:disable GitHub/GraphqlApiAuthorization
        end

        # Determine whether the viewer can see this object (called internally).
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_viewer_can_see?(permission, audit_entry)
          # Access to this object is managed by its parent OrgRestoreMemberAuditEntry.
          true # rubocop:disable GitHub/GraphqlApiAuthorization
        end

        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData
      end
    end
  end
end
