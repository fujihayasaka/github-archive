# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackageVersionDependencies < Platform::Objects::Base
      description "A lightweight object that wraps the version to dependencies relationship. Only used internally to support the rubygems dependencies endpoint."

      visibility :internal
      minimum_accepted_scopes ["read:packages"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, version)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, version)
        version.async_package.then do |package|
          permission.typed_can_see?("Package", package)
        end
      end

      field :version, String, "Identifies the version number.", null: false

      field :dependencies, [PackageDependency], description: "All dependencies for this version", null: true

      def dependencies
        Loaders::PackageVersionDefaultDependencies.load(@object.id)
      end
    end
  end
end
