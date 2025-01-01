# typed: true
# frozen_string_literal: true

# Tracks which repositories a user has committed to.
#
# We don't track the individual commits, just the total number.
class CommitContribution < ApplicationRecord::Collab
  DATA_CUTOFF_DATE = Time.utc(2012, 12, 04) # Date we started tracking commit contributions
  DELETE_BATCH_SIZE = 50
  INSERT_BATCH_SIZE = 20

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
  belongs_to :repository
  delete_in_background_with :repository

  def contributed_on
    committed_date
  end

  # Count of distinct contributors to a given repository
  #
  # repository – The repository to get the commit contribution count from
  #
  # Returns an Integer count.
  def self.contributors_count_for_repository(repository)
    key = "repository:contributor:count:v1:#{repository.id}:#{repository.updated_at.to_i}"
    GitHub.cache.fetch(key) do
      ActiveRecord::Base.connected_to(role: :reading) do
        self.for_repository(repository).no_ghost_users.distinct.count("user_id")
      end
    end
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

      # Ensure the commits we found count towards the author's contributions.
      commit_counts_by_author_and_date.each_key do |author|
        Contribution.clear_caches_for_user(author, context: "track_push")
      end

      # If we recorded any rows, check whether to also record them in commit contribution summaries:
      #
      # - if a backfill_summaries object was provided, use it to track the counts from this push (this covers
      #   cases where a backfill is processing commit history in push chunks and will write out the collected
      #   summaries when it's finished); otherwise
      #
      # - when the repo is flagged in and has no summaries yet, we should schedule a backfill (this covers
      #   cases where a repo already has history in commit_contributions and gets a new push); otherwise
      #
      # - when the repo has summaries and either the repo is flagged in or the update flag is enabled, we
      #   should update the summaries (this covers cases where a repo already has summaries and we want to
      #   keep them in sync with the counts in commit_contributions).
      if rows.any?
        if backfill_summaries
          track_commit_contribution_summaries(summaries: backfill_summaries, rows: rows)
        elsif should_queue_summary_backfill?(repository: repo)
          BackfillCommitContributionSummariesJob.perform_later(repo.id)
        elsif should_update_summaries?(repository: repo)
          update_commit_contribution_summaries(repository: repo, rows: rows)
        end
      end
    end

    count
  end

  # Whether a summary backfill job should be enqueued for a repo that has no summaries yet.
  #
  # repository - Repository to check.
  #
  # Returns a Boolean.
  def self.should_queue_summary_backfill?(repository:)
    # If the repository if flagged in and has no summaries yet, we should schedule a backfill.
    GitHub.flipper[:backfill_missing_commit_contribution_summaries].enabled? && !contribution_summaries_exist?(repository)
  end

  # Whether summaries should be updated when tracking a push.
  #
  # repository - Repository to check.
  # backfilling - Optional Boolean indicating whether processing is part of a backfill.
  #
  # Returns a Boolean.
  def self.should_update_summaries?(repository:)
    # If the repository is flagged in, we should update summaries.
    return true if repository.feature_enabled?(:commit_contribution_summaries)

    # If the summary update flag is enabled and summaries exist, we should update them.
    return true if GitHub.flipper[:update_existing_commit_contribution_summaries].enabled? && contribution_summaries_exist?(repository)

    false
  end

  # Check if commit contribution summaries exist for a repository.
  #
  # repository - Repository to check.
  #
  # Returns a Boolean.
  def self.contribution_summaries_exist?(repository)
    CommitContributionSummary.for_repository(repository).exists?
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
    for_repository(repository).exists?
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
        clear_contributions(repo)

        backfill_summaries = CommitContributionSummary::Collection.new(repository: repo) if should_update_summaries?(repository: repo)
        branches(repo).each { |branch| backfill_branch(repo, branch, backfill_summaries: backfill_summaries) }
        backfill_summaries&.replace!

        GitHub::RepoGraph.clear_cache(repo, "contributors")

        # Add ghost as a contributor if no contributors were found
        if !commit_contributions_exist?(repo)
          CommitContribution.create(user: User.ghost, repository: repo, committed_date: Date.new(1970, 1, 1), commit_count: 0)
        end
      end

      true
    else
      false
    end
  end

  def self.clear_contributions(repo)
    ids = with_read { repo.commit_contribution_ids }
    ids.each_slice(DELETE_BATCH_SIZE) do |slice|
      throttle do
        self.connection.delete(Arel.sql(<<-SQL, ids: slice))
          DELETE FROM commit_contributions WHERE id IN (:ids)
        SQL
      end
    end
  end

  def self.backfill_user!(repo, user, context: "unknown")
    raise ArgumentError, "invalid repo: nil" if repo.nil?
    raise ArgumentError, "invalid user: nil" if user.nil?
    GitHub.dogstats.time "commit_contributions.backfill_user" do

      ids = ActiveRecord::Base.connected_to(role: :reading) do
        # this is only called from a job so its resilient in that way and we
        # don't need to wrap this in a resilient response
        sql = Arel.sql <<-SQL, repo_id: repo.id, user_id: user.id
          SELECT id
          FROM   commit_contributions
          WHERE  repository_id = :repo_id
          AND    user_id = :user_id
        SQL
        self.connection.select_values(sql)
      end

      ids.each_slice(DELETE_BATCH_SIZE) do |slice|
        throttle do
          self.connection.delete(Arel.sql(<<-SQL, ids: slice))
            DELETE FROM commit_contributions WHERE id IN (:ids)
          SQL
        end
      end

      if ActiveRecord::Base.connected_to(role: :reading) { repo.pullable_by?(user) }
        count_before = ids.size
        count_after = 0

        backfill_summaries = CommitContributionSummary::Collection.new(repository: repo) if should_update_summaries?(repository: repo)
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

  def self.clear_user_contributions!(user, repository:  nil)
    GitHub.dogstats.time "commit_contributions.clear_user_contributions" do
      ids = ActiveRecord::Base.connected_to(role: :reading) do
        # this is only called from a job so its resilient in that way and we
        # don't need to wrap this in a resilient response
        sql = Arel.sql <<-SQL, user_id: user.id
          SELECT id
          FROM   commit_contributions
          WHERE  user_id = :user_id
        SQL

        sql += Arel.sql("AND repository_id = :repository_id", repository_id: repository.id) if repository.present?

        self.connection.select_values(sql)
      end

      ids.each_slice(DELETE_BATCH_SIZE) do |slice|
        throttle do
          self.connection.delete(Arel.sql(<<-SQL, ids: slice))
            DELETE FROM commit_contributions WHERE id IN (:ids)
          SQL
        end
      end
    end
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
