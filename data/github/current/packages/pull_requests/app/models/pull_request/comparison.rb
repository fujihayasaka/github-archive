# typed: true
# frozen_string_literal: true

class PullRequest
  # A PR specific Comparison state.
  #
  # A PR will have many comparison states over its lifetime. This class can
  # represent the latest and all previous states of a PR as well as ranges of
  # commits within the PR.
  #
  # Diverged from ::Comparison to add PR specific features. Eventually it might
  # be useful to PullRequest::Comparison < ::Comparison or define some sort
  # of minimal shared Comparison interface.
  class Comparison
    include Scientist
    include ActionView::Helpers::CaptureHelper
    include ResilienceHelper

    # Public: Parent PullRequest record.
    attr_reader :pull

    # Public: Head Commit of the start of a commit range.
    attr_reader :start_commit

    # Public: Head Commit of the end of the commit range.
    attr_reader :end_commit

    # Public: Merge base Commit.
    attr_reader :base_commit

    attr_reader :ignore_whitespace

    attr_reader :base_repository
    attr_reader :head_repository

    attr_accessor :diff_options

    # Public: Exposing the review_threads hash to support test assertions
    attr_reader :review_threads

    delegate :entries, :deltas, :changed_files, :additions, :deletions, :changes, :repo, to: :diffs

    # Public: Initialize new Comparison.
    #
    # pull         - The parent PullRequest
    # start_commit - Head start Commit
    # end_commit   - Head end Commit
    # base_commit  - Merge base Commit
    # use_summary   - Use summary deltas
    # ignore_whitespace - Whether to ignore whitespace
    def initialize(pull:, start_commit:, end_commit:, base_commit:, viewer: nil, use_summary: false, ignore_whitespace: false, base_repository: nil, head_repository: nil)
      unless pull.is_a?(PullRequest)
        raise TypeError, "expected pull to be a PullRequest, but was #{pull.class}"
      end
      @pull = pull

      unless start_commit.is_a?(Commit)
        raise TypeError, "expected start_commit to be a Commit, but was #{start_commit.class}"
      end
      @start_commit = start_commit

      unless end_commit.is_a?(Commit)
        raise TypeError, "expected end_commit to be a Commit, but was #{end_commit.class}"
      end
      @end_commit = end_commit

      unless base_commit.is_a?(Commit)
        raise TypeError, "expected base_commit to be a Commit, but was #{base_commit.class}"
      end
      @base_commit = base_commit

      @base_repository = base_repository
      @head_repository = head_repository

      @diff_options = {
         use_summary: use_summary,
         ignore_whitespace: ignore_whitespace,
         base_repository: base_repository,
         head_repository: head_repository,
        }

      @viewer = viewer
    end

    # Public: Find new Comparison.
    #
    # pull             - The parent PullRequest
    # start_commit_oid - Head start Commit
    # end_commit_oid   - Head end Commit
    # base_commit_oid  - Merge base Commit
    # use_summary      - Use summary deltas
    # ignore_whitespace  - Ignore whitespace
    #
    # Returns Comparison if commit objects are available.
    # Returns nil if any of the requested commits does not exist.
    def self.find(pull:, start_commit_oid:, end_commit_oid:, base_commit_oid:, viewer: nil, use_summary: false, ignore_whitespace: false, base_repository: nil, head_repository: nil)
      async_find(
        pull:,
        start_commit_oid:,
        end_commit_oid:,
        base_commit_oid:,
        viewer:,
        use_summary:,
        ignore_whitespace:,
        base_repository:,
        head_repository:
      ).sync
    end

    def self.async_find(pull:, start_commit_oid:, end_commit_oid:, base_commit_oid:, viewer: nil, use_summary: false, ignore_whitespace: false, base_repository: nil, head_repository: nil)
      return Promise.resolve(nil) unless pull

      commit_oids = [start_commit_oid, end_commit_oid, base_commit_oid]

      all_commit_oids_valid = commit_oids.all? { |oid| GitRPC::Util.valid_full_oid?(oid) }
      return Promise.resolve(nil) unless all_commit_oids_valid

      pull.async_historical_comparison.then do |comparison|
        comparison.async_load_commits(commit_oids).then do |start_commit, end_commit, base_commit|
          next nil unless start_commit && end_commit && base_commit

          new(pull:, start_commit:, end_commit:, base_commit:, viewer:, use_summary:, ignore_whitespace:, base_repository:, head_repository:)
        end
      end
    end

    def repository
      pull.compare_repository
    end

    # Codeowners for the comparison diff entries
    #
    # Returns Repository::Codeowners instance
    def codeowners
      @codeowners ||= Repository::Codeowners.new(pull.base_repository, ref: diff.base_sha).tap do |codeowners|
        codeowners.paths = diff.entries.map(&:path) if codeowners.file
      end
    end

    def positioned_threads_for(viewer:, path:, position:)
      thread_positioner(viewer: viewer).positioned_threads.path(path).position(position)
    end

    # Public: Set the ignore whitespace setting for diff. Changing this invalidates the cached diff.
    def ignore_whitespace=(value)
      @diffs = nil
      @ignore_whitespace = value
    end

    # Public: Initialize Diff for commit range.
    #
    # Returns unloaded GitHub::Diff object.
    sig { returns(GitHub::Diff) }
    def diffs
      @diffs ||= build_diff
    end
    alias_method :diff, :diffs

    def diffs=(value)
      @diffs = value
    end

    # Public: Return commit oids included in the PR range.
    #
    # Returns Array of String commit OIDs.
    def commit_oids
      @commit_oids ||= repository.rpc.rev_list(end_commit.oid, exclude_oids: [start_commit.oid, base_commit.oid].compact, reverse: true, limit: 250)
    end

    # Public: Return commits included in the PR range.
    #
    # Returns Array of Commit objects.
    def commits
      @commits ||= repository.commits.find(commit_oids.to_a)
    end

    # Public: Find all diff/review threads for this comparison.
    #
    # viewer - A User that is viewing the review comments. Maybe nil for
    #          anonymous users.
    #
    # Returns a ReviewThreads collection.
    def review_threads_for(viewer:)
      @review_threads ||= {}
      @review_threads[viewer] ||= begin
        diffs.load_diff
        # thread positioner requires the entries to be preloaded.
        diffs.entries_hash
        thread_positioner(viewer: viewer).positioned_threads
      end
    end

    def file_review_threads_for(viewer:)
      @file_review_threads ||= {}
      @file_review_threads[viewer] ||= begin
        diffs.load_diff
        thread_positioner(viewer: viewer).file_level_threads
      end
    end

    # Public: Get a thread positioner scoped to the given viewer.
    #
    # viewer - The User that is viewing the review comments. May be nil for
    #          anonymous users.
    def thread_positioner(viewer:)
      @thread_positioner ||= {}
      @thread_positioner[viewer] ||= PullRequest::ThreadPositioner.new(viewer, self)
    end

    # Public: Initialize review thread for diff entry path and position.
    #
    # path     - String diff entry path
    # position - Integer offset into diff hunk
    #
    # Returns DeprecatedPullRequestReviewThread.
    def review_thread(path:, position:)
      DeprecatedPullRequestReviewThread.new(pull_comparison: self, path: path, position: position, comments: [])
    end

    def total_commits_size
      pull.changed_commit_oids.size
    end

    def range?
      start_commit.oid != base_commit.oid
    end

    def current?
      start_commit.oid == base_commit.oid && end_commit.oid == pull.head_sha
    end

    def commit_before(commit)
      commits = pull.changed_commits
      if idx = commits.index { |c| c.oid == commit.oid }
        commits[idx - 1] if idx > 0
      end
    end

    def commit_after(commit)
      commits = pull.changed_commits
      if idx = commits.index { |c| c.oid == commit.oid }
        commits[idx + 1]
      end
    end

    # Public: Mark Pull Request Comparison as seen by user.
    #
    # user - The User viewing comparison
    #
    # Returns nothing.
    def mark_as_seen(user:)
      unless user.is_a?(User)
        raise TypeError, "expected user to be a User, but was #{user.class}"
      end

      ranges = LastSeenPullRequestRevision.where(pull_request_id: pull.id, user_id: user.id)
      if !ranges.find { |r| r.last_revision == self.end_commit.oid }
        # only mark ranges that are descendants of the previous marker. so if you look at an old
        # revision, it doesn't add a nonsense marker. force pushes won't work with this, though.
        if ranges.last
          has_ancestor = T.let(false, T::Boolean)
          is_descendant = T.let(false, T::Boolean)
          has_commits_authored_by_other_people = T.let(false, T::Boolean)
          ancestor = T.must(ranges.last).last_revision
          pull.changed_commits.each do |commit|
            if commit.oid == ancestor
              has_ancestor = true
              next
            end

            if has_ancestor && commit.oid == self.end_commit.oid
              is_descendant = true
              break
            end

            has_commits_authored_by_other_people = true if commit.author != user
          end

          if is_descendant && has_commits_authored_by_other_people
            LastSeenPullRequestRevision.add_seen_rev(pull, user, self.end_commit.oid)
          end
        else
          LastSeenPullRequestRevision.add_seen_rev(pull, user, self.end_commit.oid)
        end
      end
    end

    private

    sig { returns(GitHub::Diff) }
    def build_diff
      diff_options[:ignore_whitespace] = ignore_whitespace unless ignore_whitespace.nil?
      diff_options[:context_lines] = context_ranges
      diff_options[:head_repository] = pull.head_repository
      diff_options[:base_repository] = pull.base_repository
      GitHub::Diff.new(repository, start_commit.oid, end_commit.oid,
                       diff_options.merge(base_sha: base_commit.oid))
    end

    def entries_diff
      diff_options[:ignore_whitespace] = ignore_whitespace unless ignore_whitespace.nil?
      diff_options[:head_repository] = pull.head_repository
      diff_options[:base_repository] = pull.base_repository
      GitHub::Diff.new(repository, start_commit.oid, end_commit.oid, diff_options.merge(base_sha: base_commit.oid)).tap do |diff|
        diff.entries_hash
      end
    end

    # A hash from file name to Array[Range] indicating the extra parts of the
    # diff we want to include as context.
    def context_ranges
      additional_context_line_ranges = Hash.new { |h, k| h[k] = [] }

      # annotations are unbound, so we need to add a limit
      annotations = with_database_error_fallback(fallback: nil) { end_commit.annotations(limit: CheckAnnotation::MAX_READ_LIMIT) }
      additional_context_line_ranges.merge!(annotations&.line_ranges || {})

      # include all threads available to the viewer, inclusive of threads and
      # comments made outside of the original diff
      if repository&.feature_enabled?(:comment_outside_the_diff)
        # TODO: this is broken - we're not properly loading the entries_hash on the diff before we call `threads_in_range` which requires the data to be preload
        thread_positioner(viewer: @viewer).threads_in_range(entries_diff).each_with_object(additional_context_line_ranges) do |thread, accumulated_range_hash|
          next if thread.blob_position.nil?

          begin
            accumulated_range_hash[thread.path] << thread.blob_context_line_range if thread
          rescue NoMethodError
            next
          end
        end
      end

      additional_context_line_ranges
    end
  end
end
