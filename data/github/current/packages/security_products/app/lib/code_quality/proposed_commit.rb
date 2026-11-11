# typed: strict
# frozen_string_literal: true

module CodeQuality
  class ProposedCommit < T::Struct
    const :commit_message, String
    const :diff_entry, GitHub::Diff::Entry
    const :diff_lines, T::Array[GitHub::Diff::Line]

    sig { returns(Integer) }
    def left_start_line
      diff_lines.map(&:left).min
    end

    sig { returns(Integer) }
    def right_start_line
      diff_lines.map(&:right).min
    end

    sig { returns(Integer) }
    def left_end_line
      diff_lines.map(&:left).max
    end

    sig { returns(Integer) }
    def right_end_line
      diff_lines.map(&:right).max
    end

    sig { params(other: ProposedCommit).returns(T::Boolean) }
    def overlaps?(other)
      if diff_entry.path != other.diff_entry.path
        return false
      end

      (left_start_line <= other.left_end_line && left_end_line >= other.left_start_line) || (right_start_line <= other.right_end_line && right_end_line >= other.right_start_line)
    end

    # Assume both commits are for the same file path
    sig { params(other: ProposedCommit).returns(T::Boolean) }
    def is_later_than?(other)
      if left_start_line != other.left_start_line
        return left_start_line > other.left_start_line
      end

      if right_start_line != other.right_start_line
        return right_start_line > other.right_start_line
      end

      if left_end_line != other.left_end_line
        return left_end_line > other.left_end_line
      end

      right_end_line > other.right_end_line
    end
  end
end
