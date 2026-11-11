# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class CreatePackageVersion < Platform::Mutations::Base

      include Platform::Mutations::PackagesPrerequisites

      class DuplicatePackageError < StandardError
        attr_reader :cause

        def initialize(cause)
          @cause = cause
          super()
        end
      end

      class DuplicateVersionError < StandardError; end
      class VersionValidationError < StandardError; end
      class WrongRepositoryError < StandardError; end

      class ModelValidationError < StandardError
        attr_reader :model

        def initialize(model)
          @model = model
          super
        end
      end

      description "Adds a version to a package"
      visibility :internal
      minimum_accepted_scopes ["write:packages"]

      argument :repository_name_with_owner, String, "The nameWithOwner of the repository that contains the package.", required: true, loads: Objects::Repository
      argument :package_type, Enums::PackageType, "The registry package type for the package to associate the package version with.", required: true
      argument :package_name, String, "The registry package name to associate the package version with.", required: true
      argument :version, String, "The version string for this package version.", required: true
      argument :platform, String, "The platform the package is built for.", required: true
      argument :pre_release, Boolean, "Whether or not the package version is a prerelease", required: false, default_value: false
      argument :commit_oid, String, "The Commit OID of this package version.", required: false
      argument :tag_name, String, "Identifies the git tag of the release.", required: false
      argument :validate_tag_name, Boolean, "Fails the mutation if no Release with the given tag name exists.", required: false
      argument :sha256, String, "The sha256 checksum of this package version.", required: false
      argument :size, Integer, "The size of this package version.", required: false
      argument :package_file_sha256s, [String, null: true], "An array of sha256s which identifies package_files to add to this version", required: false

      field :package_version, Objects::PackageVersion, "The new registry package version.", null: true
      field :viewer, Objects::User, "The user that created the package version.", null: true
      field :result, Objects::PackagesMutationResult, "The result of the mutation, success or failure, with user-safe details.", null: false

      def load_repository_name_with_owner(name_with_owner)
        login, name = name_with_owner.split("/")
        Platform::Helpers::RepositoryByNwo.async_repository_with_owner(
          permission: context[:permission],
          viewer: context[:viewer],
          login: login,
          name: name,
          follow_repo_redirect: false,
        ).then do |repo|
          context[:permission].typed_can_access?("Repository", repo).then do |accessible|
            unless accessible
              raise Platform::Errors::NotFound.new("Could not resolve to a Repository with the name '#{name_with_owner}'.")
            end
            context[:permission].typed_can_see?("Repository", repo).then do |readable|
              if !readable || repo.hide_from_user?(context[:permission].viewer)
                raise Platform::Errors::NotFound.new("Could not resolve to a Repository with the name '#{name_with_owner}'.")
              end
            end

            repo
          end
        end
      end

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository_name_with_owner:, **inputs)
        permission.async_owner_if_org(repository_name_with_owner).then do |org|
          permission.access_allowed?(:create_package, current_org: org, repo: repository_name_with_owner, allow_user_via_granular_actor: true, allow_integrations: true)
        end
      end

      def resolve(repository_name_with_owner:, **inputs)
        GitHub.dogstats.time "packages.create_package_version.resolve" do
          repository = repository_name_with_owner

          result = check_repository_prerequisites(
            repository: repository,
            actor: context[:viewer],
            storage_requested: inputs[:size] || 1,
            feature_flags: [],
          )
          unless result[:success]
            return {
              package: nil,
              viewer: context[:viewer],
              result: result,
            }
          end

          package = find_package(inputs, repository)

          if package.nil?
            package = repository.packages.build(
              name: inputs[:package_name],
              registry_package_type: inputs[:package_type].to_s.downcase,
              package_type: inputs[:package_type],
            )
          end

          package_files = []
          unless inputs[:package_file_sha256s].blank?
            package_files = Loaders::PackageFiles.with_sha256s(inputs[:package_file_sha256s], repository.id)
            found_package_files = package_files.map(&:sha256).flatten
            missing_package_files = inputs[:package_file_sha256s] - found_package_files
            unless missing_package_files.blank?
              return {
                package_version: nil,
                viewer: context[:viewer],
                result: {
                  success: false,
                  user_safe_status: :unprocessable_entity,
                  user_safe_message: "No matching package_file with sha256 \"#{missing_package_files[0]}\" found in repository \"#{repository.name_with_display_owner}\".",
                  error_type: "validation",
                  validation_errors: [],
                },
              }
            end
          end

          release_id = nil
          if inputs[:tag_name].present?
            release_id = repository.releases.where(tag_name: inputs[:tag_name]).limit(1).pluck(:id).first
            if inputs[:validate_tag_name] && release_id.nil?
              return {
                package_version: nil,
                viewer: context[:viewer],
                result: {
                  success: false,
                  user_safe_status: :unprocessable_entity,
                  user_safe_message: "No release with tag named \"#{inputs[:tag_name]}\" exists for the repository.",
                  error_type: "validation",
                  validation_errors: [],
                },
              }
            end
          end

          package_version = Registry::PackageVersion.new(
            version: inputs[:version],
            release_id: release_id,
            platform: inputs[:platform],
            sha256: inputs[:sha256],
            size: inputs[:size],
            commit_oid: inputs[:commit_oid],
            author: context[:viewer],
            pre_release: inputs[:pre_release],
            published_via_actions: Platform::Helpers::ViaActions.request_via_actions?(context: context),
          )

          begin
            return create_version_with_package(package, package_version, package_files)
          rescue DuplicatePackageError => e
            # There's a potential race condition with multiple versions created concurrently,
            # so attempt to find the package that was created first and try again.
            unless package = find_package(inputs, repository)
              Failbot.report(e.cause) # This shouldn't occur, so let's log it.
              return {
                package_version: nil,
                viewer: context[:viewer],
                result: {
                  success: false,
                  user_safe_status: :unprocessable_entity,
                  user_safe_message: "Package \"#{inputs[:package_name]}\" already exists.",
                  error_type: "package_exists",
                  validation_errors: [],
                },
              }
            end

            begin
              return create_version_with_package(package, package_version, package_files)
            rescue DuplicateVersionError
              return {
                package_version: nil,
                viewer: context[:viewer],
                result: duplicate_version_result(inputs[:version], inputs[:platform]),
              }
            end
          rescue DuplicateVersionError
            return {
              package_version: nil,
              viewer: context[:viewer],
              result: duplicate_version_result(inputs[:version], inputs[:platform]),
            }
          end
        end
      rescue WrongRepositoryError
        {
          package_version: nil,
          viewer: context[:viewer],
          result: {
            success: false,
            user_safe_status: :unprocessable_entity,
            user_safe_message: "Package \"#{inputs[:package_name]}\" is already associated with another repository.",
            error_type: "wrong_repository",
            validation_errors: [],
          },
        }
      rescue ModelValidationError => err
        {
          package_version: nil,
          viewer: context[:viewer],
          result: {
            success: false,
            user_safe_status: :unprocessable_entity,
            user_safe_message: "The package version couldn't be published.",
            error_type: "validation",
            validation_errors: Platform::UserErrors.mutation_errors_for_model(err.model),
          },
        }
      end

      private

      def duplicate_version_result(version, platform)
        {
          success: false,
          user_safe_status: :unprocessable_entity,
          user_safe_message: "Version \"#{version}\"#{" on platform \"#{platform}\"" unless platform.blank?} already exists on the package.",
          error_type: "version_exists",
          validation_errors: [],
        }
      end

      def find_package(inputs, repository)
        package = ::Platform::Helpers::PackageQuery.get_package(
          inputs.merge(owner: repository.owner.login, registry_package_type: inputs[:package_type].to_s.downcase),
          context,
        )

        return unless package

        if !package.active?
          # If a package is inactive (i.e. no latest version or all versions
          # are deleted), rename the package to avoid conflict and create a
          # new one using the arguments in this mutation.
          # The renamed package will be destroyed once its retention period
          # expires
          package.original_name = package.name
          package.name = "deleted_#{SecureRandom.uuid}"
          package.save!
          nil
        elsif package.repository.global_relay_id != repository.global_relay_id
          # Make sure this package doesn't exist under a different repository, for the same owner.
          raise WrongRepositoryError.new # rubocop:disable GitHub/UsePlatformErrors
        else
          package
        end
      end

      # Raises exceptions on validation errors to roll back the transaction.
      def create_version_with_package(package, package_version, package_files)
        Registry::PackageVersion.transaction do
          begin
            unless package.persisted? || package.save
              raise ModelValidationError.new(package) # rubocop:disable GitHub/UsePlatformErrors
            end
          rescue ActiveRecord::RecordNotUnique => e
            raise DuplicatePackageError.new(e) # rubocop:disable GitHub/UsePlatformErrors
          end

          begin
            package.package_versions << package_version
            unless package_version.save
              raise VersionValidationError.new(version) # rubocop:disable GitHub/UsePlatformErrors
            end
          rescue ActiveRecord::RecordNotUnique
            current_version = package.package_versions.find_by(version: package_version.version)
            if current_version.deleted?
              current_version.version = "deleted_#{SecureRandom.uuid}"
              current_version.save
              package_version.save
            else
              raise DuplicateVersionError.new # rubocop:disable GitHub/UsePlatformErrors
            end
          end

          package_files.each do |package_file|
            package_version.files << package_file
            unless package_version.save
              raise ModelValidationError.new(version) # rubocop:disable GitHub/UsePlatformErrors
            end
          end

          {
            package_version: package_version,
            viewer: context[:viewer],
            result: {
              success: true,
              user_safe_status: :created,
              user_safe_message: "Package version created.",
              error_type: "none",
              validation_errors: [],
            },
          }
        end
      end
    end
  end
end
