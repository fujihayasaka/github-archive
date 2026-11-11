# typed: true
# frozen_string_literal: true

class Repository
  # Public: Use to fetch the IDs for repositories owned by a particular user or org that
  # have the specified repo as a dependency.
  class RepositoriesUsingDependenciesLoader

    # owner_id - User or Organization ID
    # dependency_ids - Array of Repository IDs
    def initialize(owner_id:, dependency_ids:)
      @owner_id = owner_id
      @dependency_ids = dependency_ids
    end

    # Public: Get a count of how many repositories the specified `owner_id` owns that use each dependency.
    #
    # viewer - the currently authenticated User, so that only the repositories they can see are counted for each
    #          dependency
    #
    # Returns a Promise resolving to a Hash[Repository] => Integer count.
    def async_usage_counts_by_dependency(viewer:)
      async_repo_ids_by_dependency_id.then do |repo_ids_by_dependency_id|
        dependency_ids = repo_ids_by_dependency_id.keys
        repo_ids = repo_ids_by_dependency_id.values.flatten.uniq
        visible_private_repo_and_dependency_ids = visible_private_repo_ids_for(viewer,
          repo_ids: (dependency_ids + repo_ids).uniq)

        dependencies_scope = Repository.where(id: dependency_ids).filter_spam_and_disabled_for(viewer)
        visible_dependencies_by_id = filter_repos_based_on_visibility(dependencies_scope, viewer: viewer,
          visible_private_repo_ids: visible_private_repo_and_dependency_ids).index_by(&:id)

        repos_scope = Repository.owned_by(@owner_id).where(id: repo_ids).filter_spam_and_disabled_for(viewer)
        visible_repos_by_id = filter_repos_based_on_visibility(repos_scope, viewer: viewer,
          visible_private_repo_ids: visible_private_repo_and_dependency_ids).index_by(&:id)
        visible_repo_ids = visible_repos_by_id.keys.to_set

        repo_ids_by_dependency_id.each_with_object({}) do |(dependency_id, repo_ids_for_dependency), hash|
          usage_count_for_dependency = if repo_ids_for_dependency.present?
            visible_repo_ids_for_dependency = repo_ids_for_dependency.to_set & visible_repo_ids
            visible_repo_ids_for_dependency.size
          else
            0
          end

          dependency = visible_dependencies_by_id[dependency_id]
          if dependency
            hash[dependency] = usage_count_for_dependency
          end
        end
      end
    end

    # Public: Get IDs of repositories that are owned by the requested user/org that depend on a particular repository.
    #
    # Returns a Promise resolving to an Array of DependencyGraph::RepositoriesUsingDependency objects, one for each
    # of the requested dependency IDs.
    def async_repos_using_dependencies
      async_repo_ids_by_dependency_id.then do |repo_ids_by_dependency_id|
        @dependency_ids.map do |dependency_id|
          DependencyGraph::RepositoriesUsingDependency.new(dependency_id,
            owner_id: @owner_id,
            repo_ids: repo_ids_by_dependency_id[dependency_id],
          )
        end
      end
    end

    # Public: Get a list of repository IDs for each requested dependency such that those
    # repos are owned by the user/org with the specified ID and they depend on the repository
    # with that ID.
    #
    # Returns a Hash of Repository ID => Array of Repository IDs.
    def async_repo_ids_by_dependency_id
      Platform::Loaders::Dependencies.load_repositories_using_dependencies(
        owner_id: @owner_id,
        dependency_ids: @dependency_ids,
      ).then do |result|
        result_values = if result.ok?
          result.value!
        else
          Failbot.report(result.error, app: "github-dependency-graph", user_id: @owner_id)
          []
        end

        repo_ids_by_dependency_id = result_values
          .map { |result| [result[:dependency_id], result[:repository_ids].to_a] }
          .to_h
      end
    end

    private

    def visible_private_repo_ids_for(viewer, repo_ids:)
      if viewer && repo_ids.any?
        viewer.associated_repository_ids(repository_ids: repo_ids)
      else
        []
      end
    end

    def filter_repos_based_on_visibility(repos_scope, viewer:, visible_private_repo_ids:)
      if visible_private_repo_ids.any?
        repos_scope.public_scope.or(repos_scope.where(id: visible_private_repo_ids))
      else
        repos_scope.public_scope
      end
    end
  end
end
