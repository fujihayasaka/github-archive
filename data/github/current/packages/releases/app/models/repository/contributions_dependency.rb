# typed: true
# frozen_string_literal: true

# Contains the code necessary to find first contributions in a repo given an array of Pull Requests
module Repository::ContributionsDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Public: Given an array of pull requests, find the ones that are the first
  # contribution to the repository by the author
  #
  # pull_requests_to_seach - Array of PullRequest
  #
  # Returns: Array of PullRequest
  def first_time_contributions(pull_requests_to_search)
    # contributors to the given set of PRs
    contributor_ids = pull_requests_to_search.map(&:user_id).uniq # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    # contributors to the given set of PRs with other PRs outside the set
    existing_contributor_ids = self.pull_requests.
      where(user_id: contributor_ids).
      where.not(merged_at: nil).
      where.not(id: pull_requests_to_search.map(&:id)).
      pluck(:user_id).uniq

    new_contributor_ids = contributor_ids - existing_contributor_ids

    prs_by_user = pull_requests_to_search.sort_by(&:merged_at).group_by(&:user_id)

    new_contributor_ids.map do |user_id|
      prs_by_user[user_id].first
    end
  end
end
