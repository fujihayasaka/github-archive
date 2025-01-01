# typed: true
# frozen_string_literal: true

class PullRequestReviewComment

  # Public: Contains the information necessary to position a comment in a PR's diff.
  class AbstractPositionData
    extend T::Helpers
    extend T::Sig

    abstract!

    CommentPositionError = Class.new(StandardError)
    InvalidDiffError = Class.new(CommentPositionError)
    InvalidLineError = Class.new(CommentPositionError)
    InvalidPathError = Class.new(CommentPositionError)

    # rpc - a duck which quacks for read_commit_adjusted_position[s]_with_base.
    #       Typically an instance of GitRPC::Client.
    def initialize(rpc:)
      @rpc = rpc
    end

    def diff_side
      left_blob? ? :left : :right
    end

    sig { returns(T.nilable(Integer)) }
    def line
      position = blob_position
      position + 1 if !position.nil?
    end

    # Public: The original line number for which the comment targets (multi-line only)
    sig { returns(T.nilable(Integer)) }
    def original_start_line
      position = original_start_blob_position
      position + 1 if !position.nil?
    end

    # Public: The number of lines for which the comment is targeted at.
    sig { abstract.returns(T.nilable(Integer)) }
    def start_position_offset; end

    # Public: Is the comment on a deletion?
    #
    # Returns true if the comment is on a deletion, false otherwise.
    sig { abstract.returns(T::Boolean) }
    def left_blob?; end

    # Public: The 0-based line offset of the comment in the blob identified by the path and commit.
    #
    # Returns an Integer offset in the blob.
    sig { abstract.returns(T.nilable(Integer)) }
    def blob_position; end

    sig { abstract.returns(T.nilable(Integer)) }
    def original_start_blob_position; end

    # The diff that the comment will be positioned into.
    #
    sig { abstract.returns(GitHub::Diff) }
    def diff; end

    # Public: The line offset into the _diff_ output on which this comment was placed.
    sig { abstract.returns(T.nilable(Integer)) }
    def diff_position; end

    # Public: The path of the comment's file.
    sig { abstract.returns(String) }
    def comment_path; end

    # Public: if a comment is on the left blobg of a diff
    sig { abstract.returns(T::Boolean) }
    def left_blob; end

    # Public: The diff hunk extract for a comment at this position.
    def diff_hunk_text
      return @diff_hunk_text if defined?(@diff_hunk_text)
      @diff_hunk_text = diff_hunk_lines.join("\n")
    end

    # Public: The extracted diff hunk lines for a comment at this poistion.
    #
    # Returns an Array.
    def diff_hunk_lines
      return @diff_hunk_lines if defined?(@diff_hunk_lines)

      # When creating a LegacyPositionData object via LegacyPositionData.async_from_comment, we
      # provide the diff_hunk_text attribute to the constructor since the comment's diff hunk has
      # already been extracted. If that's the case, we avoid re-extracting the diff hunk here.
      return @diff_hunk_lines = diff_hunk_text.scrub!.split("\n") if defined?(@diff_hunk_text)

      @diff_hunk_lines = extract_diff_hunk_lines
    end

    # Public: The diff entry at the comment path.
    #
    # Returns a GitHub::Diff::Entry or raises:
    # PullRequestReviewComment::AbstractPositionData::InvalidDiffError if the diff is invalid.
    # PullRequestReviewComment::AbstractPositionData::InvalidPathError if the path is invalid.
    def diff_entry
      return @diff_entry if defined?(@diff_entry)

      fail PullRequestReviewComment::AbstractPositionData::InvalidPathError, "is invalid" if comment_path.nil?

      diff.add_path(comment_path)
      diff.maximize_single_entry_limits!
      entry = diff[comment_path]

      fail PullRequestReviewComment::AbstractPositionData::InvalidDiffError, "is invalid" if entry.nil?
      fail PullRequestReviewComment::AbstractPositionData::InvalidDiffError, "can't be a binary file" if entry.binary?
      @diff_entry = entry
    end

    # Public: The commit containing the blob identified by the path.
    #
    # Returns a String commit OID.
    sig { abstract.returns(String) }
    def commit_oid; end

    # Public: The path to the blob in commit_oid.
    #
    # Returns a String path.
    sig { abstract.returns(String) }
    def path; end

    # Public: The position used when calculating an adjusted position. This method might be
    #   overridden in cases where the stored position might not be reflective of the commit OID
    #   such as in cases of positions on deletions in a proxy tree.
    def adjustment_blob_position
      blob_position
    end

    def adjustment_blob_position_valid?
      adjustment_blob_position && adjustment_blob_position >= 0
    end

    # Public: The source Hash for calculating the adjusted position from this data.
    #
    # Returns a Hash in the format expected by the source in read_commit_adjusted_position
    sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
    def adjustment_source; end

    # Public: The parameters expected by read_commit_adjusted_position to position
    #         this comment in the given diff.
    #
    # diff                   - an instance of GitHub::Diff
    # resolvable_destination - true when it is ok for left blob positions to target
    #                          a resolvable proxy tree. Generally not cool when repositioning
    #                          with an aim to persist the data.
    #
    # Returns a Hash of the form expected by read_commit_adjusted_position
    def adjustment_parameters(diff, resolvable_destination: true)
      adjustment_destination = destination_for(diff, resolvable: resolvable_destination)
      {
        destination: adjustment_destination,
        position:    adjustment_blob_position,
        source:      adjustment_source,
      }
    end

    def adjusted_blob_position(diff)
      async_adjusted_blob_position(diff).sync
    end

    # Public: The adjusted position for this comment at either the base or head of the given diff.
    #
    # diff - A GitHub::Diff instance
    #
    # Returns an Integer line (0-based) or nil if the line is removed.
    def async_adjusted_blob_position(diff)
      adjustment_args = adjustment_parameters(diff)
      Platform::Loaders::AdjustedBlobPosition.load(rpc, adjustment_args)
    rescue GitRPC::ObjectMissing
      Promise.resolve(:bad)
    end

    # Public: Generate a new PositionData instance representing where this data would be in the
    #         given diff. Commit and path are also updated so that the resulting data is internally
    #         consistent.
    #
    # diff - A GitHub::Diff instance
    #
    # Returns a brand new PullRequestReviewComment::PositionData object or nil if there adjusted
    #   position could not be calculated.
    def adjusted_data(diff)
      params = adjustment_parameters(diff, resolvable_destination: false)

      adjusted_position = Platform::Loaders::AdjustedBlobPosition.load(rpc, params).sync

      return nil if adjusted_position.nil? || adjusted_position == :bad

      destination = params[:destination]

      PositionData.new(
        comment_path:  comment_path,
        commit_oid:    destination[:commit_oid],
        path:          destination[:path],
        blob_position: adjusted_position,
        left_blob:     left_blob?,
        rpc:           rpc,
      )
    rescue GitRPC::Error
      nil
    end

    # This is confusing. For multiline comments, we instantiate two `DiffPositionData` objects.
    # One for the end position data, and one for the start position data. We calculate the start
    # position by subtracting the end position data's `diff_position` from the start position data's
    # `diff_position`, then set the `start_position_offset` attribute on the end position data
    # attribute to be used for the diff hunk extraction later on.
    def calculate_start_position_offset(end_position_data)
      return unless diff_position

      end_position = diff_entry.position_for(
        end_position_data.adjustment_blob_position,
        end_position_data.left_blob?,
      )

      return unless end_position

      end_position_data.diff_position = end_position
      end_position_data.start_position_offset = end_position - diff_position
    end

    # Public: Tries each path in sequence until a matching delta is found.
    #
    # Returns the old or new String path of the found delta depending on the value of `left_blob?`.
    #   If no delta is found, defaults to the first path.
    def target_path(diff, *paths)
      delta = find_delta(diff, paths)

      if delta
        left_blob? ? delta.old_file.path : delta.new_file.path
      else
        paths.first
      end
    end

    def update_thread_position_attributes!(thread)
      # write this first as the left_blob? method is affected by the presence of the other values
      thread.left_blob = left_blob

      # Use the destination path, which will be the a path for deletions, the b path for all others
      thread.blob_path = path

      # The destination commit will be commit 1 for a deletion, commit 2 for an addition
      thread.blob_commit_oid = commit_oid

      thread.blob_position = blob_position
    end

    def write_thread_end_position_attributes!(thread:)
      write_initial_commit_attributes(thread)

      thread.blob_commit_oid = self.commit_oid
      thread.blob_path = self.path
      thread.left_blob = self.left_blob?
      thread.blob_position = self.blob_position
      thread.path = self.comment_path
      thread.diff_hunk = self.diff_hunk_text
      thread.position = self.diff_position
    rescue InvalidDiffError, InvalidLineError, InvalidPathError, GitRPC::Error
      # Swallow error; we're just trying to set the attributes here, not triage errors
    end

    attr_reader :rpc

    private

    def write_initial_commit_attributes(thread)
      thread.commit_id = self.diff.sha2
      thread.original_commit_id = self.diff.sha2
      thread.original_base_commit_id = (self.diff.base_sha || self.diff.sha1)
      thread.original_start_commit_id = self.diff.sha1
      thread.original_end_commit_id = self.diff.sha2
    end

    def find_delta(diff, paths)
      return nil if diff.nil? || paths.empty?

      paths.each do |path|
        delta = diff.delta_for_path(path)
        return delta unless delta.nil?
      end

      nil
    rescue GitRPC::ObjectMissing
      nil
    end

    # Extracts the diff hunk excerpt from the diff entry for this comment.
    # The excerpt includes the entire diff hunk (everything following the closest
    # @@ hunk marker) up to the position attribute value.
    def extract_diff_hunk_lines
      excerpt = []
      position = diff_position
      return excerpt if position.nil?

      # If the diff position (1-based) exceeds the bounds of the diff_entry's
      # lines, then return an empty Array. Validation should catch this later,
      # and prevent the comment from being created.
      return excerpt unless position <= (diff_entry.lines.size - 1)

      diff_lines = diff_entry.lines
      position.downto(0).each do |index|
        line = diff_lines[index]
        excerpt.unshift(line)
        break if line[0] == "@"
      end

      excerpt
    end

    # Internal: A helper method for calculating the destination portion of
    def destination_for(diff, resolvable:)
      destination_path = target_path(diff, path, comment_path)
      if left_blob?
        if resolvable
          {
            start_commit_oid: diff.sha1,
            end_commit_oid:   diff.sha2,
            base_commit_oid:  diff.base_sha,
            path:             destination_path,
          }
        else
          {
            commit_oid: diff.sha1,
            path:       destination_path,
          }
        end
      else
        { commit_oid: diff.sha2, path: destination_path }
      end
    end
  end
end
