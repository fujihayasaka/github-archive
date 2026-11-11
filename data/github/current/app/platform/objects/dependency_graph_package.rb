# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DependencyGraphPackage < Platform::Objects::Base
      description "A package"


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
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      field :package_id, String, "The internal dependency graph ID", method: :id, null: true

      field :name, String, "The package name", null: true

      field :package_manager, String, "The package manager enum value", null: true

      field :repository_id, Integer, "The repository of package if it exists on GitHub", null: true

      field :package_manager_human_name, String, "The human name of the package manager", null: true

      field :repository_dependents_count, Integer, "The number of repositories that depend on this package", null: true

      field :package_dependents_count, Integer, "The number of packages that depend on this package", null: true

      field :dependents, [Platform::Objects::DependencyGraphDependent, null: true], description: "A list of package dependents", null: true

      field :dependents_page_info, GraphQL::Types::Relay::PageInfo, description: "Information about dependents field pagination", null: true

      field :debug_association_explanation, String, "Explanation for value of debug_should_be_associated_to_repo", null: true

      field :debug_should_be_associated_to_repo, Boolean, "True if the package is associated to the repo, false otherwise.", null: true
    end
  end
end
