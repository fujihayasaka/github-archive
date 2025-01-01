# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DependencyGraphDependency < Platform::Objects::Base
      extend T::Helpers

      description "A dependency manifest entry"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # This is public on dotcom, but internal on enterprise.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      minimum_accepted_scopes ["public_repo"]

      visibility :public

      field :package_id, ID, "The dependency graph package ID", null: true, visibility: :internal

      field :package_name, String, "The name of the package in the canonical form used by the package manager.", null: false

      field :package_label, String, "The original name of the package, as it appears in the manifest.", null: false do
        T.bind(self, Platform::Objects::Base::Deprecated)

        deprecated(
          start_date: Date.new(2022, 6, 8),
          reason: "`packageLabel` will be removed.",
          superseded_by: "Use normalized `packageName` field instead.",
          owner: "github/dependency_graph"
        )
      end

      def package_label
        # Preserve packageLabel field for backwards-compatibility, even though it is the same as packageName
        @object.package_name
      end

      field :package_manager, String, "The dependency package manager", null: true

      field :requirements, String, "The dependency version requirements", null: false

      field :human_requirements, String, "More readable dependency version requirements", null: false, visibility: :internal

      field :has_dependencies, Boolean, "Does the dependency itself have dependencies?", method: :has_dependencies?, null: false

      field :repository, Objects::Repository, description: "The repository containing the package", null: true, method: :async_repository
    end
  end
end
