# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class CreatePackageFile < Platform::Mutations::Base

      include Platform::Mutations::PackagesPrerequisites

      description "Adds a package file to a package version"
      visibility :internal
      minimum_accepted_scopes ["write:packages"]

      argument :version_id, ID, "The ID of the Package Version that contains the file.", required: true, loads: Objects::PackageVersion, as: :package_version
      argument :filename, String, "The Package file name.", required: true
      argument :size, Int, "Content length of the file.", required: true
      argument :sha1, String, "The shasum of this package file.", required: false
      argument :sha256, String, "The sha256 of this package file.", required: false
      argument :md5, String, "MD5 checksum of this package file.", required: false
      argument :object_migration_state,
               Enums::PackageFileObjectMigrationState,
               "An enum indicating whether this object is migrated or not.",
               required: false

      field :package_file, Objects::PackageFile, "The package file that was created.", null: true
      field :viewer, Objects::User, "The user that created the package file.", null: true
      field :result, Objects::PackagesMutationResult, "The result of the mutation, success or failure, with user-safe details.", null: false

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, package_version:, **inputs)
        repository = package_version.package.repository
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:create_package, current_org: org, repo: repository, allow_user_via_granular_actor: true, allow_integrations: true)
        end
      end

      def resolve(package_version:, **inputs)
        raise Errors::NotFound.new("Could not resolve to a node with the global id of '#{version_id}'.") if package_version.deleted?

        result = check_repository_prerequisites(
          repository: package_version.package.repository,
          actor: context[:viewer],
          storage_requested: [inputs[:size], 1].max,
        )
        unless result[:success]
          return {
            package_file: nil,
            viewer: context[:viewer],
            result: result,
          }
        end

        if package_version.files.exists?(filename: inputs[:filename])
          return {
            package_file: nil,
            viewer: context[:viewer],
            result: {
              success: false,
              user_safe_status: :conflict,
              user_safe_message: "A file named \"#{inputs[:filename]}\" already exists on package \"#{package_version.package.name}\" with version \"#{package_version.version}\".",
              error_type: "file_exists",
              validation_errors: [],
            },
          }
        end

        package_file = package_version.files.build(filename: inputs[:filename])
        package_file.state = :starter
        package_file.size = inputs[:size] if inputs[:size].present?
        package_file.sha1 = inputs[:sha1] if inputs[:sha1].present?
        package_file.sha256 = inputs[:sha256] if inputs[:sha256].present?
        package_file.md5 = inputs[:md5] if inputs[:md5].present?
        if inputs[:object_migration_state].present?
          package_file.object_migration_state = inputs[:object_migration_state]
        end

        if package_file.save
          {
            package_file: package_file,
            viewer: context[:viewer],
            result: {
              success: true,
              user_safe_status: :created,
              user_safe_message: "Package file created.",
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
              user_safe_message: "The package file couldn't be created.",
              error_type: "validation",
              validation_errors: Platform::UserErrors.mutation_errors_for_model(package_file),
            },
          }
        end
      end
    end
  end
end
