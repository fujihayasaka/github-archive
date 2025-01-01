# typed: strict
# frozen_string_literal: true

module CommitContributions
  class Domain < GH::Domain::Base
    # Public: Whether the given user has recorded contributions to the given repository
    #
    # user - User to check for contributions
    # repository - Repository to check for contributions
    #
    # Returns a Boolean.
    sig { params(user: User, repository: T.nilable(Repository)).returns(T::Boolean) }
    def is_contributor?(user:, repository: nil)
      scope = GitHub.commit_contribution_summaries_enabled? ? CommitContributionSummary : CommitContribution
      scope = scope.for_user(user)
      scope = scope.for_repository(repository) if repository

      scope.exists?
    end

    # Public: Repository IDs a given user has contributed commits to
    #
    # user - User to check for contributions
    #
    # Returns an Array of Integer repository IDs.
    sig do
      params(
        user: T.untyped, # Sorbet doesn't play well with SimpleDelegator instances and is_a?
        since: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone)),
        prior_to: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone))
      ).returns(T::Array[Integer])
    end
    def contributed_repo_ids(user:, since: nil, prior_to: nil)
      target_user = user.is_a?(SimpleDelegator) ? user.__getobj__ : user

      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.contributed_repo_ids(user: target_user, since: since, prior_to: prior_to)
      else
        CommitContribution.contributed_repo_ids(user: target_user, since: since, prior_to: prior_to)
      end
    end

    # Public: User IDs who have contributed to a given repository
    #
    # repository - The Repository to find contributors for.
    # users - An optional Array of User objects to include in the results
    # since - An optional Date, if provided only users that have contributed to the
    #         repository between the given date and today will be included.
    # exclude_ghost: Whether to exclude the Ghost user, optional defaults to false.
    #
    # Returns an Array of Integer user IDs.
    sig do
      params(
        repository: Repository,
        users: T::Array[User],
        since: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone)),
        exclude_ghost: T.nilable(T::Boolean)
      ).returns(T::Array[Integer])
    end
    def contributed_user_ids(repository:, users: [], since: nil, exclude_ghost: false)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.contributed_user_ids(repository: repository, users: users, since: since, exclude_ghost: exclude_ghost)
      else
        CommitContribution.contributed_user_ids(repository: repository, users: users, since: since, exclude_ghost: exclude_ghost)
      end
    end

    # Public: User IDs who have contributed to a given repository, sorted by most recent to least recent contribution date.
    #
    # repository - The Repository to find contributors for.
    # limit - The maximum number of users to return.
    #
    # Returns an Array of Integer user IDs.
    sig do
      params(
        repository: Repository,
        limit: Integer,
      ).returns(T::Array[Integer])
    end
    def contributed_user_ids_by_recency(repository:, limit:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.contributed_user_ids_by_recency(repository: repository, limit: limit)
      else
        CommitContribution.for_repository(repository).
          no_ghost_users.
          order("last_commit DESC").
          group(:user_id).
          select(:user_id, "MAX(committed_date) AS last_commit").
          limit(limit).
          map(&:user_id)
      end
    end

    # Public: Whether any of the given repository IDs have contribution recorded since the
    # given date.
    #
    # repository_ids - Array of repository IDs to check
    # since - Date to check for contributions since
    #
    # Returns a Boolean.
    sig { params(repository_ids: T::Array[Integer], since: T.any(Date, DateTime, ActiveSupport::TimeWithZone)).returns(T::Boolean) }
    def has_recent_contributions?(repository_ids:, since:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.has_recent_contributions?(repository_ids: repository_ids, since: since)
      else
        CommitContribution.for_repository(repository_ids).where(committed_date: since..Date.today).exists?
      end
    end

    # Public: Count of commits to a given repository
    sig { params(repository: Repository).returns(Integer) }
    def commit_count_for_repository(repository)
      if GitHub.commit_contribution_summaries_enabled?
        T.cast(CommitContributionSummary.for_repository(repository).sum(:total_count), Integer)
      else
        T.cast(CommitContribution.for_repository(repository).sum(:commit_count), Integer)
      end
    end

    # Public: Return a list of CommitContribution records for the given repository and date range.
    #
    # date_range: the range of dates to get contributions for
    # user: the User to get contributions for
    # repositories: optional Array of Integer repository IDs to get contributions for
    # lightweight_attributes: optional Array of lightweight attributes to select (used only for CommitContribution)
    sig do
      params(
        date_range: T::Range[Date],
        user: T.untyped, # Sorbet doesn't play well with SimpleDelegator instances and is_a?
        repositories: T.nilable(T::Array[Integer]),
        lightweight_attributes: T.nilable(T::Array[Symbol])
      ). returns(T::Array[CommitContribution])
    end
    def commit_contributions_for(date_range:, user:, repositories: nil, lightweight_attributes: nil)
      target_user = user.is_a?(SimpleDelegator) ? user.__getobj__ : user

      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.commit_contributions_for(date_range: date_range, user: target_user, repositories: repositories)
      else
        CommitContribution.commit_contributions_for(date_range: date_range, user: target_user, repositories: repositories, lightweight_attributes: lightweight_attributes)
      end
    end

    # Public: Generate a contribution history for the given repository and optional users.
    #
    # repository - The Repository to generate the history for.
    # users - An optional Array of User objects to generate the history for, if no users
    #         are provided, the top 100 contributors to the given repository will be used.
    #
    # Returns a Hash of Hashes, in the same format as returned by
    # GitHub::RepoGraph::ContributionInsights#fetch_contributors_data.
    sig do
      params(repository: Repository, users: T::Array[User]).
        returns(T::Hash[Symbol, T::Hash[String, T::Hash[Integer, Integer]]])
    end
    def repository_contribution_history(repository:, users:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.repository_contribution_history(repository: repository, users: users)
      else
        CommitContribution.repository_contribution_history(repository: repository, users: users)
      end
    end

    # Public: Generate commit activity history for the given repository
    #
    # repository - The Repository to generate the commit activity for.
    #
    # Returns a Hash of [[timestamp => count, ...]] in the same format as returned by
    # GitHub::RepoGraph::ContributionInsights#fetch_commit_activity_data.
    sig { params(repository: Repository).returns(T::Array[[Date, Integer]]) }
    def repository_commit_activity(repository:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.repository_commit_activity(repository: repository)
      else
        CommitContribution.repository_commit_activity(repository: repository)
      end
    end

    # Public: Get a list of top contributors to a repository
    #
    # repository: the Repository to get contributors for
    # limit: how many users to return at most
    # viewer: the current user, used for spam-filtering purposes; a User or nil
    # skip_viewer: if true, the current user will not be included in the results
    # skip_bots: if true, Bot type users will not be included in the results
    # skip_private_profiles: if true, users with private profiles will not be included in the results
    #
    # Returns an Array of User objects sorted by most to least contributions.
    sig do
      params(
        repository: Repository,
        limit: Integer,
        viewer: T.nilable(User),
        skip_viewer: T::Boolean,
        skip_bots: T::Boolean,
        skip_private_profiles: T::Boolean,
      ).returns(T::Array[User])
    end
    def top_repository_contributors(repository:, limit:, viewer:, skip_viewer: false, skip_bots: false, skip_private_profiles: false)
      user_ids = top_repository_contributor_ids(repository: repository, limit: limit)

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

    # Public: Get a list of User IDs of top contributors to a repository
    #
    # repository: the Repository to get contributors for
    # limit: how many users to return at most
    #
    # Returns an Array of Integer User IDs
    sig { params(repository: Repository, limit: Integer).returns(T::Array[Integer]) }
    def top_repository_contributor_ids(repository:, limit:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.top_repository_contributor_ids(repository: repository, limit: limit)
      else
        CommitContribution.top_repository_contributor_ids(repository: repository, limit: limit)
      end
    end

    # Public: Get a list of top repository IDs contributed to by a given user
    #
    # user: the User that made contributions
    # limit: the number of top repository IDs to return
    # repository_ids: optional list of repository IDs to include
    #
    # Returns an Array of Integer Repository IDs
    sig { params(user: User, limit: Integer, repository_ids: T.nilable(T::Array[Integer])).returns(T::Array[Integer]) }
    def top_contributed_repository_ids(user:, limit:, repository_ids: nil)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.top_contributed_repository_ids(user: user, limit: limit, repository_ids: repository_ids)
      else
        CommitContribution.top_contributed_repository_ids(user: user, limit: limit, repository_ids: repository_ids)
      end
    end

    # Public: Get the first recorded commit contribution date for a given repository
    #
    # repository: the Repository to get the date for
    #
    # Returns a Date
    sig { params(repository: Repository).returns(T.nilable(Date)) }
    def first_repository_contribution_date(repository:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.first_repository_contribution_date(repository: repository)
      else
        CommitContribution.where(repository: repository).order(:committed_date).pluck(:committed_date).first
      end
    end

    # Public: Find the number of days the given user has contributed to each repository
    # after a given date.
    #
    # user - The user to get the commit contribution count from
    # since - Date to check for contributions since
    #
    # Returns a Hash of Integer repository IDs to Integer commit count.
    sig { params(user: User, since: T.any(Date, DateTime, ActiveSupport::TimeWithZone)).returns(T::Hash[Integer, Integer]) }
    def days_with_commits_count_by_repo(user:, since:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.days_with_commits_count_by_repo(user: user, since: since)
      else
        CommitContribution.for_user(user).where(committed_date: since..Date.today).group(:repository_id).count
      end
    end

    # Public: Count of distinct contributors to a given repository
    #
    # repository – The repository to get the commit contribution count from
    #
    # Returns an Integer count.
    sig { params(repository: Repository, since: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone))).returns(Integer) }
    def contributors_count_for_repository(repository, since: nil)
      key = "repository:contributor:count:v1:#{repository.id}:#{repository.updated_at.to_i}"
      GitHub.cache.fetch(key) do
        if GitHub.commit_contribution_summaries_enabled?
          CommitContributionSummary.contributors_count_for_repository(repository, since: since)
        else
          CommitContribution.contributors_count_for_repository(repository, since: since)
        end
      end
    end

    # Public: Find the most recent day a given user has contributed to a given repository.
    #
    # user: the User to check
    # repository: the Repository to check
    #
    # Returns a Date or nil
    sig { params(user: User, repository: Repository).returns(T.nilable(Date)) }
    def last_contribution_date(user:, repository:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.last_contribution_date(user: user, repository: repository)
      else
        CommitContribution.for_repository(repository).for_user(user).order(committed_date: :desc).first&.committed_date
      end
    end

    # Public: Find the earliest day a given user has contributed to any repository.
    #
    # user: the User to check
    #
    # Returns a Date or nil
    sig { params(user: User).returns(T.nilable(Date)) }
    def first_contribution_date(user:)
      if GitHub.commit_contribution_summaries_enabled?
        CommitContributionSummary.first_contribution_date(user: user)
      else
        CommitContribution.first_contribution_date(user: user)
      end
    end
  end
end
