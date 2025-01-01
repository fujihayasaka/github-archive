# typed: true
# frozen_string_literal: true

class PullRequestReviewComment

  # Public: A concrete PORO implementation of AbstractPositionData. Used for comments which
  # are already persisted to the DB using blob positioning.
  class PositionData < AbstractPositionData
    attr_reader :blob_position, :left_blob, :commit_oid, :path, :comment_path, :original_start_blob_position

    # Required method defition as part of PullRequestReviewComment::AbstractPositionData class
    # these are not necessary for this class to function, so they will all return nil
    attr_reader :diff_position, :start_position_offset, :diff

    alias left_blob? left_blob

    def self.async_from_thread(thread)
      thread.async_pull_request.then(&:async_compare_repository).then(&:rpc).then do |rpc|
        new(
          comment_path:  thread.path,
          commit_oid:    thread.blob_commit_oid,
          left_blob:     thread.left_blob,
          path:          thread.blob_path,
          blob_position: thread.blob_position,
          original_start_blob_position: thread.original_start_blob_position,
          rpc:           rpc,
        )
      end
    end

    def initialize(comment_path:, commit_oid:, left_blob:, path:, blob_position:, rpc:, original_start_blob_position: nil)
      super(rpc: rpc)
      @comment_path  = comment_path
      @commit_oid    = commit_oid
      @left_blob     = left_blob
      @path          = path
      @blob_position = blob_position
      @original_start_blob_position = original_start_blob_position
    end

    def adjustment_source
      { commit_oid: commit_oid, path: path }
    end
  end
end
