# typed: true
# frozen_string_literal: true

# Tracks which repositories a user has committed to.
#
# We don't track the individual commits, just the total number.
class CommitContribution < ApplicationRecord::Collab
  DATA_CUTOFF_DATE = Time.utc(2012, 12, 04) # Date we started tracking commit contributions
  DELETE_BATCH_SIZE = 50
  INSERT_BATCH_SIZE = 20
  RETENTION_PERIOD = 60.days

  # See https://github.com/github/github/issues/61784#issuecomment-247716619
  LARGE_SCALE_CONTRIBUTOR_LIMIT = 40_000

  scope :no_ghost_users, -> { where("user_id <> ?", User.ghost.id) }
  scope :for_repository, ->(repo) { where(repository_id: repo) }
  scope :for_user, ->(user) { where(user_id: user) }
  scope :order_by_commit_count, ->(user, since: 1.year.ago) {
    for_user(user)
      .where("committed_date > ?", since)
      .group(:repository_id)
      .order(Arel.sql("SUM(commit_count) DESC"))
  }

  belongs_to :user
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  delete_in_background_with :repository

  def contributed_on
    committed_date
  end

  # Public: Repository IDs a given user has contributed commits to
  #
  # user - User to check for contributions
  #
  # Returns an Array of Integer repository IDs.
  sig do
    params(
      user: User,
      since: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone)),
      prior_to: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone))
    ).returns(T::Array[Integer])
  end
  def self.contributed_repo_ids(user:, since:, prior_to:)
    scope = for_user(user)

    date_range = if since && prior_to
      since..prior_to
    elsif since
      since..Date.today
    elsif prior_to
      Range.new(nil, prior_to)
    end
    scope = scope.where(committed_date: date_range) if date_range

    scope.distinct.pluck(:repository_id)
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
  def self.contributed_user_ids(repository:, users: [], since: nil, exclude_ghost: false)
    scope = CommitContribution.for_repository(repository)
    scope = scope.no_ghost_users if exclude_ghost
    scope = scope.for_user(users) if users.any?
    scope = scope.where(committed_date: since..Date.today) if since

    scope.distinct.pluck(:user_id)
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
  def self.repository_contribution_history(repository:, users:)
    all_contributions = CommitContribution.select(:user_id, :committed_date, :commit_count).where(repository: repository, user_id: users.map(&:id))

    all_commits = {}
    all_adds = {}
    all_deletes = {}

    users.each do |user|
      email = user.git_author_email
      next unless email.present?
      user_commits = {}
      user_adds = {}
      user_deletes = {}
      all_contributions.where(user_id: user.id).each do |c|
        timestamp = c.committed_date.to_time.to_i
        user_commits[timestamp] = c.commit_count
        user_adds[timestamp] = 0
        user_deletes[timestamp] = 0
      end
      all_commits[email] = user_commits
      all_adds[email] = user_adds
      all_deletes[email] = user_deletes
    end

    {
      commits: all_commits,
      additions: all_adds,
      deletions: all_deletes
    }
  end

  # Public: Generate commit activity history for the given repository
  #
  # repository - The Repository to generate the commit activity for.
  #
  # Returns a Hash of [[timestamp => count, ...]] in the same format as returned by
  # GitHub::RepoGraph::ContributionInsights#fetch_commit_activity_data.
  sig { params(repository: Repository).returns(T::Array[[Date, Integer]]) }
  def self.repository_commit_activity(repository:)
    all_contributions = CommitContribution.select(:committed_date, :commit_count).where(repository: repository, committed_date: 1.year.ago..).group(:committed_date).order(committed_date: :asc).sum(:commit_count)

    T.cast(all_contributions, T::Hash[Date, Integer]).transform_keys { |k| k.to_time.to_i }.to_a
  end

  # Public: Get a list of matching CommitContribution objects.
  #
  # date_range: A range of dates to search for.
  # user: The User to search for.
  # repositories: An optional Array of Repository IDs to search for.
  # lightweight_attributes: An optional Array of Symbol attributes to select.
  #
  # Returns an Array of CommitContribution objects.
  sig do
    params(
      date_range: T::Range[Date],
      user: User,
      repositories: T.nilable(T::Array[Integer]),
      lightweight_attributes: T.nilable(T::Array[Symbol])
    ). returns(T::Array[CommitContribution])
  end
  def self.commit_contributions_for(date_range:, user:, repositories:, lightweight_attributes:)
    scope = for_user(user).where(committed_date: date_range)
    scope = scope.for_repository(repositories) if repositories
    scope = scope.reselect(lightweight_attributes) if lightweight_attributes

    scope.includes(:repository).to_a
  end

  # Public: Get a list of User IDs of top contributors to a repository
  #
  # repository: the Repository to get contributors for
  # limit: how many users to return at most
  #
  # Returns an Array of Integer User IDs
  sig { params(repository: Repository, limit: Integer).returns(T::Array[Integer]) }
  def self.top_repository_contributor_ids(repository:, limit:)
    ActiveRecord::Base.connected_to(role: :reading) do
      scope = CommitContribution.for_repository(repository).group(:user_id).no_ghost_users.
        order(Arel.sql("SUM(commit_count) DESC"), :user_id)
      scope.limit(limit).pluck(:user_id)
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
  def self.top_contributed_repository_ids(user:, limit:, repository_ids:)
    scope = order_by_commit_count(user)
    scope = scope.for_repository(repository_ids) if repository_ids&.any?
    scope.limit(limit).pluck(:repository_id)
  end

  # Public: Count of distinct contributors to a given repository
  #
  # repository – The repository to get the commit contribution count from
  #
  # Returns an Integer count.
  sig { params(repository: Repository, since: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone))).returns(Integer) }
  def self.contributors_count_for_repository(repository, since:)
    ActiveRecord::Base.connected_to(role: :reading) do
      scope = for_repository(repository).no_ghost_users
      scope = scope.where(committed_date: since..Date.today) if since
      scope.distinct.count("user_id")
    end
  end

  # Public: Find the earliest day a given user has contributed to any repository.
  #
  # user: the User to check
  #
  # Returns a Date or nil
  sig { params(user: User).returns(T.nilable(Date)) }
  def self.first_contribution_date(user:)
    scope = for_user(user).where.not(committed_date: nil)

    # FORCE INDEX required for getting back the first commit contribution quickly
    index = "index_commit_contributions_on_user_committed_date_and_repo"
    scope = scope.from("`#{CommitContribution.table_name}` FORCE INDEX (#{index})")

    scope.order(committed_date: :asc).first&.committed_date
  end

  # Queue up a ContributionsTrackPush job if the updated ref is tracked.
  #
  # push - The Push to track.
  #
  # Returns nothing.
  def self.track_push(ref_update:)
    if track_commits_in_branch?(repository: ref_update.repository, branch: ref_update.branch_name)
      ContributionsTrackPushJob.perform_later(nil, repository: ref_update.repository, before: ref_update.before, after: ref_update.after, ref: ref_update.ref, pusher: ref_update.pusher)
    end
  end

  # Private: Build the grouped counts for push
  #
  # push - The Push to track.
  #
  # Returns a 2-level hash of { author => { date => count } }
  def self.grouped_commit_counts_for_push(push, user: nil)
    commit_counts_by_author_and_date = {}

    Promise.all(push.commits.map do |commit|
      commit.async_authors.then do |authors|
        # Use the date the commit was authored.
        date = commit.contributed_on

        report_author_count(authors.count) unless user

        authors.each do |author|
          next if user && author != user
          # filter out dates that the datetime MySQL type can't handle
          next if date.year > 9999 || date.year < 1000
          commit_counts_by_author_and_date[author] ||= Hash.new(0)
          commit_counts_by_author_and_date[author][date] += 1
        end
      end
    end).sync

    commit_counts_by_author_and_date
  end

  # Given a Push object, finds the authors of the commits and records
  # their contributions.
  #
  # Only records commits on the default branch and the gh-pages branch.
  #
  # push - A Push object.
  # user - Optional User object to track commits for.
  # backfill_summaries - Optional CommitContributionSummary::Collection to track pushes during a backfill.
  #
  # Returns the Integer count of CommitContribution records inserted/updated.
  def self.track_push!(push, user = nil, backfill_summaries: nil)
    repo = push.repository
    return 0 unless repo

    # Only check master and gh-pages branches
    return 0 unless track_commits_in_branch?(repository: repo, branch: push.branch_name)

    # Ignore forks
    return 0 if repo.fork?

    count = 0

    GitHub.dogstats.time "commit_contributions.track_push" do
      GitHub.logger.tagged(
        "code.namespace" => self.name,
        "code.function" => __method__,
        "gh.repo.id" => repo.id,
        "gh.user.id" => user&.id,
      ) do
        commit_counts_by_author_and_date = ActiveRecord::Base.connected_to(role: :reading) do
          grouped_commit_counts_for_push(push, user: user)
        end

        # If we're backfilling a specific user, we've already confirmed that they have pull access to
        # the repo, so we can add all the commit counts. Otherwise we need to add only counts where
        # the author has pull access.
        if user.present?
          rows = commit_counts_by_author_and_date.flat_map do |author, dates|
            dates.map do |date, count|
              [author.id, repo.id, date, count, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW]
            end
          end
        else
          rows = []
          promises = []
          commit_counts_by_author_and_date.each do |author, dates|
            # Create a Promise for the async_pullable_by? call
            promise = repo.async_pullable_by?(author).then do |pullable|
              if pullable
                dates.each do |date, count|
                  rows << [author.id, repo.id, date, count, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW]
                end
              end
            end
            promises << promise
          end

          # Batch load the pullable_by? checks on a :reading role connection. The promises will populate rows[]
          # with only contributions where the author has pull access to the repo.
          ActiveRecord::Base.connected_to(role: :reading) { Promise.all(promises).sync }
        end

        GitHub.dogstats.histogram("commit_contributions.track_push.push_commit_count", push.commits.length)
        GitHub.dogstats.histogram("commit_contributions.track_push.row_count", rows.length)
        GitHub.dogstats.histogram("commit_contributions.track_push.updated_author_count", commit_counts_by_author_and_date.length)

        count += rows.size

        # When contribution summaries are enabled, also record individual commit_contributions records
        # unless the feature flag to skip them is enabled.
        rows.each_slice(INSERT_BATCH_SIZE) do |chunk|
          throttle do
            self.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(chunk)))
              INSERT INTO commit_contributions
                (user_id, repository_id, committed_date, commit_count, created_at, updated_at)
              :rows
              ON DUPLICATE KEY UPDATE
                commit_count = commit_count + VALUES(commit_count),
                updated_at = VALUES(updated_at)
            SQL
          end
        end

        # When contribution data exists in commit contribution summaries - currently only used in the
        # dotcom environment - we only need to preserve a subset of commit contribution records for use
        # in data warehouse DAGs.
        #
        # When pruning commit contributions is enabled, we need to keep:
        # - the most recent RETENTION_PERIOD for each user/repo
        # - the least and most recent commit for each user/repo
        #
        # In those cases, find prunable commit contributions for each user/repo in the push and remove them.
        if contribution_summaries_enabled? && repo.feature_enabled?(:prune_commit_contributions)
          contributor_ids = rows.map(&:first).uniq
          contribution_dates = self.connection.select_rows(Arel.sql(<<-SQL, repository_id: repo.id, user_ids: contributor_ids))
            SELECT user_id, MIN(committed_date) AS first_commit, MAX(committed_date) AS last_commit
            FROM commit_contributions
            WHERE repository_id = :repository_id
            AND user_id IN (:user_ids)
            GROUP BY user_id
          SQL
          contribution_dates_by_user_id = contribution_dates.index_by(&:first)
          contribution_dates_by_user_id.default = []

          prunable_contribution_ids = contributor_ids.flat_map do |user_id|
            endpoint_dates = contribution_dates_by_user_id[user_id][1..2].compact
            scope = CommitContribution.for_repository(repo).for_user(user_id).where("committed_date < ?", RETENTION_PERIOD.ago)
            scope = scope.where("committed_date NOT IN (?)", endpoint_dates) if endpoint_dates.any?
            scope.pluck(:id)
          end

          GitHub.dogstats.distribution("commit_contributions.prunable_count", prunable_contribution_ids.length)

          prunable_contribution_ids.each_slice(DELETE_BATCH_SIZE) do |slice|
            CommitContribution.with_write do
              CommitContribution.connection.delete(Arel.sql(<<-SQL, ids: slice))
                DELETE FROM commit_contributions WHERE id IN (:ids)
              SQL
            end
          end
        end

        # If we found any rows to record, check whether to also record them in commit contribution summaries:
        #
        # - if a backfill_summaries object was provided, use it to track the counts from this push (this covers
        #   cases where a backfill is processing commit history in push chunks and will write out the collected
        #   summaries when it's finished); otherwise
        #
        # - when contribution summaries are enabled, record found rows in summary records
        if rows.any?
          if backfill_summaries
            track_commit_contribution_summaries(summaries: backfill_summaries, rows: rows)
          elsif contribution_summaries_enabled?
            update_commit_contribution_summaries(repository: repo, rows: rows)
          end
        end

        # Ensure the commits we found count towards the author's contributions.
        commit_counts_by_author_and_date.each_key do |author|
          Contribution.clear_caches_for_user(author, context: "track_push")
        end
      end
    end

    count
  end

  # Whether the current environment is configured to use contribution summaries.
  #
  # Returns a Boolean.
  def self.contribution_summaries_enabled?
    GitHub.commit_contribution_summaries_enabled?
  end

  # Track counts in commit contribution summaries.
  #
  # The pullable_by? checks in track_push! are used to populate the list of rows with only contributions
  # from users who have pull access to the repo. We need to use that filtered list when updating
  # summaries to ensure we don't surface contributions from unauthorized accounts.
  #
  # summaries - CommitContributionSummary::Collection to update.
  # rows - Array of [Integer author ID, _, Date committed date, Integer commit count, _, _]
  #
  # Returns nothing
  def self.track_commit_contribution_summaries(summaries:, rows:)
    rows.each { |user_id, _, date, count, _, _| summaries.add(user_id: user_id, date: date, count: count) }
  end

  # Create/update commit contribution summaries with given commit counts.
  #
  # The pullable_by? checks in track_push! are used to populate the list of rows with only contributions
  # from users who have pull access to the repo. We need to use that filtered list when creating
  # summaries to ensure we don't surface contributions from unauthorized accounts.
  #
  # repository - Repository to update summaries for.
  # authors - Array of User objects.
  # rows - Array of [Integer author ID, Integer repository ID, Date committed date, Integer commit count, _, _]
  #
  # Returns nothing.
  def self.update_commit_contribution_summaries(repository:, rows:)
    GitHub.dogstats.distribution_time("commit_contribution_summary.update_from_push") do
      summaries = CommitContributionSummary::Collection.new(repository: repository)
      rows.each { |user_id, _, date, count, _, _| summaries.add(user_id: user_id, date: date, count: count) }
      summaries.update!
    end
  end

  # Queue up a BackfillContributions job if the given repo needs to be
  # backfilled. Runs `backfill!`.
  #
  # repo - Repository to backfill.
  # reset - Optional Boolean (default: false) indicating whether to force a backfill
  # wait - Optional Duration to wait before enqueueing the job
  #
  # Returns a Boolean indicating whether the job was queued or not.
  def self.backfill(repo, reset = false, wait: nil)
    if reset || backfill?(repo)
      if wait
        ContributionsBackfillJob.set(wait: wait).perform_later(repo.id, reset)
      else
        ContributionsBackfillJob.perform_later(repo.id, reset)
      end
      true
    else
      false
    end
  end

  # Whether any commit contributions exist for the specified repository.
  #
  # repository - Repository to check.
  #
  # Returns a Boolean.
  def self.commit_contributions_exist?(repository)
    if contribution_summaries_enabled?
      CommitContributionSummary.for_repository(repository).exists?
    else
      for_repository(repository).exists?
    end
  end

  # Should we backfill the repo?
  #
  # repo - Repository in question.
  #
  # Returns a Boolean.
  def self.backfill?(repo)
    !repo.fork? && with_read { !commit_contributions_exist?(repo) }
  end

  # Given a Repository object, goes through the commit history and creates
  # CommitContribution records for all the previous commits.
  #
  # repo  - Repository to backfill
  # reset - Reset any accumulated data and backfill from scratch.
  #
  # Returns a Boolean indicating whether the repo was backfilled. When reset is
  # true, the backfill always occurs.
  def self.backfill!(repo, reset = false)
    raise ArgumentError, "invalid repo: nil" if repo.nil?
    if reset || backfill?(repo)
      GitHub.dogstats.time "commit_contributions.backfill" do
        backfill_summaries = CommitContributionSummary::Collection.new(repository: repo) if contribution_summaries_enabled?

        clear_contributions(repo)

        branches(repo).each { |branch| backfill_branch(repo, branch, backfill_summaries: backfill_summaries) }
        backfill_summaries&.replace!

        GitHub::RepoGraph.clear_cache(repo, "contributors")

        # Add ghost as a contributor if no contributors were found
        if !commit_contributions_exist?(repo)
          CommitContributionSummary.create(user: User.ghost, repository: repo, year: 1970, counts: [1]) if contribution_summaries_enabled?
          CommitContribution.create(user: User.ghost, repository: repo, committed_date: Date.new(1970, 1, 1), commit_count: 0)
        end
      end

      true
    else
      false
    end
  end

  def self.clear_contributions(repo)
    ids = with_read { CommitContribution.for_repository(repo).pluck(:id) }
    ids.each_slice(DELETE_BATCH_SIZE) do |slice|
      throttle do
        self.connection.delete(Arel.sql(<<-SQL, ids: slice))
          DELETE FROM commit_contributions WHERE id IN (:ids)
        SQL
      end
    end

    # There should be no summaries in non-enabled environments, but we should check to be safe.
    ids = with_read { CommitContributionSummary.for_repository(repo).pluck(:id) }
    ids.each_slice(DELETE_BATCH_SIZE) do |slice|
      throttle do
        self.connection.delete(Arel.sql(<<-SQL, ids: slice))
          DELETE FROM commit_contribution_summaries WHERE id IN (:ids)
        SQL
      end
    end
  end

  def self.backfill_user!(repo, user, context: "unknown")
    raise ArgumentError, "invalid repo: nil" if repo.nil?
    raise ArgumentError, "invalid user: nil" if user.nil?
    GitHub.dogstats.time "commit_contributions.backfill_user" do
      count_before, _ = clear_user_contributions!(user, repository: repo)

      if ActiveRecord::Base.connected_to(role: :reading) { repo.pullable_by?(user) }
        count_after = 0

        backfill_summaries = CommitContributionSummary::Collection.new(repository: repo) if contribution_summaries_enabled?
        branches(repo).each { |branch| count_after += backfill_branch(repo, branch, user, backfill_summaries: backfill_summaries) }
        backfill_summaries&.replace!

        # Optionally track metrics about whether the backfill changed anything
        if user.feature_enabled?(:track_user_contribution_backfill)
          result = if count_before == count_after
            :noop
          elsif count_before == 0
            :added
          elsif count_after == 0
            :removed
          else
            :updated
          end

          GitHub.logger.info(
            "User contribution backfill result",
            "code.namespace" => self.class.name,
            "code.function" => __method__,
            "context" => context,
            "gh.user.id" => user.id,
            "gh.user.login" => user.login, # rubocop:disable GitHub/DoNotAllowLogin - used in logging
            "gh.repo.id" => repo.id,
            "result" => result,
            "count_before" => count_before,
            "count_after" => count_after,
          )
          GitHub.dogstats.increment("user_contributions_backfill.result", tags: ["context:#{context}", "result:#{result}"])
        end
      else
        # Memoize the repo's rpc on a replica so it doesn't happen later on the primary when
        # clearing the cache.
        ActiveRecord::Base.connected_to(role: :reading) { repo.rpc }
        GitHub.dogstats.increment("user_contributions_backfill.no_pull_access")
      end

      GitHub::RepoGraph.clear_cache(repo, "contributors")
    end
    true
  end

  # Clear all commit contributions and summaries for a user, optionally in a repository.
  #
  # user - User to clear contributions for.
  # repository - Optional Repository to clear contributions for.
  #
  # Returns an Array of [
  #   Integer count of commit_contribution records removed,
  #   Integer count of commit_contribution_summaries records removed,
  # ].
  def self.clear_user_contributions!(user, repository:  nil)
    cc_ids = T.let([], T.untyped)
    summary_ids = T.let([], T.untyped)

    GitHub.dogstats.time "commit_contributions.clear_user_contributions" do
      scope = CommitContribution.for_user(user)
      scope = scope.for_repository(repository) if repository.present?
      cc_ids = with_read { scope.pluck(:id) }

      cc_ids.each_slice(DELETE_BATCH_SIZE) do |slice|
        throttle do
          self.connection.delete(Arel.sql(<<-SQL, ids: slice))
            DELETE FROM commit_contributions WHERE id IN (:ids)
          SQL
        end
      end

      # There should be no summaries in non-enabled environments, but we should check to be safe.
      scope = CommitContributionSummary.for_user(user)
      scope = scope.for_repository(repository) if repository.present?
      summary_ids = with_read { scope.pluck(:id) }

      summary_ids.each_slice(DELETE_BATCH_SIZE) do |slice|
        throttle do
          self.connection.delete(Arel.sql(<<-SQL, ids: slice))
            DELETE FROM commit_contribution_summaries WHERE id IN (:ids)
          SQL
        end
      end
    end

    [cc_ids.size, summary_ids.size]
  end

  CommitContributionJobInfo = Struct.new(:repository, :commits, :branch_name)
  # Given a Repository object and a branch, goes through the commit history
  # and creates CommitContribution records for all the commits.
  #
  #   repo - Repository to track
  # branch - String branch name to track
  # backfill_summaries - Optional nested Hash of User => Integer year => Hash of summary attributes
  #
  # Returns the Integer count of CommitContribution records inserted.
  def self.backfill_branch(repo, branch, user = nil, backfill_summaries: nil)
    count = 0

    page = 1
    if commit_oid = repo.ref_to_sha(branch)
      ignore_merge_commits = GitHub.flipper[:contributors_testing_use_no_merges].enabled?(repo)
      while (commits = repo.commits.paged_history(commit_oid, page, 500, nil, ignore_merge_commits)).any?
        page += 1
        push = CommitContributionJobInfo.new(repo, commits, branch)
        count += track_push!(push, user, backfill_summaries: backfill_summaries)
      end
    end

    count
  end

  # Which branches count towards contributions?
  #
  # repo - Repository to check for.
  #
  # Returns an Array of String branch names.
  def self.branches(repo)
    ActiveRecord::Base.connected_to(role: :reading) do
      [repo.default_branch, "gh-pages"].uniq
    end
  end

  # Public: Returns true if commits in the branch should be counted for the given repository.
  #
  # branch - a string branch name
  # repository - a Repository instance
  #
  # Returns a Boolean.
  def self.track_commits_in_branch?(branch:, repository:)
    branches(repository).include?(branch)
  end

  # Which branches count towards contributions?
  #
  # Returns an Array of String branch names.
  def branches
    self.class.branches(repository)
  end

  def self.report_author_count(count)
    range = count.clamp(1, 5)
    range = "5-or-more" if range == 5
    range = "range:#{range}"
    GitHub.dogstats.increment("commit_contributions.author_count", tags: [range])
  end
end
