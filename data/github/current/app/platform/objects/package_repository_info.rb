# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackageRepositoryInfo < Platform::Objects::Base
      description "A subset of Repository attributes for internal use only from the registry service."

      visibility :internal
      minimum_accepted_scopes ["read:packages"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Package", object)
      end

      field :id, ID, description: "The global id of the repository associated with this package.", null: false
      field :database_id, Integer, description: "The database id of the repository associated with this package.", null: false
      field :organization_database_id, Integer, description: "The database id of the organization that the repository associated with this package belongs to, if any.", null: true
      field :name_with_owner, String, description: "The nwo of the repository associated with this package.", null: false
      field :visibility, Enums::RepositoryVisibility, "The associated repository's visibility level.", null: false
      field :owner_id, ID, description: "The global id of the owner of the repository associated with this package.", null: false
      field :owner_database_id, Integer, description: "The database id of the owner of the repository associated with this package.", null: false
      field :owner_login, String, description: "The login of the owner of the repository associated with this package.", null: false
      field :owner_type, String, description: "The type of the owner of the repository associated with this package, 'User' or 'Organization'.", null: false
      field :parent_id, ID, description: "The global id of the parent of the repository associated with this package.", null: true
      field :parent_database_id, Integer, description: "The database id of the parent of the repository associated with this package.", null: true

      def id
        @object.async_repository.then do |repo|
          next 0 unless repo
          repo.global_relay_id
        end
      end

      def database_id
        @object.repository_id
      end

      def organization_database_id
        @object.async_repository.then do |repo|
          next nil unless repo
          repo.organization_id
        end
      end

      def name_with_owner
        @object.async_repository.then do |repo|
          next "" unless repo
          repo.async_organization.then do |org|
            next "" unless org
            repo.name_with_display_owner
          end
        end
      end

      def visibility
        @object.async_repository.then do |repo|
          next "PRIVATE" unless repo
          repo.async_visibility
        end
      end

      def owner_id
        @object.async_repository.then do |repo|
          next unless repo
          repo.async_owner.then do |owner|
            next unless owner
            owner.global_relay_id
          end
        end
      end

      def owner_database_id
        @object.async_repository.then do |repo|
          next unless repo
          repo.owner_id
        end
      end

      def owner_login
        @object.async_repository.then do |repo|
          next "" unless repo
          repo.async_owner.then do |owner|
            next "" unless owner
            owner.display_login
          end
        end
      end

      def owner_type
        @object.async_repository.then do |repo|
          next "" unless repo
          repo.async_owner.then do |owner|
            next "" unless owner
            case owner
            when ::Organization
              "Organization"
            when ::User
              "User"
            else
              "Unknown"
            end
          end
        end
      end

      def parent_id
        @object.async_repository.then do |repo|
          next unless repo
          repo.async_parent.then do |parent|
            next unless parent
            parent.global_relay_id
          end
        end
      end

      def parent_database_id
        @object.async_repository.then do |repo|
          next unless repo
          repo.parent_id
        end
      end
    end
  end
end
