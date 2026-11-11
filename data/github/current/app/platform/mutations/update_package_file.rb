# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdatePackageFile < Platform::Mutations::Base

      include Platform::Mutations::PackagesPrerequisites

      description "Updates a package file."
      visibility :internal
      minimum_accepted_scopes ["write:packages"]

      argument :package_file_id, ID, "The package file to update.", required: true, loads: Objects::PackageFile
      argument :md5, String, "MD5 checksum of this package file.", required: false
      argument :sha1, String, "The shasum of this package file.", required: false
      argument :sha256, String, "The sha256 of this package file.", required: false
      argument :size, Int, "Content length of the file.", required: false
      argument :sri512, String, "The subresource integrity (SRI) hashed using sha512.", required: false
      argument :state, Enums::PackageFileState, "The state of this package file.", required: false
      argument :object_migration_state,
               Enums::PackageFileObjectMigrationState,
               "An enum indicating whether this object is migrated or not.",
               required: false

      field :package_file, Objects::PackageFile, "The package file that was updated.", null: true
      field :viewer, Objects::User, "The user that updated the package file.", null: true
      field :result, Objects::PackagesMutationResult, "The result of the mutation, success or failure, with user-safe details.", null: false

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, package_file:, **inputs)
        repository = package_file.package_version.package.repository
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:create_package, current_org: org, repo: repository, allow_user_via_granular_actor: true, allow_integrations: true)
        end
      end

      def resolve(package_file:, **inputs)
        raise Errors::NotFound.new("Could not resolve to a node with the global id of '#{package_file_id}'.") if package_file.package_version.deleted?

        repository = package_file.package_version.package.repository
        result = check_repository_prerequisites(repository: repository, actor: context[:viewer])
        unless result[:success]
          return {
            package_file: nil,
            viewer: context[:viewer],
            result: result,
          }
        end

        package_file.state = inputs[:state] if inputs[:state].present?
        package_file.size = inputs[:size] if inputs[:size].present?
        package_file.sha1 = inputs[:sha1] if inputs[:sha1].present?
        package_file.sha256 = inputs[:sha256] if inputs[:sha256].present?
        package_file.md5 = inputs[:md5] if inputs[:md5].present?
        package_file.sri_512 = inputs[:sri512] if inputs[:sri512].present?
        if inputs[:object_migration_state].present?
          package_file.object_migration_state = inputs[:object_migration_state]
        end

        if package_file.save
          {
            package_file: package_file,
            viewer: context[:viewer],
            result: {
              success: true,
              user_safe_status: :accepted,
              user_safe_message: "Package file updated.",
              error_type: "none",
              validation_errors: [],
            },
          }
        else
          {
            package_file: nil,
            viewer: context[:viewer],
            result: {
              success: false,
              user_safe_status: :unprocessable_entity,
              user_safe_message: "The package file couldn't be updated.",
              error_type: "validation",
              validation_errors: Platform::UserErrors.mutation_errors_for_model(package_file),
            },
          }
        end
      end
    end
  end
end
