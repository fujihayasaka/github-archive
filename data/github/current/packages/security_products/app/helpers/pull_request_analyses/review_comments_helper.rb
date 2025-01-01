# typed: strict
# frozen_string_literal: true

module PullRequestAnalyses
  module ReviewCommentsHelper

    sig { params(pull: PullRequest, commit_oid: String).returns(T.nilable(PullRequest::Comparison)) }
    def find_pull_comparison(pull, commit_oid)
      PullRequest::Comparison.find(
        pull:,
        start_commit_oid: pull.merge_base,
        end_commit_oid: commit_oid,
        base_commit_oid: pull.merge_base,
      )
    end

    # We don't want the comment's location to escape a single diff hunk, so we may have to compute a new start_line for it
    # so the final location is the intersection of the alert's location with the diff hunk that contains the end_line.
    # This method is public so it can be tested.
    sig { params(result: T.untyped, diffs: GitHub::Diff).returns(T.nilable(Integer)) }
    def comment_start_line(result, diffs)
      diff_entry = diffs.with_path(result.location.file_path)
      return nil unless diff_entry.present?

      start_line = result.location.start_line # we shuld never end up with this not having changed value I think?
      new_hunk = T.let(false, T::Boolean)
      diff_entry.each_line do |line|
        next if line.right < result.location.start_line

        break if line.right > result.location.end_line # should we ever actually hit here??

        # we are in a new hunk, we need this to move the start_line
        if line.hunk?
          new_hunk = true
          next
        end
        if new_hunk && line.right
          start_line = line.right
          new_hunk = false
          next
        end

        if line.type == :addition && result.location.end_line == line.right
          return start_line
        end
      end

      nil
    end

    sig do
      params(
        result_start_line: T.nilable(Integer),
        result_end_line: T.nilable(Integer),
        comment_start_line: T.nilable(Integer)
      ).returns(T::Hash[T.untyped, T.untyped])
    end
    def extra_comment_attributes(result_start_line, result_end_line, comment_start_line = nil)
      if result_start_line != result_end_line
        {
          start_line: comment_start_line || result_start_line,
          start_side: :right,
        }
      else
        {}
      end
    end
  end
end
