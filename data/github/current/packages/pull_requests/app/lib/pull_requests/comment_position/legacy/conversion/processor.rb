# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy::Conversion
      class Processor
        sig do
          params(
            side: T.nilable(Symbol),
            start_side: T.nilable(Symbol),
            subject_type: T.nilable(Symbol),
            base_sha: String,
            base_path: T.nilable(String),
            head_sha: String,
            head_path: T.nilable(String),
            # Tuple from diff [left_line_number, right_line_number]
            start_line_numbers: [T.nilable(Integer), T.nilable(Integer)],
            # Tuple from diff [left_line_number, right_line_number]
            end_line_numbers: [T.nilable(Integer), T.nilable(Integer)],
            outdated: T::Boolean,
          ).void
        end
        def initialize(side:, start_side:, subject_type:, base_sha:, base_path:, head_sha:, head_path:, start_line_numbers:, end_line_numbers:, outdated: false)
          @side = side
          @start_side = start_side
          @subject_type = subject_type
          @base_sha = base_sha
          @base_path = base_path
          @head_sha = head_sha
          @head_path = head_path
          @start_line_numbers = start_line_numbers
          @end_line_numbers = end_line_numbers
          @outdated = outdated
        end

        sig { returns(Positions) }
        def call
          range = Positions::DiffRange.new(base_commit_oid: @base_sha, start_commit_oid: @base_sha, end_commit_oid: @head_sha)

          # TODO: Determine if blob position is still valid when PullRequestReviewThread is marked
          # as outdated?
          if @outdated
            return Positions::Indeterminate.new(reason: :outdated, range:)
          end

          # Determine path and commit_oid for "end positioning" for all position types.
          if @side == :left
            end_line_number = @end_line_numbers[0]

            if base_path = @base_path
              path = base_path
              commit_oid = @base_sha
            else
              return Positions::Indeterminate.new(reason: :positioning_requires_left_path, range:)
            end
          else
            end_line_number = @end_line_numbers[1]

            if head_path = @head_path
              path = head_path
              commit_oid = @head_sha
            else
              return Positions::Indeterminate.new(reason: :positioning_requires_right_path, range:)
            end
          end

          if @subject_type == :file
            return Positions::File.new(
              path:,
              commit_oid:,
              range:,
            )
          end

          # If the comment is not on a file, validate that we have an "end position" line number.
          if end_line_number.nil?
            return Positions::Indeterminate.new(reason: :line_requires_end_line_number, range:)
          end

          # Legacy multiline comments span `start_line...line` and have a side and start_side.
          # If we don't have a start_side, then it is a single line comment.
          unless start_side = @start_side
            return Positions::Line.new(
              line: end_line_number,
              path:,
              commit_oid:,
              range:,
            )
          end

          if start_side == :left
            start_line_number = @start_line_numbers[0]

            if base_path = @base_path
              start_path = base_path
              start_commit_oid = @base_sha
            else
              return Positions::Indeterminate.new(reason: :multiline_requires_left_start_path, range:)
            end
          else
            start_line_number = @start_line_numbers[1]

            if head_path = @head_path
              start_path = head_path
              start_commit_oid = @head_sha
            else
              return Positions::Indeterminate.new(reason: :multiline_requires_right_start_path, range:)
            end
          end

          # If the comment is not on a file, validate that we have an "end position" line number.
          if start_line_number.nil?
            return Positions::Indeterminate.new(reason: :multiline_requires_start_line_number, range:)
          end

          # After all validations pass, we have a valid multiline comment position.
          Positions::Multiline.new(
            start_path:,
            start_line: start_line_number,
            start_commit_oid:,
            end_path: path,
            end_line: end_line_number,
            end_commit_oid: commit_oid,
            range:,
          )
        end
      end
    end
  end
end
