# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ViewerCopilotCodingAgentEligibility < Platform::Objects::Base
      visibility :internal

      description "Information about the viewer's eligibility to request or enable Copilot coding agent for the repository."

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

      field :has_requested_cca, Boolean, null: false, description: "Whether the viewer has requested Copilot coding agent access."

      sig { returns(T::Boolean) }
      def has_requested_cca
        checker.viewer_has_requested_swe_agent?
      end

      field :can_request_cca, Boolean, null: false, description: "Whether the viewer can request Copilot coding agent access."

      sig { returns(T::Boolean) }
      def can_request_cca
        checker.viewer_can_request_swe_agent?
      end

      field :can_grant_org_cca, Boolean, null: false, description: "Whether the viewer can grant organization-level Copilot coding agent access."

      sig { returns(T::Boolean) }
      def can_grant_org_cca
        checker.viewer_can_grant_org_swe_agent?
      end

      field :can_grant_enterprise_cca, Boolean, null: false, description: "Whether the viewer can grant enterprise-level Copilot coding agent access."

      sig { returns(T::Boolean) }
      def can_grant_enterprise_cca
        checker.viewer_can_grant_enterprise_swe_agent?
      end

      private

      sig { returns(CopilotSweAgent::RepoEligibilityChecker) }
      def checker
        @checker ||= T.let(
          CopilotSweAgent::RepoEligibilityChecker.new(@object[:repository], @context[:viewer]),
          T.nilable(CopilotSweAgent::RepoEligibilityChecker)
        )
      end
    end
  end
end
