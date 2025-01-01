# typed: true
# frozen_string_literal: true

module DependencyGraph
  class RepositoriesUsingDependency
    attr_reader :dependency_id, :owner_id, :repo_ids

    # dependency_id - Integer Repository ID
    # owner_id - Integer User or Organization ID who owns a repository that uses the repository specified by
    #            `dependency_id`
    # repo_ids - Array of Repository IDs that are owned by the user with the specified `owner_id` and that depend on
    #            the repository with the specified `dependency_id`; can be `nil` if there are no such repositories
    def initialize(dependency_id, owner_id:, repo_ids:)
      @dependency_id = dependency_id
      @owner_id = owner_id
      @repo_ids = repo_ids.to_a
    end

    def async_dependency
      Platform::Loaders::ActiveRecord.load(::Repository, dependency_id)
    end

    def async_owner
      Platform::Loaders::ActiveRecord.load(::User, owner_id)
    end

    def repositories(viewer:)
      return ::Repository.none if @repo_ids.empty?

      repos = ::Repository.where(id: @repo_ids).where(owner_id: @owner_id).filter_spam_and_disabled_for(viewer)
      return repos.public_scope unless viewer

      visible_and_relevant_repo_ids = viewer.associated_repository_ids(repository_ids: @repo_ids)
      return repos.public_scope if visible_and_relevant_repo_ids.empty?

      repos.public_scope.or(repos.where(id: visible_and_relevant_repo_ids))
    end
  end
end
