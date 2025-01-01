# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CandidateReviewer < Platform::Objects::Base
      visibility :internal
      description "Represents a potential reviewer for a pull request returned by search"
      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true` as this is only accessible to internal users
      def self.async_api_can_access?(permission, object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true` as this is only accessible to internal users
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :reviewer, Unions::ReviewerResult, description: "The potential reviewer", null: false
    end
  end
end
