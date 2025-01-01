# typed: false
# frozen_string_literal: true

module MetricQuery::SingleModelColumn
  ##
  # Mixin module for extending AR scopes/relations
  module ForRepoOwner
    # Restricts the query to include the given owner_id.
    # May optionally provide a custom association on which to join
    def for_owner(owner_id, join = :repository, repo_filter_key: "repository_id")
      scope = self

      if join != :repository
        scope = scope.joins(join.keys)
      end

      if owner_id
        target_repos = scope.distinct.pluck(repo_filter_key) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        owner_repo_ids = Repository.where(id: target_repos, owner_id: owner_id).pluck(:id)
        scope = scope.where(repo_filter_key => owner_repo_ids)
      end

      scope
    end
  end
end
