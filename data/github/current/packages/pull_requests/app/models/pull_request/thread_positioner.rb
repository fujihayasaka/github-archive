# typed: true
# frozen_string_literal: true

class PullRequest
  # This class is responsible for filtering and grouping the comments related to the
  # range of the pull request's diff being viewed. Comments are filtered so that
  # only those visible to the `viewer` and on files that are actually part of the current
  # "diff page" are returned.
  class ThreadPositioner
    # The PullRequest::Comparison with which these comments are associated. Can be
    # the full range of the PR or some sub range.
    attr_reader :comparison

    # The viewer of the Comparison. This can be nil for anonymous viewers.
    attr_reader :viewer


    def initialize(viewer, comparison)
      @viewer       = viewer
      @comparison   = comparison
    end

    # Public: Calculates the current position of line-level comments
    # by building the comment threads for the diff viewer based on the repositioning
    # output of the first comment in the thread, then groups the comments accordingly.
    #
    # Returns a ReviewThreads collection.
    def positioned_threads
      return @review_threads if defined?(@review_threads)

      @review_threads = begin
        return ReviewThreads.new([]) if line_threads_in_range.empty?

        add_paths_to_comments_diff
        comments_diff.load_diff

        threads = line_threads_in_range.each_with_object([]) do |thread, threads|

          path, position, start_diff_line, end_diff_line = positioning_data[thread]

          next unless position && path

          deprecated_thread = DeprecatedPullRequestReviewThread.new(
            pull: comparison.pull,
            pull_comparison: comparison,
            path: path,
            position: position,
            start_diff_line: start_diff_line,
            end_diff_line: end_diff_line,
            comments: thread.async_review_comments_for(viewer).sync,
            activerecord_pull_review_thread: thread
          )

          threads << deprecated_thread
        end

        record_positioning_stats

        ReviewThreads.new(threads)
      end
    end

    def file_level_threads
      return @file_level_threads if defined?(@file_level_threads)
      @file_level_threads = begin
        return ReviewThreads.new([]) if file_threads_in_range.empty?

        add_paths_to_comments_diff
        comments_diff.load_diff

        threads = file_threads_in_range.map do |thread|
          thread.outdated = thread.file_level_thread_outdated_as_of_diff?(diff: comments_diff)

          DeprecatedPullRequestReviewThread.new(
            pull: comparison.pull,
            pull_comparison: comparison,
            path: thread.path,
            position: nil,
            start_diff_line: nil,
            end_diff_line: nil,
            comments: thread.async_review_comments_for(viewer).sync,
            activerecord_pull_review_thread: thread
          )
        end

        ReviewThreads.new(threads)
      end
    end

    def threads_in_range(entries_diff = nil)
      return @threads_in_range if defined?(@threads_in_range)
      @threads_in_range = pull.review_comment_threads_for(viewer)
      @threads_in_range = @threads_in_range.select(&:live?) if current?
      @threads_in_range = @threads_in_range.select { |thread| selected_paths(entries_diff).include?(thread.path) }
      @threads_in_range
    end

    # Public: The line-level comment threads that are both visible and in the progressive range
    # which the viewer is currently viewing.
    def line_threads_in_range
      return @line_threads_in_range if defined?(@line_threads_in_range)
      @line_threads_in_range = threads_in_range.select(&:on_line?)
      @line_threads_in_range
    end

    # Public: The file-level comment threads that are both visible and in the progressive range
    # which the viewer is currently viewing.
    def file_threads_in_range
      return @file_threads_in_range if defined?(@file_threads_in_range)
      @file_threads_in_range = threads_in_range.select(&:on_file?)

      @file_threads_in_range
    end

    # Public: The diff paths that will be rendered in this comparison. Relies on
    # the assumption that the paths of interest are already loaded or, in the case
    # of the diff being beyond the limits, the paths have been requested.
    def selected_paths(entries_diff = nil)
      return @selected_paths if defined?(@selected_paths)

      paths_diff = entries_diff || comparison.diffs
      paths = paths_diff.non_truncated_paths

      # if paths are returned, or if none are returned and the diff is truncated
      paths =
        if !paths.empty? || comparison.diffs.truncated?
          paths
        else
          # return the requested paths as a fall-back
          comparison.diffs.requested_paths
        end
      @selected_paths = paths.map { |path| path.dup.force_encoding(Encoding::UTF_8) }
    end

    private

    delegate :current?, :start_commit, :end_commit, :base_commit, :pull, to: :comparison

    # This diff shares the commit range of the diff displayed to the user but only includes
    # paths relevant for the comments being displayed. It also has its single_entry_limits! set
    # so that comments on large (skipped) diff entries are positioned, even when they are not
    # expanded in the UI. This way we know if an entry has positioned comments even if the
    # text of the entry is not displayed.
    def comments_diff
      return @comments_diff if defined?(@comments_diff)
      @comments_diff = comparison.diffs.only_params
      @comments_diff.maximize_single_entry_limits!
      @comments_diff
    end

    # Internal: Calculates positioning data for each first comment of all visible threads
    #
    # Returns a Hash of PullRequestReviewThreads to [path, position] tuples
    def positioning_data
      return @positioning_data if defined?(@positioning_data)
      @positioning_data = {}

      repositioning_promises = line_threads_in_range.map do |thread|
        new_thread_positioning_data = async_thread_positioning_data(comments_diff, thread)
        @positioning_data[thread] = new_thread_positioning_data if new_thread_positioning_data
      end

      Promise.all(repositioning_promises).sync

      @positioning_data
    end

    # Internal: Determine the new positioning data for a PullRequestReviewThread
    def async_thread_positioning_data(diff, thread)
      # For line-level threads:
      # `thread.position`, `thread.commit_id` and `thread.outdated` will be updated via `thread#async_reposition_from_blob_position`
      on_reject = proc do |error|
        # we just fail to position comments with bad diff hunks. Swallow those and move on.
        raise error unless error.is_a?(PullRequestReviewComment::BadDiffHunkError)
      end

      Promise.all([
        thread.async_reposition_from_blob_position(diff),
        thread.async_start_line(diff),
        thread.async_end_line(diff),
      ]).then(nil, on_reject) do |_, start_line, end_line|
        thread.position ? [thread.path, thread.position, start_line, end_line] : nil
      end.sync
    end

    # Internal: Populate the comments_diff with all the paths referenced by the comments.
    #
    # This way we can filter out the paths with no comments and position as many comments
    # as we can without our default diff limits when calculating how many comments are
    # visible per path.
    def add_paths_to_comments_diff
      comment_paths = threads_in_range.map(&:path)
      comments_diff.add_paths(comment_paths)
    end

    def record_positioning_stats
      GitHub.dogstats.count("pull_request.comparison.threads", threads_in_range.count)
    end
  end
end
