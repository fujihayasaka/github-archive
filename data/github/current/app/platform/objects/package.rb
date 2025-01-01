# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Package < Platform::Objects::Base
      model_name "Registry::Package"
      description "Information for an uploaded package."

      minimum_accepted_scopes ["read:packages"]
      visibility :public, environments: [:enterprise, :dotcom]

      implements_node templates: [[:rp, :repo_id, :package_id]], as: "P", ready_date: "2021-07-01" do |package|
        {
          prefix: :rp,
          repo_id: package.repository_id,
          package_id: package.id,
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, package)
        # https://github.com/github/pe-package-registry/issues/364
        return false if package.async_repository.nil?
        permission.async_repo_and_org_owner(package).then do |repo, org|
          permission.access_allowed?(:list_packages, repo: repo, organization: org, resource: package, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_repository.then do |repo|
          repo.async_organization.then do |_org|
            permission.belongs_to_repository(object)
          end
        end
      end

      database_id_field(visibility: :internal)

      field :name, String, "Identifies the name of the package.", null: false
      field :shell_safe_name, String, "Identifies the title of the package, escaped for safe use in a shell command.", visibility: :internal, null: false
      field :name_with_owner, String, "Identifies the title of the package, with the owner prefixed.", null: false, visibility: :internal
      field :package_type, Enums::PackageType, "Identifies the type of the package.", null: false
      field :repository, Objects::Repository, method: :async_repository, description: "The repository this package belongs to.", null: true
      field :color, String, "The package type color", null: false, visibility: :internal

      field :pre_release_versions, resolver: Resolvers::PreReleasePackageVersions, description: "List the prerelease versions for this package.", null: true, connection: true, visibility: :internal

      field :versions_by_metadatum, resolver: Resolvers::PackageVersionsByMetadatum, description: "List package versions with a specific metadatum.", null: true, connection: true, visibility: :internal

      field :versions, resolver: Resolvers::PackageVersions, description: "list of versions for this package", null: false, connection: true

      field :version, Objects::PackageVersion, description: "Find package version by version string.", null: true do
        argument :version, String, "The package version.", required: true
        argument :include_deleted, Boolean, "Whether or not deleted versions will be included.", required: false, default_value: false, visibility: :internal
      end

      def version(**arguments)
        Loaders::ActiveRecord.load(::User, @object.owner_id).then do |owner|
          @object.version_by_version_string(arguments[:version], owner: owner, include_deleted: arguments[:include_deleted])
        end
      end

      field :version_by_sha256, Objects::PackageVersion, description: "Find package version by manifest SHA256.", null: true, visibility: :internal do
        argument :sha256, String, "The package SHA256 digest.", required: true
        argument :include_deleted, Boolean, "Whether or not deleted versions will be included.", required: false, default_value: false, visibility: :internal
      end

      def version_by_sha256(**arguments)
        Loaders::ActiveRecord.load(::User, @object.owner_id).then do |owner|
          @object.version_by_sha256(arguments[:sha256], owner: owner, include_deleted: arguments[:include_deleted])
        end
      end

      field :version_by_platform, Objects::PackageVersion, description: "Find package version by version string.", null: true, visibility: :internal do
        argument :version, String, "The package version.", required: true
        argument :platform, String, "Find a package for a specific platform.", required: true
        argument :include_deleted, Boolean, "Whether or not deleted versions will be included.", required: false, default_value: false, visibility: :internal
      end

      def version_by_platform(**arguments)
        Loaders::ActiveRecord.load(::User, @object.owner_id).then do |owner|
          @object.version_by_platform(arguments[:version], arguments[:platform], owner: owner, include_deleted: arguments[:include_deleted])
        end
      end

      field :latest_version, PackageVersion, method: :async_latest_version, description: "Find the latest version for the package.", null: true

      def latest_version
        Loaders::ActiveRecord.load(::User, @object.owner_id).then do |owner|
          @object.async_latest_version.then do |package_version|
            # Once remove_packages_docker_v1_migrated_ff is removed, the last clause to check for unmigrated should also be able to be removed
            if @object.docker? && Registry::Package.all_docker_versions_migrated(owner) && !package_version.nil? && package_version.migration_state != :unmigrated
              nil
            else
              package_version
            end
          end
        end
      end

      field :statistics, PackageStatistics, description: "Statistics about package activity.", null: true

      def statistics
        @object
      end

      field :package_file_by_guid, PackageFile, description: "Find the package file identified by the guid.", null: true, visibility: :internal do
        argument :guid, String, "The unique identifier of the package_file", required: true
      end

      def package_file_by_guid(**arguments)
        Loaders::PackageFiles.with_guid(arguments[:guid], @object.repository_id)
      end

      field :package_file_by_sha256, PackageFile, description: "Find the package file identified by the sha256.", null: true, visibility: :internal do
        argument :sha256, String, "The SHA256 of the package_file", required: true
      end

      def package_file_by_sha256(**arguments)
        Loaders::PackageFiles.load(arguments[:sha256], @object.repository_id)
      end

      field :topics, Connections.define(Objects::Topic), description: "List the topics for this package.", null: true, visibility: :internal, connection: true

      def topics
        @object.async_repository.then do |repository|
          repository.topics.scoped
        end
      end

      field :tags, Connections.define(Objects::PackageTag), description: "list of tags for this package", null: false, connection: true, visibility: :internal

      def tags
        @object.tags.scoped
      end

      field :repository_info, PackageRepositoryInfo, description: "An internal subset of Repository data for this package's repository.", null: true, visibility: :internal

      def repository_info
        @object.async_repository.then do |repo|
          next nil unless repo
          @object
        end
      end

      field :all_dependencies, [PackageVersionDependencies], description: "All dependencies for this package.", null: true, visibility: :internal

      def all_dependencies
        ArrayWrapper.new(@object.package_versions.unmigrated_undeleted)
      end

    end
  end
end
