module API
  module Types
    class Root < BaseObject
      include GraphQL::Types::Relay::HasNodeField

      field :packages, API::Types::Package.connection_type, null: true, connection: true do
        argument :ids, [Integer, null: true], required: false
        argument :repository_ids, [Integer, null: true], required: false
        argument :names, [String, null: true], required: false
        argument :package_manager, Enums::PackageManager, required: false
        argument :limit, Integer, required: false
        argument :debug, Boolean, required: false
        argument :preview, Boolean, required: false
        argument :sort_by, Enums::PackageQuerySort, default_value: "DEFAULT", required: false
      end

      def packages(**args)
        arguments = {
          repository_ids:  args[:repository_ids],
          names:           args[:names],
          package_manager: args[:package_manager],
          ids:             args[:ids],
          sort_by:         args[:sort_by],
          limit:           args[:limit],
          debug:           !!args[:debug],
        }

        unless args[:preview]
          if package_manager_in_preview?(args[:package_manager])
            return ::Package.none
          end

          unless arguments[:package_manager]
            arguments[:package_manager] = restrict_package_managers
          end
        end

        Queries::PackageQuery.new(arguments).results
      end

      field :unmapped_packages, API::Types::Package.connection_type, null: true, connection: true do
        argument :names, [String, null: true], required: false
        argument :package_manager, Enums::PackageManager, required: false
        argument :limit, Integer, required: false
      end

      def unmapped_packages(**args)
        arguments = {
          names:            args[:names],
          package_manager:  args[:package_manager],
          limit:            args[:limit]
        }

        Queries::PackageQuery.new(arguments).unmapped_packages
      end

      field :repository_package_releases, API::Connections::PackageReleaseDependents, null: true, connection: true do
        argument :owner_ids, [Integer], required: true
        argument :name, String, required: false
        argument :version, String, required: false
        argument :sort_by, Enums::RepositoryPackageReleaseQuerySort, default_value: "DEFAULT", required: false
        argument :package_manager, Enums::PackageManager, required: false
        argument :vulnerable, Boolean, required: false
        argument :exact_match, Boolean, required: false
        argument :severity, Enums::Severity, required: false
        argument :license, [Enums::License], required: false
        argument :dependent_name, String, required: false
      end

      def repository_package_releases(**args)
        if args[:owner_ids].empty?
          raise GraphQL::ExecutionError.new("Missing required ownerIds on repositoryPackageReleases")
        end

        arguments = {
          owner_ids: args[:owner_ids],
          name: args[:name],
          version: args[:version],
          sort_by: args[:sort_by],
          package_manager: args[:package_manager],
          vulnerable: args[:vulnerable],
          exact_match: args[:exact_match],
          severity: args[:severity],
          license: args[:license],
          dependent_name: args[:dependent_name]
        }

        Queries::RepositoryPackageReleasesQuery.new(**arguments)
      end

      field :package_releases, API::Types::PackageRelease.connection_type, null: true, connection: true do
        argument :package_name, [String, null: true], required: true
        argument :package_manager, Enums::PackageManager, required: true
        argument :requirements, String, required: false
        argument :default_to_latest, Boolean, required: false
        argument :include_unpublished, Boolean, required: false
        argument :preview, Boolean, required: false
      end

      def package_releases(**args)
        arguments = {
          package_name:      args[:package_name],
          package_manager:   args[:package_manager],
          requirements:      args[:requirements],
          default_to_latest: args[:default_to_latest],
          include_unpublished: args[:include_unpublished],
        }

        if package_manager_in_preview?(args[:package_manager]) && !args[:preview]
          return ::PackageRelease.none
        end

        Queries::PackageReleaseQuery.new(**arguments).results
      end

      field :package_release_vulnerabilities, [Integer], null: false do
        argument :package_name, String, required: true
        argument :package_manager, Enums::PackageManager, required: true
        argument :contains_version, String, required: true
      end

      def package_release_vulnerabilities(package_name:, package_manager:, contains_version:)
        allow_named_versions = ::Types::PackageManager.allows_named_versions?(package_manager)
        requirement = Versioning::RequirementSet.deserialize("= #{contains_version}", allow_named_versions: allow_named_versions)

        github_ids = []

        scoped_ranges = ::VulnerableVersionRange
          .for_package_manager(package_manager)
          .for_package(package_name)
          .select(:id, :version_range, :github_id)
        scoped_ranges.find_in_batches do |batch_of_ranges|
          batch_of_ranges.each do |range|
            if range.requirements_set.contain?(requirement)
              github_ids << range.github_id
            end
          end
        end

        github_ids
      end

      field :manifests, API::Connections::Manifests, null: true, connection: true do
        argument :repository_ids, [Integer, null: true], required: true
        argument :ids, [Integer, null: true], required: false
        argument :with_dependencies, Boolean, required: false
        argument :with_snapshots, Boolean, required: false
        argument :include_internal_snapshots, Boolean, required: false
        argument :preview, Boolean, required: false
        argument :package_manager, Enums::PackageManager, required: false
        argument :package_name, String, required: false
      end

      def manifests(**args)
        query = {
          repository_ids:             args[:repository_ids],
          ids:                        args[:ids],
          with_dependencies:          args[:with_dependencies],
          with_snapshots:             args[:with_snapshots],
          include_internal_snapshots: args[:include_internal_snapshots],
          package_manager:            args[:package_manager],
          package_name:               args[:package_name]
        }

        if enforce_preview_mode? && !args[:preview]
          query[:manifest_types] = restrict_manifest_types
        end

        Queries::ManifestsQuery.new(**query).manifests
      end

      # Returns *all* (public and private) repositories for a version range
      field :all_repositories_with_version_range, API::Connections::Dependents, null: true, connection: true, extras: [:lookahead] do
        argument :package_manager, Enums::PackageManager, required: true
        argument :package_name, String, required: true
        argument :lower_bound, String, required: false
        argument :upper_bound, String, required: false
        argument :requirements, String, required: false
        argument :contain, Boolean, default_value: true, required: false
        argument :preview, Boolean, required: false
        argument :allow_empty_pages, Boolean, default_value: false, required: false
        argument :use_version_ranges, Boolean, default_value: false, required: false
      end

      def all_repositories_with_version_range(lookahead:, **args)
        arguments = {
          package_manager: ::Types::PackageManager.coerce(args[:package_manager]),
          package_name: args[:package_name],
          requirements: args[:requirements],
        }

        if package_manager_in_preview?(arguments[:package_manager]) && !args[:preview]
          return []
        end

        # Ordinarily, these arguments would go to the query object via the .first() and .after() methods of
        # relay_query.rb.
        # However, those methods are not called in time to set @after for the calculation of the `dependentEndCursor`
        # field.
        # So, we extract them here, and make sure they get passed to the query via the constructor.
        first = lookahead.arguments[:first]
        after = lookahead.arguments[:after]
        unless after.nil?
          after = ConnectionWrappers::VersionRangeDependentsWrapper.decode(after)
        end

        arguments[:limit] = first
        arguments[:after] = after

        arguments[:use_normalized_tables] = DependencyGraph.use_normalized_tables?

        version_range_dependents_query = Queries::VersionRangeDependentsQuery.new(**arguments)
        DependencyGraph.logger.with_named_tags(version_range_dependents_query.get_log_context) do
          version_range_dependents_query.tap do |query|
            unless query.valid?
              return GraphQL::ExecutionError.new("Invalid version range")
            end
          end
        end
      end

      field :repository_owner_dependencies, API::Types::RepositoryOwnerDependencies, null: true do
        description "Look up what dependencies a given user or organization has."
        argument :owner_id, Integer, "User or organization ID", required: true
        argument :public_only, Boolean, "Whether only the user/org's public repositories " \
          "should be looked at when finding dependencies.", required: false,
          default_value: true
        argument :direct_only, Boolean, "Whether only the user/org's direct dependencies should be included, " \
          "versus those that are dependencies of their dependencies.", required: false, default_value: false
        argument :sort_by, Enums::RepositoryOwnerDependencyQuerySort, "How to order the results.",
          required: false, default_value: "package_name"
        argument :package_manager, Enums::PackageManager,
          "Deprecated, use packageManagers instead. Filter returned dependencies to only those using this " \
          "package manager.", required: false
        argument :package_managers, [Enums::PackageManager],
          "Filter returned dependencies to only those using any of the specified package managers.", required: false,
          default_value: []
        argument :repository_ids, [Integer], "Optional list of IDs of repositories owned by the specified owner to " \
          "filter which of their repositories are checked for dependencies.", required: false, default_value: []
      end

      def repository_owner_dependencies(owner_id:, public_only:, direct_only:, sort_by:, package_manager: nil, package_managers: [], repository_ids: [])
        package_managers << package_manager if package_manager
        Queries::RepositoryOwnerDependenciesQuery.new(owner_id,
          public_only: public_only,
          direct_only: direct_only,
          sort_by: sort_by.try(:to_sym),
          package_managers: package_managers.uniq,
          github_repository_ids: repository_ids,
        )
      end

      field :repositories_using_dependencies, [API::Types::RepositoriesUsingDependency], null: true do
        description "Look up which repositories are using which of some particular dependencies."
        argument :owner_id, Integer, "User or organization ID who owns the repositories that " \
          "should be looked up that use the specified dependencies.", required: true
        argument :dependency_ids, [Integer], "The repository IDs of dependencies to look up " \
          "their usage.", required: true
      end

      def repositories_using_dependencies(owner_id:, dependency_ids:)
        query = Queries::RepositoriesUsingDependenciesQuery.new(owner_id,
          dependency_ids: dependency_ids)
        query.repositories_using_dependencies
      end

      def manifest_preview_types
        DependencyGraph::MANIFEST_TYPE_PREVIEW
      end

      def package_preview_types
        DependencyGraph::PACKAGE_MANAGER_PREVIEW
      end

      def enforce_preview_mode?
        manifest_preview_types.present? || package_preview_types.present?
      end

      def restrict_package_managers
        ::Types::PackageManager.to_a - package_preview_types
      end

      def package_manager_in_preview?(package_manager)
        package_preview_types.include?(package_manager)
      end

      def restrict_manifest_types
        ::Types::Manifest.to_a - manifest_preview_types
      end

      def manifest_type_in_preview?(manifest_type)
        manifest_preview_types.include?(manifest_type)
      end
    end
  end
end
