# typed: true
# frozen_string_literal: true

class PullRequestReviewComment

  # Public: A concrete PORO implementation of AbstractPositionData. Used for comments which
  # are already persisted to the DB using file level positioning.
  class FileLevelPositionData < AbstractPositionData
    attr_reader :left_blob, :path, :comment_path, :thread, :diff

    # Required method defitions as part of PullRequestReviewComment::AbstractPositionData class
    # these are not necessary for this class to function, so they will all return nil
    attr_reader :line, :blob_position, :diff_position, :original_start_blob_position, :start_position_offset

    alias left_blob? left_blob

    def self.async_from_thread(thread, diff: nil)
      async_diff = if diff
        Promise.resolve(diff)
      else
        thread.async_original_diff
      end
      Promise.all([async_diff, thread.async_pull_request.then(&:async_compare_repository).then(&:rpc)]).then do |resolved_diff, rpc|
        new(
          comment_path:  thread.path,
          diff:          resolved_diff,
          path:          thread.path,
          rpc:           rpc,
          side:          thread.left_blob? ? :left : :right,
        )
      end
    end

    # TODO `thread.blob_path` is the same as `thread.path` ?
    def initialize(comment_path:, path:, rpc:, diff: nil, side: :right)
      super(rpc: rpc)

      @comment_path  = comment_path
      @diff          = diff
      @left_blob     = side == :left
      @path          = path
    end

    def commit_oid
      left_blob? ? diff.sha1 : diff.sha2
    end

    def update_thread_position_attributes!(thread)
      # write this first as the left_blob? method is affected by the presence of the other values
      thread.left_blob = left_blob

      # Use the destination path, which will be the a path for deletions, the b path for all others
      thread.blob_path = path

      # The destination commit will be commit 1 for a deletion, commit 2 for an addition
      thread.blob_commit_oid = commit_oid
    end

    def adjustment_source
      { commit_oid: commit_oid, path: path }
    end

    # file-level threads have no blob positions, so this isn't a possible validation error.
    def adjustment_blob_position_valid?
      true
    end

    def adjusted_data(diff)
      params = adjustment_parameters(diff, resolvable_destination: false)

      destination = params[:destination]

      self.class.new(
        comment_path:  comment_path,
        path:          destination[:path],
        rpc:           rpc,
      )
    rescue GitRPC::Error
      nil
    end

    # Extracted from the #diff_entry method in ::PullRequestReviewComment::AbstractPositionData, this
    # implementation specifically does not raise a failure if the diff entry is binary as file level comments
    # should be possible on binary files

    # Public: The diff entry at the comment path.
    #
    # Returns a GitHub::Diff::Entry or raises:
    # - PullRequestReviewComment::AbstractPositionData::InvalidDiffError if the diff is invalid.
    # - PullRequestReviewComment::AbstractPositionData::InvalidPathError if the path is invalid.
    def diff_entry
      return @diff_entry if defined?(@diff_entry)

      fail PullRequestReviewComment::AbstractPositionData::InvalidPathError, "is invalid" if comment_path.nil?

      diff.add_path(comment_path)
      diff.maximize_single_entry_limits!
      entry = diff[comment_path]

      fail PullRequestReviewComment::AbstractPositionData::InvalidDiffError, "is invalid" if entry.nil?
      @diff_entry = entry
    end

    # for this to work, diff needs to be set
    # TODO: analyze the steps that get taken that result in this getting run
    def write_thread_end_position_attributes!(thread:)
      write_initial_commit_attributes(thread)

      thread.blob_commit_oid = self.commit_oid
      thread.blob_path = self.path
      thread.path = self.comment_path
    rescue InvalidDiffError, InvalidLineError, InvalidPathError, GitRPC::Error
      # Swallow error; we're just trying to set the attributes here, not triage errors
    end
  end
end
