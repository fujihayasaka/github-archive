# typed: true
# frozen_string_literal: true

class Codespaces::RepositorySelectView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  # Maximum number of user repos to query for and ultimate render the view with
  USER_REPO_LIMIT = 100

  attr_reader :selected_repository, :phrase, :form_name, :remote_ip, :repos_owned_by, :cap_filter, :user_repos_first, :business

  def after_initialize
    @cached_repository_policies = Hash.new do |hash, repo|
      hash[repo] = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync
    end
    @cached_trusted_repos = Codespaces.trusted_repository_authorizations_with_repository(current_user).map(&:repository)
    @form_name ||= "repo"
  end

  def selected?(repo)
    repo == selected_repository
  end

  def trusted_repo_selected?(repo)
    @cached_trusted_repos.include?(repo)
  end

  def codespace_dotfiles_repository_selected?(repo)
    repo == current_user.codespace_dotfiles_repository
  end

  def disabled?(repo)
    !@cached_repository_policies[repo].can_attempt_create? || !satisifies_cap_filter_for_billable_owner?(repo)
  end

  def repositories
    return @repositories if defined?(@repositories)

    @repositories = []

    if phrase.blank?
      @repositories = user_repositories
    else
      GitHub.tracer.in_span("#{self.class.name&.underscore}#repo_search") do
        if user_repos_first
          GitHub.tracer.in_span("#{self.class.name&.underscore}#user_most_recent_repos_search") do
            # get matches from user's own/org repositories/forks
            results = map_search_results(user_most_recently_used_query.execute.results)
            @repositories += add_user_repositories_on_top(results)
          end
        end

        results = query.execute.results
        @repositories += map_search_results(results)
      end
    end
    if selected_repository && @repositories.include?(selected_repository)
      @repositories.delete(selected_repository)
      @repositories.unshift(selected_repository)
    end

    # It is possible to have same repository being returned from both queries
    # we need to apply uniqueness on the resulted array to avoid duplicated results
    @repositories.uniq
  end

  # added to support the codespace permissions repo picker. should only return repos that match the
  # login for the User/Org with id `repos_owned_by` and the phrase
  def repositories_for_owner
    owner = User.find_by(id: repos_owned_by)
    return [] if owner.blank?

    search_query = owner.user? ? "user:#{owner.display_login}" : "org:#{owner.display_login}"
    search_query += " in:name \"#{phrase}\""

    results = Search::Queries::RepoQuery.new(
      current_user: current_user,
      user_session: user_session,
      remote_ip: remote_ip,
      phrase: search_query,
      include_forks: true
    ).execute.results

    cap_filter.authorized_resources(results.map { |result| result["_model"] })
  end

  def internal_repositories_for_business
    repo_ids = if phrase.blank?
      InternalRepository.where(business_id: business.id).limit(100).pluck(:repository_id)
    else
      name = phrase&.split("/").last
      InternalRepository.where(business_id: business.id).joins(:repository).where(["repositories.name LIKE ?", "%#{name}%"]).limit(100).pluck(:repository_id)
    end
    cap_filter.authorized_resources(Repository.where(id: repo_ids))
  end

  private

  def satisifies_cap_filter_for_billable_owner?(repo)
    cap_filter.authorized_resources([@cached_repository_policies[repo].billable_owner]).any?
  end

  # user_repositories fetches all of the associated repositories with the current user
  # and ranks them based on contributions.
  def user_repositories
    ranked_repos = current_user.ranked_contributed_repositories(
      include_issue_comments: true,
      exclude_owned: false,
      since: 30.days.ago,
    )

    associated_ids = current_user.associated_repository_ids(including: [:owned, :direct]).take(USER_REPO_LIMIT)
    associated_repos = Repository.active.where(id: associated_ids).includes(:owner).limit(USER_REPO_LIMIT)

    superset = Set.new(ranked_repos.keys)

    # join ranked repos and associated repos deduping them in the process
    superset = superset | associated_repos.to_a

    # sort repos by their ranked if it exists, otherwise by their name with owner
    cap_filter.authorized_resources(superset.to_a)
      .sort_by { |repo| user_repo_rank(ranked_repos, repo) }
      .take(USER_REPO_LIMIT)
  end

  # user_repo_rank returns the ranking for a repo based on contributions, or
  # repo name with owner if no contributions are found
  def user_repo_rank(rankings, repo)
    can_create = @cached_repository_policies[repo].can_attempt_create?
    ranking = if !can_create
      # > 1, causes these repos to be at the bottom of the repo list
      1
    elsif rankings[repo]
      # negate so the highest :score causes `sort_by` to put most active repos at the top of the repo list
      -rankings[repo][:score]
    else
      # Repos from associated_repository_ids will have no score, they're in the middle
      0
    end

    [ranking, repo.name_with_display_owner]
  end

  def search_query
    split_phrase = phrase.split("/", -1)
    if split_phrase.length != 2
      return "in:name #{phrase}"
    end
    owner, repo_name = split_phrase

    # Some organizations are having repos with the same name as the organization itself
    # Which results in getting other results on top since they match the organization name
    # since `in:name` qualifier searches within `name_with_owner` as well.
    # ex:
    # Searching for github/github will return github/onboarding, github/codespaces, etc..
    # this is not the ideal solution:
    # - Probably ES configs needs to be changed over here to search for "repository name only":
    # https://github.com/github/github/blob/ed4a632227382754fa6904b310f8afbe43755433/app/models/search/queries/repo_query.rb#L120
    repo_subclause = if owner.downcase == repo_name.downcase
      " in:name \"#{owner}/#{repo_name}\""
    elsif repo_name.present?
      " in:name \"#{repo_name}\""
    end

    "org:#{owner} user:#{owner}#{repo_subclause}"
  end

  def query
    @query ||= Search::Queries::RepoQuery.new(
      current_user: current_user,
      user_session: user_session,
      remote_ip: remote_ip,
      phrase: search_query,
      include_forks: true
    )
  end

  # Query for user's own/org repositories ordered my most recently used
  def user_most_recently_used_query
    Search::Queries::RepoQuery.new(
      phrase: "user:#{current_user.display_login} #{user_orgs_subclause} in:name #{phrase}",
      include_forks: true,
      current_user: current_user,
      user_session: user_session,
      sort: %w[updated desc]
    )
  end

  # Return search query subclause for all organizations that user belongs to
  # This subclause can be used if we want to user organizations in the search query
  # ex: User at `GitHub` and `GitHub-learnings` organizations
  # => "org:GitHub org:GitHub-learnings"
  def user_orgs_subclause
    return @user_orgs_subclause if defined?(@user_orgs_subclause)

    GitHub.dogstats.distribution_time("#{self.class.name&.underscore}/user-orgs-select-query.latency") do
      @user_orgs_subclause = current_user.organizations.pluck(:login).map { |name| "org:#{name}" }.join(" ")
    end

    @user_orgs_subclause
  end

  # Return `_model` key from ES search results array
  def map_search_results(results)
    results.map { |result| result["_model"] }
  end

  # Takes an array of user's own/org repositories
  # and puts the user repos on top of the list
  def add_user_repositories_on_top(user_and_org_repos)
    user_repos, org_repos = user_and_org_repos.partition { |repo| repo.owner_id == current_user.id }

    user_repos + org_repos
  end

end
