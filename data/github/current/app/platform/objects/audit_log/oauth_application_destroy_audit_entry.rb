# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OauthApplicationDestroyAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a oauth_application.destroy"

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

        implements_node_with_document_id(prefix: "OADAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OauthApplicationAuditEntryData
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :is_full_trust, Boolean, null: true, visibility: :internal, description: "Whether this was a full trust OAuth application.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_full_trust
          @object.get(:full_trust) == "true"
        end

        field :rate_limit, Integer, null: true, description: "The rate limit of the OAuth application.", deprecated: Helpers::AuditLog::DeprecationNotice
        def rate_limit
          @object.get(:rate_limit)
        end

        field :state, Platform::Enums::AuditLog::OauthApplicationDestroyAuditEntryState, null: true, description: "The state of the OAuth application.", deprecated: Helpers::AuditLog::DeprecationNotice
        def state
          state_key = @object.get(:state)
          ::OauthApplication.states.invert[state_key]
        end

        field :callback_url, Platform::Scalars::URI, null: true, description: "The callback URL of the OAuth application.", deprecated: Helpers::AuditLog::DeprecationNotice
        def callback_url
          @object.get(:callback_url)
        end

        field :application_url, Platform::Scalars::URI, null: true, description: "The application URL of the OAuth application.", deprecated: Helpers::AuditLog::DeprecationNotice
        def application_url
          @object.get(:application_url)
        end
      end
    end
  end
end
