# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseContribution < Objects::Base

      scopeless_tokens_as_minimum
      visibility :internal

      implements Interfaces::Contribution

      description "Represents an enterprise contribution a user made on GitHub."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, contrib)
        permission.access_allowed?(:v4_read_user_private, user: permission.viewer, resource: contrib.user, current_repo: nil, current_org: nil, allow_integration: false, allow_user_via_granular_actor: false, allow_integrations: false)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, contrib)
        permission.belongs_to_viewer(contrib.associated_subject)
      end
    end
  end
end
