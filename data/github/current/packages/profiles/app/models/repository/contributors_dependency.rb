# typed: false
# frozen_string_literal: true

module Repository::ContributorsDependency
  extend T::Sig

  def contributors(with_anon: false, email_limit: nil, viewer: nil, skip_private_profiles: false)
    Contributors.new(self).all(with_anon: with_anon, email_limit: email_limit, viewer: viewer, skip_private_profiles: skip_private_profiles)
  end

  # Public: Return the total count of non-spammy users who have contributed to this repository.
  #
  # Returns a Contributors::CountResponse that must be checked with :computed? before use.
  def contributor_count
    Contributors.new(self).count
  end

  # Public: Return the total count of non-spammy users who have contributed to this repository,
  # falling back to a default value if it cannot be computed.
  #
  # Returns an Integer.
  def contributor_count_or(fallback)
    response = contributor_count
    response.computed? ? response.value : fallback
  end

  def top_contributors(limit:, viewer:, skip_viewer: false, skip_bots: false, skip_private_profiles: false, since: nil)
    if limit < 0
      GitHub.logger.warn("limit param out of range #{limit}",
                         "code.namespace": self.class.name,
                         "code.function": __method__)
      limit = 0
    end

    contribution_summaries_available = since.nil? &&
      self.feature_enabled?(:commit_contribution_summaries) &&
      CommitContributionSummary.for_repository(self).exists?

    science("contribution_summaries_top_contributors") do |e|
      e.use do
        top_contributors_control(
          limit: limit,
          viewer: viewer,
          skip_viewer: skip_viewer,
          skip_bots: skip_bots,
          skip_private_profiles: skip_private_profiles,
          since: since
        )
      end

      e.try do
        top_contributors_candidate(
          limit: limit,
          viewer: viewer,
          skip_viewer: skip_viewer,
          skip_bots: skip_bots,
          skip_private_profiles: skip_private_profiles,
        )
      end

      e.run_if { contribution_summaries_available }

      e.compare { |control, candidate| control.map(&:display_login) == candidate.map(&:display_login) }

      e.clean { |value| value.map(&:display_login) }

      e.context({
        repository_id: self.id
      })
    end
  end

  # Public: Get contributors who have made the most commits to this repository. Pulls data
  # from the commit_contributions table instead of the git repo itself.
  #
  # limit - how many users to return at most
  # viewer - the current user, used for spam-filtering purposes; a User or nil
  # skip_viewer - if true, the current user will not be included in the results
  # skip_bots - if true, Bot type users will not be included in the results
  #
  # Returns an Array of Users.
  def top_contributors_control(limit:, viewer:, skip_viewer: false, skip_bots: false, skip_private_profiles: false, since: nil)
    user_ids = ActiveRecord::Base.connected_to(role: :reading) do
      scope = commit_contributions.group(:user_id).no_ghost_users.
        order(Arel.sql("SUM(commit_count) DESC"), :user_id)
      scope = scope.where("committed_date > ?", since) if since
      scope.limit(limit).pluck(:user_id)
    end

    users = ActiveRecord::Base.connected_to(role: :reading) do
      query = User.where(id: user_ids).filter_spam_for(viewer)
      query = query.where.not(id: viewer.id) if viewer && skip_viewer
      query = query.where.not(type: ::Bot.name) if skip_bots
      query = query.where(private_profile: false) if skip_private_profiles
      query.to_a
    end

    # Sort with top contributors first
    users.sort_by { |user| user_ids.index(user.id) }
  end

  # Public: Get contributors who have made the most commits to this repository. Pulls data
  # from the daily_commit_contribution_summaries table instead of the git repo itself.
  #
  # limit - how many users to return at most
  # viewer - the current user, used for spam-filtering purposes; a User or nil
  # skip_viewer - if true, the current user will not be included in the results
  # skip_bots - if true, Bot type users will not be included in the results
  #
  # Returns an Array of Users.
  def top_contributors_candidate(limit:, viewer:, skip_viewer: false, skip_bots: false, skip_private_profiles: false)
    user_ids = ActiveRecord::Base.connected_to(role: :reading) do
      scope = CommitContributionSummary.for_repository(self).group(:user_id).no_ghost_users.
        order(Arel.sql("SUM(total_count) DESC"), :user_id)
      scope.limit(limit).pluck(:user_id)
    end

    users = ActiveRecord::Base.connected_to(role: :reading) do
      query = User.where(id: user_ids).filter_spam_for(viewer)
      query = query.where.not(id: viewer.id) if viewer && skip_viewer
      query = query.where.not(type: ::Bot.name) if skip_bots
      query = query.where(private_profile: false) if skip_private_profiles
      query.to_a
    end

    # Sort with top contributors first
    users.sort_by { |user| user_ids.index(user.id) }
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

      blocked_contributor_ids = commit_contributions.where(user_id: ignored_user_ids).distinct.pluck(:user_id)
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
    if user_ids.empty?
      @contributor_ids ||= ActiveRecord::Base.connected_to(role: :reading) { commit_contributions.no_ghost_users.group(:user_id).pluck(:user_id) }
    else
      ActiveRecord::Base.connected_to(role: :reading) { commit_contributions.where(user_id: user_ids.uniq.compact).group(:user_id).pluck(:user_id) }
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
        issues.without_pull_requests.exists? user_id: user
      elsif type == Discussion
        discussions.authored_by(user).exists?
      else
        commit_contributions.exists? user_id: user
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
          commit_contributions.exists?(user_id: user)
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
  sig { params(user: T.nilable(User), is_pull_requests: T::Boolean, repo_owner: User).returns(T::Boolean) }
  def show_first_time_contributor_banner?(user:, is_pull_requests: false, repo_owner: owner)
    return false unless feature_enabled?(:issues_react_first_time_contribution_banner)

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
    !user_has_contributed?(is_pull_requests: is_pull_requests) &&
    !owner_blocking?(user)
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
  sig { params(is_pull_requests: T::Boolean).returns(T::Boolean) }
  def user_has_contributed?(is_pull_requests:)
    contributor?(user, type: CommitContribution) || contributor?(user, type: is_pull_requests ? PullRequest : Issue)
  end
end
