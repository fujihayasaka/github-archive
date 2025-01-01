# typed: true
# frozen_string_literal: true

class RegistryTwo::SearchRepositoriesController < RegistryTwo::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
  only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  SEARCH_RESULT_LIMIT = 8

  def index
    query = params.fetch(:q, "").strip

    # We only want to search repos *belonging* to the owner of the package.
    # Since a package can only be linked to a repo owned by the owner of the package.
    scope = if owner.organization?
      # Note: Elastomer has a limit of 4000 *private* repos which are considered for the search.
      # This means that sometimes it's not possible to find a private repo via the search.
      # However, Elastomer has a bug/quirks/background compatability feature where it will not apply this restriction for searches with an `org:` qualifier.
      # This means that more than 4000 private repos will be considered for the search BUT it's possible that the search runs into a timeout an partial results are returned.
      # So the search for private repos is best effort for both `user:` and `org:` qualifieres but with different internal reasons on why that's the case.
      "org:#{owner.login}" # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1194
    else
      "user:#{owner.login}" # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1194
    end

    # `RepoQuery` will only return repositories that the `current_user` has at least read access to.
    search_query = ::Search::Queries::RepoQuery.new(
      current_user: current_user,
      user_session: user_session,
      remote_ip:    request&.remote_ip,
      phrase: "#{scope} in:name #{query}",
      per_page: SEARCH_RESULT_LIMIT,
      include_forks: true
    )
    results = search_query.execute.results
    repositories = results.map { |r| r["_model"] }.uniq.first(SEARCH_RESULT_LIMIT)

    render(Packages::RepositorySearchResultsComponent.new(
      repositories: repositories
    ), layout: false, formats: :html)
  end
end
