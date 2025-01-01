# typed: true
# frozen_string_literal: true

class UserRankedRepositories
  # Public: Get cached repositories a user has contributed to. See
  # User.repositories_contributed_to docs for more info on ranking. Unlike
  # self.ranked_for, this returns an Array instead of a scope.
  #
  # user - User to calculate ranked repositories for.
  # since - DateTime (optional). Defaults to 1 year ago.
  #
  # Returns an array of Repositories.
  def self.eager_ranked_for(user, since: nil)
    since ||= 1.year.ago

    ids = UserRanked::Cache.fetch_ranked_ids(name, user, { since: since.strftime("%m-%Y") }) do
      compute_ranked_ids(user: user, since: since)
    end

    return [] if ids.empty?

    Repositories.domain.by_ids(ids).to_a.sort_by { |repo| ids.index(repo.id) }
  end

  def self.compute_ranked_ids(user:, since: nil)
    since ||= 1.year.ago

    user.ranked_contributed_repositories(
      include_issue_comments: true,
      since: since.at_beginning_of_month,
    ).keys.map(&:id)
  end
end
