# typed: false
# frozen_string_literal: true

module Repository::ContributorsDependency
  TOP_CONTRIBUTORS_LIMIT = 1_000

  def contributors(with_anon: false, email_limit: nil, viewer: nil, skip_private_profiles: false)
    Contributors.new(self).all(with_anon: with_anon, email_limit: email_limit, viewer: viewer, skip_private_profiles: skip_private_profiles)
  end

  # Public: Return the total count of non-spammy users who have contributed to this repository.
  #
  # Returns a Contributors::CountResponse that must be checked with :computed? before use.
  def contributor_count
    Contributors.new(self).count
  end

  def top_contributors(limit:, viewer:, skip_viewer: false, skip_bots: false, skip_private_profiles: false)
    if limit < 0
      GitHub.logger.warn("limit param out of range #{limit}",
                         "code.namespace": self.class.name,
                         "code.function": __method__)
      limit = 0
    end
    limit = [limit, TOP_CONTRIBUTORS_LIMIT].min

    CommitContributions.domain.top_repository_contributors(
      repository: self,
      limit: limit,
      viewer: viewer,
      skip_viewer: skip_viewer,
      skip_bots: skip_bots,
      skip_private_profiles: skip_private_profiles,
    )
  end

  # Return repo contributors blocked by a given user
  #
  # user - User object
  #
  # Returns an empty array if user hasn't blocked anyone, or
  # an ActiveRecord::Relation of blocked Users
  def blocked_contributors_for(user)
    return [] unless user

    ActiveRecord::Base.connected_to(role: :reading) do
      ignored_user_ids = user.ignored.pluck(:id)
      return [] if ignored_user_ids.empty?

      blocked_contributor_ids = CommitContributions.domain.contributed_user_ids(repository: self, users: ignored_user_ids)
      return [] if blocked_contributor_ids.empty?

      User.where(id: blocked_contributor_ids)
    end
  end

  # Return an array of contributor IDs
  #
  # user_ids - an array of user_ids to check
  #
  # If no argument is given, this will be all contributor IDs
  # If an array of IDs are passed, a subset of contributor IDs will be returned
  def contributor_ids(user_ids = [])
    @contributor_ids ||= begin
      ActiveRecord::Base.connected_to(role: :reading) do
        CommitContributions.domain.contributed_user_ids(repository: self, users: user_ids, exclude_ghost: true)
      end
    end
  end

  # Is the given user a contributor to this repository?
  #
  # user - the user or user id
  # type - an optional type of contribution to consider; defaults to commits; valid values:
  #        Issue, PullRequest, CommitContribution, Discussion
  #
  # Returns bool, true if contributor, otherwise false
  def contributor?(user, type: CommitContribution)
    ActiveRecord::Base.connected_to(role: :reading) do
      if type == PullRequest
        pull_requests.exists? user_id: user
      elsif type == Issue
        issues.without_pull_requests.exists? user_id: user # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      elsif type == Discussion
        discussions.authored_by(user).exists?
      else
        CommitContributions.domain.is_contributor?(repository: self, user: user)
      end
    end
  end

  # Is the given user a contributor of any kind to this repository?
  #
  # user - the user or user id
  #
  # Returns bool, true if contributor, otherwise false
  def contributor_of_any_kind?(user)
    with_database_error_fallback(fallback: false) do
      ActiveRecord::Base.connected_to(role: :reading) do
        # omitting issues check due to slow performance of query
        discussions.authored_by(user).exists? || pull_requests.exists?(user_id: user) || \
          CommitContributions.domain.is_contributor?(repository: self, user: user)
      end
    end
  end

  # Public: Returns true if the viewer should see a 'first-time contributor' banner.
  #
  # user - The User viewing the repository.
  # is_pull_requests - Boolean indicating whether the user is on the /pulls/ page or /issues/
  # repo_owner - The User who owns the repository, used for async loading.
  #
  # Returns a Boolean.
  sig { params(user: T.nilable(User), is_pull_requests: T::Boolean, repo_owner: User, owner_managed: T::Boolean).returns(T::Boolean) }
  def show_first_time_contributor_banner?(user:, is_pull_requests: false, repo_owner: owner, owner_managed: owner.is_enterprise_managed?)
    notice_subject = is_pull_requests ? "pull_requests" : "issues"
    notice = "first_time_contributor_#{notice_subject}_banner"

    public? &&
    !fork? &&
    !archived? &&
    !GitHub.enterprise? &&
    !!user &&
    !repo_owner.spammy? &&
    repo_owner.id != user.id &&
    !adminable_by?(user) &&
    !user.dismissed_repository_notice?(notice, repository_id: id) &&
    !user.dismissed_notice?(notice) &&
    !user_has_contributed?(user: user, is_pull_requests: is_pull_requests) &&
    !owner_blocking?(user) &&
    # only show the banner to emu users if the repo is managed
    (!user.is_enterprise_managed? || owner_managed)
  end

  # Returns an instance of the graph cache for this repo
  def graph_cache
    @graph_cache ||= GitHub::RepoGraph::Cache.new(self, network_id, default_oid)
  end

  # Is the git graph cache enabled for this repo?
  #
  # Returns true or false
  def graph_cache_enabled?
    return unless online?
    !graph_cache.disabled?
  end

  # Toggle git graphing, turning it on if it's off, and off
  # if it's on
  def toggle_allow_git_graph
    if graph_cache_enabled?
      graph_cache.disable
    else
      graph_cache.enable!
    end
  end

  private

  # Private: Returns true if the current user has contributed to the repository in a way relevant
  # to the page they're currently on.
  #
  # is_pull_requests - Boolean indicating whether the user is on the /pulls/ page or /issues/
  #
  # Returns a Boolean.
  sig { params(user: User, is_pull_requests: T::Boolean).returns(T::Boolean) }
  def user_has_contributed?(user:, is_pull_requests:)
    contributor?(user, type: CommitContribution) || contributor?(user, type: is_pull_requests ? PullRequest : Issue)
  end
end
