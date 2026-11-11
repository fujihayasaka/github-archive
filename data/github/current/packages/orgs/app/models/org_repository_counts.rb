# typed: true
# frozen_string_literal: true

class OrgRepositoryCounts < UserRepositoryCounts
  attr_reader :org

  def initialize(org, **preloads)
    super
    @org = org
  end

  # Public: Counts the number of private repositories a org has. Includes forks. Does not include internal repos.
  #
  # Returns an Integer.
  def private_repositories
    return @private_repositories_count if defined?(@private_repositories_count)

    repos_to_count = org.repositories.private_not_internal_scope.limit(Organization::MEGA_ORG_REPOS_THRESHOLD)

    workspace_repo_ids = with_read(org) { org.owned_advisory_workspace_repositories.pluck(:id) }
    repos_to_count = repos_to_count.without_ids(workspace_repo_ids) if workspace_repo_ids.any?

    @private_repositories_count = with_read(org) { repos_to_count.count }
  end
end
