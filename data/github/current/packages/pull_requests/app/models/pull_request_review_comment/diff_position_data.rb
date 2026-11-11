# typed: true
# frozen_string_literal: true

class PullRequestReviewComment

  # Public: Represents position data provided outside the context of a PullRequestReviewComment.
  # Used to calculate the legacy diff_position and the adjusted blob position if comment is
  # left on the left side of the diff. Used for creating new comments only.
  class DiffPositionData < AbstractPositionData
    attr_reader :side, :diff, :start_position_offset

    # Required method defitions as part of PullRequestReviewComment::AbstractPositionData class
    # this is not necessary for this class to function, so this will return nil
    attr_reader :original_start_blob_position

    # diff - the unloaded GitHub::Diff (it will be loaded in the process of using this class)
    # line - the 1-based line of the blob on which the comment resides
    # right_path - the path of the blob on the right hand side of the diff. This is used
    #              for the legacy `path` field of comments
    # side - :left for deletions, :right for all others
    def initialize(diff:, line:, right_path:, side:)
      super(rpc: diff.rpc)
      @diff = diff
      @side = side
      @right_path = right_path
      @adjustment_blob_position = line.to_i - 1
    end

    def commit_oid
      left_blob? ? diff.sha1 : diff.sha2
    end

    def comment_path
      @right_path
    end

    def path
      left_blob? ? diff_entry.a_path : diff_entry.b_path
    end

    # The 0-based offset into the blob. For comments on the :right, this will be identical to
    # the provided line - 1. For comments on the left, there can be adjustments, depending on
    # the `base_oid` and `oid1` values for the diff as they can influence the base blob in the
    # diff text.
    def blob_position
      return @blob_position if defined?(@blob_position)
      @blob_position = calculate_real_blob_position
    end

    def diff_position
      return @diff_position if defined?(@diff_position)
      @diff_position = diff_entry.position_for(adjustment_blob_position, left_blob?)
    rescue InvalidDiffError, InvalidPathError
      # Swallow error; we're just trying to set the attributes here, not triage errors
    end

    def adjustment_source
      if left_blob?
        if diff.base_sha && diff.base_sha != diff.sha1

          # Identifies a potential proxy tree reference
          {
            start_commit_oid: diff.sha1,
            end_commit_oid:   diff.sha2,
            base_commit_oid:  diff.base_sha,
            path:             path,
          }
        else
          { commit_oid: diff.sha1, path: path }
        end
      else
        { commit_oid: diff.sha2, path: path }
      end
    end

    def left_blob?
      side.to_sym == :left
    end

    def left_blob
      left_blob?
    end

    # override super's default implementation
    attr_reader :adjustment_blob_position

    protected

    attr_writer :diff_position, :start_position_offset

    private

    def validate_adjustment_blob_position!
      return if adjustment_blob_position_valid?
      fail PullRequestReviewComment::AbstractPositionData::InvalidLineError, "required and an integer greater than zero"
    end

    def calculate_real_blob_position
      validate_adjustment_blob_position!
      if left_blob?
        calculate_blob_position_for_deletion
      else
        adjustment_blob_position
      end
    end

    # Internal: Calculate the adjusted position from the proxy tree position to the actual
    #   position relative to the path in the commit.
    def calculate_blob_position_for_deletion
      adjustment_params = adjustment_parameters(diff, resolvable_destination: false, caller: "diff_position_data.calculate_blob_position_for_deletion")
      adjusted_position = Platform::Loaders::AdjustedBlobPosition.load(rpc, adjustment_params).sync
      adjusted_position == :bad ? nil : adjusted_position
    end
  end
end
