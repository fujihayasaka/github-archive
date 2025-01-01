# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class OrgDisableSamlAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a org.disable_saml event."

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

        implements_node_with_document_id(prefix: "ODSAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData

        field :single_sign_on_url, Scalars::URI, null: true, description: "The SAML provider's single sign-on URL.", deprecated: Helpers::AuditLog::DeprecationNotice
        def single_sign_on_url
          @object.get(:sso_url)
        end

        field :issuer_url, Scalars::URI, null: true, description: "The SAML provider's issuer URL.", deprecated: Helpers::AuditLog::DeprecationNotice
        def issuer_url
          @object.get(:issuer)
        end

        field :digest_method_url, Scalars::URI, null: true, description: "The SAML provider's digest algorithm URL.", deprecated: Helpers::AuditLog::DeprecationNotice
        def digest_method_url
          @object.get(:digest_method)
        end

        field :signature_method_url, Scalars::URI, null: true, description: "The SAML provider's signature algorithm URL.", deprecated: Helpers::AuditLog::DeprecationNotice
        def signature_method_url
          @object.get(:signature_method)
        end

        field :is_enforced, Boolean, null: true, visibility: :internal, description: "Whether the organization enforced that all new members be linked with this SAML provider.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_enforced
          @object.get(:enforced)
        end

        field :organization_created_at, Scalars::DateTime, null: true, visibility: :internal, description: "Identifies the date and time when the organization was created.", deprecated: Helpers::AuditLog::DeprecationNotice
        def organization_created_at
          @object.get(:org_created_at)
        end

        field :seats_count, Integer, null: true, visibility: :internal, description: "The number of seats the organization had.", deprecated: Helpers::AuditLog::DeprecationNotice
        def seats_count
          @object.get(:seats)
        end

        field :filled_seats_count, Integer, null: true, visibility: :internal, description: "The number of filled seats the organization had.", deprecated: Helpers::AuditLog::DeprecationNotice
        def filled_seats_count
          @object.get(:filled_seats)
        end

        field :pending_invitation_count, Integer, null: true, visibility: :internal, description: "The number of pending invitations the organization had.", deprecated: Helpers::AuditLog::DeprecationNotice
        def pending_invitation_count
          @object.get(:pending_invites)
        end

        field :reason, String, null: true, visibility: :internal, description: "A reason why SAML was disabled for this provider.", deprecated: Helpers::AuditLog::DeprecationNotice
        def reason
          @object.get(:reason)
        end
      end
    end
  end
end
