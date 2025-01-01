# typed: true
# frozen_string_literal: true

class PullRequest
  class SuggestedReviewers
    MAX_DIFF_CHANGES = 250
    MAX_BLOB_SIZE = 250_000
    DEFAULT_SUGGESTION_COUNT = 3
    BLAME_TIMEOUT_SECONDS = 2
    BLAME_CUMULATIVE_TIMEOUT_SECONDS = 4
    BLAME_PATHS_MAX_CONCURRENCY = 8

    attr_reader :comparison

    def initialize(pull, actor: nil, max_commit_age: 3.years, max_comment_age: 6.months)
      @max_commit_age = max_commit_age
      @max_comment_age = max_comment_age
      @comparison = pull.historical_comparison
      @pull = pull
      @actor = actor
    end

    # Determines if suggestions should be made available for this comparison.
    #
    # - Cross repository comparisons always get suggestions.
    # - Source repository as base and head get suggestions.
    # - Forked repository as base and head do not get suggestions.
    #
    # We don't show suggestions when opening a pull request inside your own
    # fork of a repository. The authors from the source repository probably
    # don't want to review pull requests not targeting their source as the
    # base.
    #
    # Returns true if we should make suggestions.
    def available?
      return false if !comparison.valid?
      return false if comparison.merge_base.nil?
      return true if comparison.cross_repository?
      !comparison.base_repo.fork?
    end

    # Suggests the most relevant reviewers for this pull request.
    #
    # excluding - A User, or Array of Users, to remove from the suggested list.
    #             The pull request author should not be suggested to themselves,
    #             for example.
    #
    # Returns an Array of SuggestedReviewers.
    def find(excluding: [], limit: DEFAULT_SUGGESTION_COUNT)
      GitHub.dogstats.time("reviewers.suggestions.time") do
        collection = perform(excluding)
        collection = limit ? collection.first(limit) : collection
      end
    end

    private

    def perform(excluding)
      excluding = Array(excluding)
      results = suggestions
      allowed_reviewers = @pull.filter_allowed_reviewers(results.map(&:user))
      results
        .reject { |suggestion| excluding.include?(suggestion.user) }
        .reject { |suggestion| suggestion.user.spammy? }
        .select { |suggestion| allowed_reviewers.include?(suggestion.user) }
    end

    def suggestions
      (uncached_suggestions + cached_suggestions).uniq
    end

    # Some suggestions may not be cacheable, since the cache is keyed on PR state and these vary by user state
    def uncached_suggestions
      uncached = []

      # Suggest Copilot when appropriate.
      access = PullRequests::Copilot::CodeReviewAccess.new(
        actor: @actor,
        pull_request: @pull,
        current_repository: @pull.repository,
      )

      if access.should_suggest_reviewer?
        bot = Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
        bot_suggestion = PullRequest::SuggestedReviewer.new(user: bot, pull: @pull, copilot: 100)
        uncached.unshift(bot_suggestion)
      end

      uncached
    end

    # Combines suggestion signals (blame and comments) into a single list of
    # scored suggestions.
    #
    # Returns a sorted Array of SuggestedReviewers.
    def cached_suggestions
      cached_suggested_reviewer_data = GitHub.cache.fetch(PullRequest::SuggestedReviewer.cache_key(@pull), stats_key: "reviewers.cached") do
        deltas = diff_deltas

        # Suggest previous reviewers of these files.
        commenters = GitHub.dogstats.time("reviewers.cached.suggestions.commenters.time") do
          paths = deltas.map { |delta| delta.old_file.path }
          reviewers(paths).index_by(&:user)
        end

        # Suggest previous authors of lines we're changing.
        blamed = GitHub.dogstats.time("reviewers.cached.suggestions.authors.time") do
          authors(commits(deltas)).index_by(&:user)
        end

        # Combine scores from commenting and blame into single suggestion.
        @suggested_reviewers = commenters.merge(blamed) do |_user, commenter, author|
          commenter.merge(author)
        end.values.sort.reverse

        @suggested_reviewers.map(&:to_cache)
      end

      # on cache misses @suggested_reviewers will be populated so we don't need to refetch here
      return @suggested_reviewers if @suggested_reviewers

      PullRequest::SuggestedReviewer.from_cache(@pull, cached_suggested_reviewer_data)
    end

    # Loads the paths and lines changed by this pull request so we can
    # find past authors for those lines.
    #
    # For large pull requests, with many paths changed, prioritize the largest
    # diffs and limit the search to the top few entries.
    #
    # Returns an Array of GitRPC::Diff::Summary::Delta objects.
    def diff_deltas
      return [] if !comparison.valid?
      return [] if comparison.merge_base.nil?

      # Load the diff without diff text.
      deltas = comparison.init_diffs.summary.deltas

      # Check blame only on modified paths for now.
      deltas = deltas.select do |delta|
        delta.modified? && !delta.submodule? && !delta.symlink? && !delta.binary?
      end

      # Ignore large diffs causing git blame timeouts.
      deltas = deltas.select do |delta|
        delta.changes < MAX_DIFF_CHANGES
      end

      # Ignore large blobs causing git blame timeouts.
      size_by_path = blob_sizes(deltas)
      deltas = deltas.select do |delta|
        size_by_path[delta.old_file.path] < MAX_BLOB_SIZE
      end

      deltas.sort_by { |delta| -delta.changes }.first(10)
    end

    # Loads the blob byte sizes without loading the blob text itself.
    #
    # deltas - An Array of GitRPC::Diff::Summary::Delta.
    #
    # Returns a Hash of path to size.
    def blob_sizes(deltas)
      oids = deltas.map { |delta| delta.old_file.oid }
      blob_headers = comparison.base_repo.read_object_headers(oids)
      deltas.zip(blob_headers).map do |delta, headers|
        [delta.old_file.path, headers["size"]]
      end.to_h
    end

    # Loads a full diff with diff text, tree deltas and change summary
    # (diffstat) information. Only data for the deltas passed in will be
    # loaded.
    #
    # deltas - An array of GitRPC::Diff::Summary::Delta objects
    #
    # Returns a GitHub::Diff object with diff text loaded. Iterating over this
    # object will yield GitHub::Diff::Entry objects.
    def load_diff_text(deltas)
      paths = deltas.map { |delta| delta.old_file.path }
      diff = comparison.init_diffs

      # If the diff is already loaded and doesn't contain all of the paths,
      # build a new diff without any path limitations.
      if diff.loaded? && (paths - diff.paths).any?
        diff = diff.only_params
      end

      diff.add_paths(paths)
      diff.load_diff
      diff
    end

    def paths_for_deltas(deltas)
      diff = load_diff_text(deltas)
      paths = diff.map do |entry|
        lines = entry.each_line
          .select { |line| (line.addition? || line.deletion?) && line.left > 0 }
          .map { |line| line.left }
          .uniq
        [entry.path, lines]
      end
    end

    # Finds recent commits for each diff entry.
    #
    # Note that a commit may be included in the list several times if it touched
    # several lines in the diff. This duplication is a proxy for lines authored
    # so we can score authors by line count and commit age.
    #
    # deltas - An Array of GitRPC::Diff::Summary::Delta objects.
    #
    # Returns an Array of Commits.
    def commits(deltas)
      return [] if deltas.empty?
      return [] if comparison.merge_base.nil?

      # Don't suggest people who wrote really old code.
      stale = @max_commit_age.ago
      paths = paths_for_deltas(deltas)

      commits =
        if @pull&.repository&.feature_enabled?(:suggested_reviewers_blame_time_bound)
          commits_for_paths_time_bound(paths)
        else
          commits_for_paths(paths)
        end
      # Score only commits we can match to an author.
      Commit.prefill_users(commits).reject { |commit| commit.author.nil? }
    end

    # Ranks past commit authors by contribution relevancy.
    #
    # Assumptions
    #
    # - The most recent blame author of a line is a relevant reviewer.
    # - The more recent your contribution, the more relevant a reviewer you are.
    # - Finding no suggestions is acceptable when you're updating a line
    #   that you last touched. You probably already know who to ask for review.
    #
    # commits - An Array of Commits to score.
    #
    # Returns an Array of SuggestedReviewers.
    def authors(commits)
      commits.group_by(&:author).map do |user, commits|
        score = commits.sum { |c| 1.0 * weight(c.authored_date) }
        PullRequest::SuggestedReviewer.new(user: user, pull: @pull, author: score)
      end
    end

    # Ranks past code reviewers by relevancy.
    #
    # Assumptions
    #
    # - The most recent code reviewers on a path is a relevant reviewer
    #   regardless of the diff position in the blob that changed.
    #
    # paths - An Array of String file paths to score.
    #
    # Returns an Array of SuggestedReviewers.
    def reviewers(paths)
      thread_ids = comparison.base_repo.pull_request_review_threads
        .where(path: paths)
        .where("pull_request_review_threads.created_at > ?", @max_comment_age.ago)
        .where("pull_request_review_threads.pull_request_id <> ?", @pull.id)
      comments = comparison.base_repo.pull_request_review_comments
        .where(pull_request_review_thread_id: thread_ids)
        .joins(:pull_request_review)
        .where(pull_request_reviews: {
          user_hidden: false,
          state: [
            PullRequestReview.state_value(:approved),
            PullRequestReview.state_value(:changes_requested),
          ],
        })
        .includes(:user)
        .reject { |comment| comment.user.nil? }

      comments.group_by(&:user).map do |user, comments|
        score = comments.sum { |c| 1.0 * weight(c.created_at) }
        PullRequest::SuggestedReviewer.new(user: user, pull: @pull, commenter: score)
      end
    end

    # Determines the decay factor to use to weight a contribution by its age.
    # Newer changes indicate a more valuable reviewer than older changes.
    #
    # date - The Date to weight according to its age.
    #
    # Returns a Float between 0.0 and 1.0.
    def weight(date)
      if date > 3.months.ago
        1.0
      elsif date > 6.months.ago
        0.75
      elsif date > 9.months.ago
        0.5
      elsif date > 12.months.ago
        0.25
      else
        0.05
      end
    end

    # Helper method for commits_for_paths below, which acts similarly to `Enumerable#map`
    # except that it expects each mapped value to be a promise, and it waits on multiple
    # promises in parallel at any given time (up to `max_concurrency`). It also ensures
    # that no additional work is started once the given `timeout` has been reached.
    #
    # This would be a great utility function but for now is used experimentally here
    # while this IOPromise code is all behind a feature flag.
    def concurrent_map(items, max_concurrency:, timeout:, &block)
      timer = GitHub::SafeTimer.new(timeout)
      indexed_items = items.each_with_index.to_a
      results = []

      process_next_item = T.let(-> () { 0 }, T.proc.returns(Integer))

      process_next_item = lambda do
        next if indexed_items.empty?
        next unless timer.run?

        next_item, index = indexed_items.shift
        block.call(next_item).then do |result|
          results[index] = result
          process_next_item.call
        end
      end

      # set of "workers", that continue processing items until we timeout or run out of items
      promises = (1..max_concurrency).map { process_next_item.call }
      Promise.all(promises).then { results }
    end

    def commits_for_paths_time_bound(paths)
      # use beginning_of_day so we aren't constantly invalidating our blame cache.
      since = @max_commit_age.ago.beginning_of_day.utc

      ignore_revs_file_oid =
        begin
          comparison.base_repo.spokes_api.read_tree_entry_oid(oid: comparison.merge_base, path: Blame::IGNORE_REVS_FILE_PATH)
        rescue GitRPC::NoSuchPath, GitRPC::BadLineRange, SpokesAPI::NotFound, SpokesAPI::InvalidArgument
          nil
        end

      GitHub.dogstats.distribution_time("reviewers.suggestions.blame.time_bound.time") do
        timer = GitHub::SafeTimer.new(BLAME_CUMULATIVE_TIMEOUT_SECONDS)
        commit_oids = paths.map do |path, lines|
          next unless timer.run?

          blame = comparison.base_repo.blame(
            comparison.merge_base,
            path,
            line_numbers: lines.sort,
            since: since,
            timeout: BLAME_TIMEOUT_SECONDS,
            skip_cache: true
          )

          begin
            blame.read_blame_data(
              retry_without_ignore_revs: false,
              ignore_revs_file: ignore_revs_file_oid.present?
            ).map { |_lineno, _old_lineno, oid| oid }
          rescue GitRPC::Timeout
            []
          end
        end.flatten.compact

        comparison.base_repo.commits.find(commit_oids.uniq).select do |commit|
          commit.authored_date > since
        end
      end
    rescue GitRPC::InvalidIgnoreRevs => e
      # Blame failed due to bad .git-blame-ignore-revs file
      # https://github.blog/changelog/2022-03-24-ignore-commits-in-the-blame-view-beta/
      []
    end

    def commits_for_paths(paths)
      stale = @max_commit_age.ago

      # Approximate the same amount of time as the synchronous version below, but allowing
      # BLAME_PATHS_MAX_CONCURRENCY blames to run concurrently. as soon as we go over our
      # timeout, we stop executing new blames. See `concurrent_map` above for details.
      timeout = BLAME_CUMULATIVE_TIMEOUT_SECONDS.to_f / BLAME_PATHS_MAX_CONCURRENCY

      GitHub.dogstats.distribution_time("reviewers.suggestions.blame.distribution_time") do
        commits_promise = concurrent_map(paths, max_concurrency: BLAME_PATHS_MAX_CONCURRENCY, timeout: timeout) do |path, lines|
          # use beginning_of_day so we aren't constantly invalidating our blame cache.
          since = stale.beginning_of_day.utc

          blame = comparison.base_repo.blame(
            comparison.merge_base,
            path,
            line_numbers: lines.sort,
            since: since,
            timeout: BLAME_TIMEOUT_SECONDS,
            skip_cache: true
          )

          # Blame implements IOPromise::DataLoader, which will preload the
          # required data to operate on the blame. By chaining on this, we
          # can do the loading concurrently and the `#then` work in down time.
          blame.async_attributes.then do
            blame.select do |lineno, _old_lineno, commit|
              lines.include?(lineno) && commit.authored_date > stale
            end.map(&:third)
          end
        end

        commits_promise.sync.flatten.compact
      end
    rescue GitRPC::InvalidIgnoreRevs => e
      # Blame failed due to bad .git-blame-ignore-revs file
      # https://github.blog/changelog/2022-03-24-ignore-commits-in-the-blame-view-beta/
      []
    end
  end
end
