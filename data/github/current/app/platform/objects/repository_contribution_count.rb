# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryContributionCount < Objects::Base
      visibility :under_development

      scopeless_tokens_as_minimum

      description "A repository with a count of all contributions made to it"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # No special API permissions
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :contribution_count, Integer,
        description: "The count of the contributions to the repository",
        method: :count, null: false

      field :repository, Objects::Repository, "The associated repository.", null: false

      def repository
        Loaders::ActiveRecord.load(::Repository, @object.id)
      end
    end
  end
end
