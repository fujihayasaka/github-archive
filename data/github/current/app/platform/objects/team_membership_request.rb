# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TeamMembershipRequest < Platform::Objects::Base
      description "Membership requests for a team."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_team.then { |team| permission.typed_can_see?("Team", team) }
      end

      visibility :internal

      minimum_accepted_scopes ["read:org"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the TeamMembershipRequest object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :requester, User, method: :async_requester, description: "User requesting membership.", null: true
    end
  end
end
