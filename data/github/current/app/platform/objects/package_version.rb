# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PackageVersion < Platform::Objects::Base
      model_name "Registry::PackageVersion"
      description "Information about a specific package version."

      minimum_accepted_scopes ["read:packages"]
      visibility :public, environments: [:enterprise, :dotcom]

      implements_node templates: [[:rpv, :repo_id, :package_id, :package_version_id]], as: "PV", ready_date: "2021-07-01" do |package_version|
        package_version.async_package.then do |package|
          {
            prefix: :rpv,
            repo_id: package.repository_id,
            package_id: package.id,
            package_version_id: package_version.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, package_version)
        package_version.async_package.then do |package|
          permission.typed_can_access?("Package", package)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_package.then do |package|
          permission.typed_can_see?("Package", package)
        end
      end

      database_id_field(visibility: :internal)

      field :deleted, Boolean, "Whether or not this version has been deleted.", null: false, method: :deleted?, visibility: :internal
      field :deleted_at, Scalars::DateTime, "Time at which the version was deleted.", visibility: :internal, null: true
      field :sha256, String, "Identifies the sha256.", null: true, visibility: :internal
      field :size, Integer, "Identifies the size.", null: true, visibility: :internal
      field :summary, String, "The package version summary.", null: true
      field :manifest, String, "The package manifest for this package version.", null: true, method: :package_manifest, visibility: :internal
      field :version, String, "The version string.", null: false
      field :pre_release, Boolean, "Whether or not this version is a pre-release.", null: false
      field :shell_safe_version, String, "Identifies the version number, escaped for safe use in a shell command.", visibility: :internal, null: false
      field :platform, String, "The platform this version was built for.", null: true
      field :updated_at, Scalars::DateTime, description: "Time at which the most recent file upload for this package version finished", null: false, visibility: :internal

      def updated_at
        @object.async_files.then do |files|
          @object.async_package_files.then do |package_files|
            all_files = (files + package_files)
            updated_at = all_files.sort_by(&:created_at).last.created_at unless all_files.empty?
            updated_at || @object.updated_at
          end
        end
      end

      field :package, Objects::Package, method: :async_package, description: "The package associated with this version.", null: true

      field :release, Objects::Release, method: :async_release, description: "The release associated with this package version.", null: true

      field :readme, String, description: "The README of this package version.", null: true

      field :installation_command, String, description: "A single line of text to install this package version.", null: true, visibility: :internal

      def readme
        readme = @object.body
        return readme unless readme.to_s.empty?
        @object.async_release.then do
          if @object.release
            @object.release.body
          end
        end
      end

      # Manually specify this camelcasing, it's different than the default :readmeHTML
      field :readmeHtml, Scalars::HTML, description: "The HTML README of this package version", null: true, visibility: :internal, resolver_method: :readme_html

      def readme_html
        html = @object.body_html
        return html unless html.to_s.empty?
        @object.async_release.then do
          if @object.release
            @object.release.body_html
          end
        end
      end

      field :statistics, PackageVersionStatistics, description: "Statistics about package activity.", null: true

      def statistics
        @object
      end

      field :viewer_can_edit, Boolean, description: "Can the current viewer edit this Package version.", null: false, visibility: :internal

      def viewer_can_edit
        return false if @context[:viewer].blank?
        @object.async_package.then do |package|
          package.async_repository.then do |repository|
            repository.writable_by?(context[:viewer])
          end
        end
      end

      field :dependencies, Connections.define(Objects::PackageDependency), description: "list of dependencies for this package", null: false, connection: true, visibility: :internal do
        argument :type, Enums::PackageDependencyType, "Find dependencies by type.", required: false
      end

      def dependencies(**arguments)
        if arguments[:type].present?
          @object.dependencies.where(dependency_type: Registry::Dependency.dependency_types[arguments[:type]])
        else
          @object.dependencies.scoped
        end
      end

      field :files, resolver: Resolvers::PackageFiles, description: "List of files associated with this package version", null: false, connection: true

      field :file_by_name, Objects::PackageFile, description: "A file associated with this package version", null: true, visibility: :internal do
        argument :filename, String, "A specific file to find.", required: true
      end

      def file_by_name(**arguments)
        @object.files.uploaded.where(filename: arguments[:filename]).first
      end

      field :metadata, Connections.define(Objects::PackageMetadatum), description: "Metadata associated with this package version", null: true, connection: true, visibility: :internal do
        argument :names, [String, null: true], "List of metadatum names to find.", required: false
      end

      def metadata(**arguments)
        if arguments[:names]
          name = arguments[:names]
        elsif arguments[:name]
          name = arguments[:name]
        end

        Loaders::Registry::PackageMetadata.load(@object.id, name).then do |metadata|
          StableArrayWrapper.new(metadata)
        end
      end
    end
  end
end
