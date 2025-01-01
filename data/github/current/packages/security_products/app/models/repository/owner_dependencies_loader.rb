# typed: true
# frozen_string_literal: true

class Repository
  # Public: Use to fetch a given user or org's dependency repository IDs, for all their repositories.
  class OwnerDependenciesLoader
    include ActionView::Helpers::CaptureHelper
    include ResilienceHelper

    MAX_REPOSITORY_IDS = 100
    BATCH_SIZE = 300
    DG_API_SORT_OPTIONS = %w(PACKAGE_MANAGER RECENTLY_PUBLISHED MOST_USED LEAST_RECENTLY_PUBLISHED LEAST_USED).freeze

    # Internal: Ensure a list of repository IDs is in a consistent format.
    #
    # repository_ids - Array of Repository IDs
    #
    # Returns a normalized Array of Repository IDs that's a subset of the given Array.
    def self.normalize_repository_ids(repository_ids)
      repository_ids.compact.uniq.take(MAX_REPOSITORY_IDS)
    end

    # owner_id - User or Organization ID
    # sort_by - corresponds with API::Enums::RepositoryOwnerDependencyQuerySort in github/dependency-graph-api
    # package_managers - Array or Set of package manager filters; see
    #                    AdvisoryDB::Ecosystems.dependency_graph_supported for valid values; corresponds with
    #                    API::Enums::PackageManager in github/dependency-graph-api
    # public_only - Boolean controlling whether only the repository owner's public repositories
    #               should be checked for dependencies
    # viewer - currently authenticated User or nil
    # direct_only - Boolean controlling whether only the owner's direct dependencies should be included, versus those
    #               that are dependencies of their dependencies; defaults to including both direct and indirect
    # repository_ids - optional Array of Repository IDs to limit which of the owner's repositories are checked for
    #                  dependencies; only as many as `MAX_REPOSITORY_IDS` will be used
    def initialize(owner_id:, public_only:, viewer: nil, package_managers: [], sort_by: nil, direct_only: false, repository_ids: [])
      @owner_id = owner_id
      @viewer = viewer
      @sort_by = DG_API_SORT_OPTIONS.include?(sort_by) ? sort_by : nil
      @public_only = public_only
      @direct_only = direct_only
      @package_managers = package_managers
      @repository_ids = self.class.normalize_repository_ids(repository_ids)
    end

    def async_dependency_ids
      Platform::Loaders::Dependencies.load_repository_owner_dependencies(dg_api_params).then do |result|
        dependency_ids = if result.ok?
          hash = result.value!
          hash[:dependencies]
        else
          Failbot.report(result.error, app: "github-dependency-graph", user_id: @owner_id)
          []
        end
      end
    end

    # Public: Get dependency repositories that are visible to the viewer.
    #
    # scope - optional ActiveRecord::Relation for Repository to limit or sort the results
    # preloads - optional Array of Symbols for Repository relations to load in bulk for all the results, to avoid
    #            n+1 queries; defaults to preloading the `owner` relation
    #
    # Returns a Promise resolving to a Repository::OwnerDependenciesLoader::Result.
    def async_dependencies(scope: nil, preloads: [])
      preloads << :owner unless preloads.include?(:owner) # Preload the owner so we can filter out orphaned repos

      async_dependency_ids.then do |dependency_repo_ids|
        all_repos = T.let([], T::Array[T.untyped])
        is_single_batch = dependency_repo_ids.size <= BATCH_SIZE

        dependency_repo_ids.each_slice(BATCH_SIZE) do |dependency_repo_ids_in_batch|
          repos = Repository.active.where(id: dependency_repo_ids_in_batch).filter_spam_and_disabled_for(@viewer)
          repos = repos.merge(scope) if scope
          repos = filter_for_visibility(repos)

          # Sort this batch according to the order the dependency graph API returned, if we're expecting it to
          # sort the results:
          repos = repos.ordered_by_array_index(dependency_repo_ids_in_batch) if is_single_batch && @sort_by

          all_repos = all_repos.concat(repos.to_a)
        end

        GitHub::PrefillAssociations.prefill_associations(all_repos, preloads) if all_repos.present?

        # Exclude orphaned repos:
        all_repos = all_repos.reject { |repo| repo.owner.nil? }

        # Preserve ordering from the dependency graph API across multiple batches if we expected it to sort results:
        all_repos = all_repos.sort_by { |repo| dependency_repo_ids.index(repo.id) } if !is_single_batch && @sort_by

        Repository::OwnerDependenciesLoader::Result.new(dependencies: all_repos,
          # Say it's already sorted if it was a single batch, even when no `@sort_by` was used, because we expect the
          # caller to have given a `scope` that would sort one batch:
          already_sorted: is_single_batch)
      end
    end

    # Public: Get dependency repositories that are visible to the viewer. Memoizes results to avoid duplicate
    # queries on repeated calls with the same parameters.
    #
    # scope - optional ActiveRecord::Relation for Repository to limit or sort the results
    # preloads - optional Array of Symbols for Repository relations to load in bulk for all the results, to avoid
    #            n+1 queries; defaults to the `owner` relation
    #
    # Returns a Repository::OwnerDependenciesLoader::Result.
    def dependencies(scope: nil, preloads: [])
      key = scope&.to_sql || ""
      @memoized_dependencies ||= {}
      result = if @memoized_dependencies.key?(key)
        @memoized_dependencies[key]
      else
        async_dependencies(scope: scope, preloads: preloads).sync
      end
      GitHub::PrefillAssociations.prefill_associations(result.dependencies, preloads) if preloads.present?
      @memoized_dependencies[key] = result
    end

    # Public: Get a count of how many dependencies are visible to the viewer.
    #
    # scope - optional ActiveRecord::Relation for Repository to limit the results
    #
    # Returns an Integer.
    def total_dependencies(scope: nil)
      result = dependencies(scope: scope)
      result.dependencies.count
    end

    private

    # Private: Filter the list of repositories to those the viewer can see.
    #
    # repos - a Repository ActiveRecord::Relation
    #
    # Returns a Repository ActiveRecord::Relation.
    def filter_for_visibility(repos)
      # Conservatively assume no repositories are visible to the viewer when the necessary database clusters aren't
      # available:
      with_database_error_fallback(fallback: Repository.none) do
        return repos.public_scope if !@viewer

        # Is the relation already scoped to just public repositories? No further filtering is necessary, and
        # we don't need to check for visible private IDs in the results:
        return repos if repos.where_values_hash["public"] == true

        private_repo_ids = repos.private_scope.distinct.pluck(:id)
        return repos.public_scope if private_repo_ids.empty?

        visible_private_repo_ids = @viewer.associated_repository_ids(repository_ids: private_repo_ids)
        return repos.public_scope if visible_private_repo_ids.empty?

        repos.public_scope.or(repos.where(id: visible_private_repo_ids))
      end
    end

    def dg_api_params
      @dg_api_params ||= {
        owner_id: @owner_id,
        sort_by: @sort_by,
        package_managers: @package_managers,
        public_only: @public_only,
        direct_only: @direct_only,
        repository_ids: @repository_ids,
      }
    end
  end
end
