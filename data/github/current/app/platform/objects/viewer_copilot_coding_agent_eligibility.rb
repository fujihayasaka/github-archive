# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ViewerCopilotCodingAgentEligibility < Platform::Objects::Base
      docs_category :copilot
      visibility :internal

      description "Information about the viewer's eligibility to request or enable Copilot cloud agent for the repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, object: T.untyped).returns(T::Boolean) }
      def self.async_api_can_access?(permission, object)
        # This is only called internally as a field in the Repository object
        # and visibility is pre-checked on the Repository object itself.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, object: T.untyped).returns(T::Boolean) }
      def self.async_viewer_can_see?(permission, object)
        # This is only called internally as a field in the Repository object
        # and visibility is pre-checked on the Repository object itself.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # NOTE: This object is deprecated and all fields return false as default values.
      # We are keeping the type in the schema to avoid breaking older clients that may
      # still query these fields. Once usage drops to zero, this type can be removed entirely.

      field :has_requested_cca, Boolean, null: false, description: "Whether the viewer has requested Copilot cloud agent access."

      sig { returns(T::Boolean) }
      def has_requested_cca
        false
      end

      field :can_request_cca, Boolean, null: false, description: "Whether the viewer can request Copilot cloud agent access."

      sig { returns(T::Boolean) }
      def can_request_cca
        false
      end

      field :can_grant_org_cca, Boolean, null: false, description: "Whether the viewer can grant organization-level Copilot cloud agent access."

      sig { returns(T::Boolean) }
      def can_grant_org_cca
        false
      end

      field :can_grant_enterprise_cca, Boolean, null: false, description: "Whether the viewer can grant enterprise-level Copilot cloud agent access."

      sig { returns(T::Boolean) }
      def can_grant_enterprise_cca
        false
      end
    end
  end
end
