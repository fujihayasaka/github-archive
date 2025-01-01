# typed: true
# frozen_string_literal: true

class PullRequestReviewComment

  # Public: An AbstractPositionData implementation which acts as an adapter for comments which
  #   do not have blob positioning information. Uses the original diff of the comment to
  #   determine the values returned by the required abstract methods.
  class LegacyPositionData < AbstractPositionData

    attr_reader :diff_position, :diff, :comment_path

    # Required method defitions as part of PullRequestReviewComment::AbstractPositionData class
    # these are not necessary for this class to function, so they will all return nil
    attr_reader :line, :original_start_blob_position

    def initialize(diff:, comment_path:, diff_position:, diff_hunk_text: nil)
      super(rpc: diff.repo.rpc)
      @comment_path = comment_path
      @diff = diff
      @diff_position = diff_position
      @diff_hunk_text = diff_hunk_text if diff_hunk_text
    end

    def self.async_from_comment(comment)
      Promise.all([
        comment.async_pull_request,
        comment.async_original_diff,
      ]).then do |_pull_request, diff|
        LegacyPositionData.new(
          diff: diff,
          comment_path: comment.path,
          diff_position: comment.original_position,
          diff_hunk_text: comment.diff_hunk,
        )
      end
    end

    def self.async_from_thread(thread)
      thread.async_original_diff.then do |diff|
        LegacyPositionData.new(
          diff: diff,
          comment_path: thread.path,
          diff_position: thread.original_position,
          diff_hunk_text: thread.diff_hunk,
        )
      end
    end

    # Public: Legacy positioned comments cannot target more than one line.
    def start_position_offset
      nil
    end

    # Public: Legacy positioned comments cannot target more than one line.
    def original_start_line
      nil
    end

    # Public: Returns the position as calculated by the offset in the diff_hunk.
    #   If the position is on a deletion, also calculates the position relative to the start_oid
    #   in case the diff_hunk is based on an excerpt from a proxy tree diff.
    def blob_position
      return @blob_position if defined?(@blob_position)
      @blob_position = calculate_blob_position
    end

    # Public: We override this method so that when we position a comment on a deletion which was
    # originally logged in a range diff, we can use the position in the proxy tree and then
    # just calculate the offset from the original proxy tree to the target one.
    def adjustment_blob_position
      left_blob? ? diff_line.blob_left : diff_line.blob_right
    end

    # Public: True if the final line of the diff hunk is on a deletion.
    def left_blob?
      return @left_blob if defined?(@left_blob)
      @left_blob = diff_line.deletion?
    end

    # Public: True if the final lineof the diff hunk is on a deletion
    def left_blob
      left_blob?
    end

    # Public: The merge_base/start_commit_id of the comment for deletions, the end_commit/
    #   original_commit_id for all others.
    def commit_oid
      return @commit_oid if defined?(@commit_oid)
      @commit_oid = left_blob? ? diff&.sha1 : diff&.sha2
    end

    # Public: The "a" path of the original diff for deletion comments, the "b" path otherwise.
    def path
      return @path if defined?(@path)
      @path = target_path(diff, comment_path)
    end

    private

    def adjustment_source
      if left_blob?
        if over_range?

          # Identifies a potential proxy tree reference
          {
            start_commit_oid: diff&.sha1,
            end_commit_oid:   diff&.sha2,
            base_commit_oid:  diff&.base_sha,
            path:             path,
          }
        else
          { commit_oid: diff&.sha1, path: path }
        end
      else
        { commit_oid: diff&.sha2, path: path }
      end
    end

    # Internal: the GitHub::Diff::Line representation of the line being commented on
    def diff_line
      return @diff_line if defined?(@diff_line)

      line = GitHub::Diff::Enumerator.new(diff_hunk_lines).to_a.last
      raise PullRequestReviewComment::AbstractPositionData::InvalidDiffError if line.nil?

      @diff_line = line
    end

    def calculate_blob_position
      return if diff.nil?
      if left_blob?
        calculate_blob_position_for_deletion
      else
        diff_line.blob_right
      end
    end

    # Internal: Calculate the adjusted position from the proxy tree position to the actual
    #   position relative to the path in the commit.
    def calculate_blob_position_for_deletion
      adjustment_params = adjustment_parameters(diff, resolvable_destination: false)
      adjusted_position = Platform::Loaders::AdjustedBlobPosition.load(rpc, adjustment_params).sync
      adjusted_position == :bad ? nil : adjusted_position
    end

    def over_range?
      diff&.base_sha
    end
  end
end
