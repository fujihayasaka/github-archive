# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackageMetadatum < Platform::Objects::Base
      model_name "Registry::Metadatum"
      description "Arbitrary metadata about a specific package version."

      visibility :internal
      minimum_accepted_scopes ["read:packages"]

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
        object.async_package_version.then do |package_version|
          package_version.async_package.then do |package|
            permission.typed_can_see?("Package", package)
          end
        end
      end

      field :name, String, "The name for this metadatum.", null: false
      field :value, String, "The value for this metadatum.", null: false

      def value
        GitHub::Encoding.try_guess_and_transcode(object.value.to_s)
      end

      field :package_version, PackageVersion, method: :async_package_version, description: "The package version this metadatum describes.", null: true
    end
  end
end
