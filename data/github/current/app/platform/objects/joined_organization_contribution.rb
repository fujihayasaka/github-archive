# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class JoinedOrganizationContribution < Objects::Base
      visibility :under_development

      scopeless_tokens_as_minimum

      implements Interfaces::Contribution

      description "Represents a user joining an organization on GitHub."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        !object.restricted?
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        !object.restricted?
      end

      field :organization, Organization, null: false,
        description: "The organization that the user joined."
    end
  end
end
