# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackageTag < Platform::Objects::Base
      model_name "Registry::Tag"
      description "A version tag contains the mapping between a tag name and a version."

      minimum_accepted_scopes ["read:packages"]
      visibility :public, environments: [:enterprise, :dotcom]

      implements_node templates: [[:rpt, :repo_id, :package_tag_id]], as: "PT", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |package_tag|
        package_tag.async_package.then do |package|
          {
            prefix: :rpt,
            repo_id: package.repository_id,
            package_tag_id: package_tag.id
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, tag)
        tag.async_package_version.then do |package_version|
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

      field :name, String, "Identifies the tag name of the version.", null: false
      field :version, PackageVersion, description: "Version that the tag is associated with.", null: true

      def version
        @object.async_package_version.then do |version|
          version.deleted? ? nil : version
        end
      end
    end
  end
end
