# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class TeamChangePrivacyAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a team.change_privacy event."

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

        implements_node_with_document_id(prefix: "TCPAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData
        implements Platform::Interfaces::AuditLog::TeamAuditEntryData

        field :privacy, Platform::Enums::AuditLog::TeamChangePrivacyAuditEntryPrivacy, null: true, description: "The privacy setting of the team", deprecated: Helpers::AuditLog::DeprecationNotice
        def privacy
          normalized_team_privacy(@object.get(:privacy))
        end

        field :privacy_was, Platform::Enums::AuditLog::TeamChangePrivacyAuditEntryPrivacy, null: true, description: "The former privacy setting of the team", deprecated: Helpers::AuditLog::DeprecationNotice
        def privacy_was
          normalized_team_privacy(@object.get(:privacy_was))
        end

        field :is_ldap_mapped, Boolean, null: true, description: "Whether the team was mapped to an LDAP Group.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_ldap_mapped
          !!@object.get(:ldap_mapped)
        end

        private

        def normalized_team_privacy(privacy)
          if privacy == "closed"
            # We eventually plan on introducing a "open" privacy that allows any
            # org member to join the team (whereas "closed" allows any org member to
            # see the team, but they must be added by someone with admin access).
            #
            # Until we introduce "open", the "closed" visibility is misleading, so
            # we say "visible" publicly until then.
            #
            # Introduced in https://github.com/github/github/pull/50559
            "visible"
          else
            privacy
          end
        end
      end
    end
  end
end
