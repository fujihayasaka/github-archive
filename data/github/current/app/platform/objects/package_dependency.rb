# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackageDependency < Platform::Objects::Base
      model_name "Registry::Dependency"
      description "A package dependency contains the information needed to satisfy a dependency."

      visibility :internal
      minimum_accepted_scopes ["read:packages"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, dependency)
        dependency.async_package_version.then do |package_version|
          permission.typed_can_access?("PackageVersion", package_version)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_package_version.then do |version|
          version.async_package.then do |package|
            permission.typed_can_see?("Package", package)
          end
        end
      end

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the PackageDependency object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :name, String, "Identifies the name of the dependency.", null: false
      field :version, String, "Identifies the version of the dependency.", null: false
      field :dependency_type, Enums::PackageDependencyType, "Identifies the type of dependency.", null: false
    end
  end
end
