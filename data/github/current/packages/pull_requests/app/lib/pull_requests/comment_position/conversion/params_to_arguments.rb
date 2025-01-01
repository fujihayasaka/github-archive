# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Conversion
      # Convert the Positions API type to the arguments utilized within the existing
      # CreateNewPullRequestReviewCommentOrchestration.
      module ParamsToArguments
        extend self

        class Arguments < T::Struct
          const :diff_base_commit_id, String
          const :diff_start_commit_id, String
          const :diff_end_commit_id, String
          const :path, String
          const :side, Symbol
          const :start_side, T.nilable(Symbol)
          const :line, T.nilable(Integer)
          const :start_line, T.nilable(Integer)
          const :subject_type, Symbol
          const :positioning, Positions
        end

        sig do
          params(
            positioning: T.nilable(T::Hash[T.untyped, T.untyped]),
            base_commit_oid: String,
            head_commit_oid: String,
          ).returns(T.any(Arguments, CommentPosition::Errors))
        end
        def convert(positioning:, base_commit_oid:, head_commit_oid:)
          # See: CreateNewPullRequestReviewCommentOrchestration
          diff_base_commit_id = base_commit_oid
          diff_start_commit_id = base_commit_oid
          diff_end_commit_id = head_commit_oid

          case positioning = Positions::Parser.parse(positioning, base_commit_oid:, head_commit_oid:)
          when CommentPosition::Errors
            positioning
          when Positions::File
            Arguments.new(
              diff_base_commit_id:,
              diff_start_commit_id:,
              diff_end_commit_id:,
              side: positioning.commit_oid == base_commit_oid ? :left : :right,
              path: positioning.path,
              subject_type: :file,
              positioning:,
            )
          when Positions::Line
            Arguments.new(
              diff_base_commit_id:,
              diff_start_commit_id:,
              diff_end_commit_id:,
              path: positioning.path,
              side: positioning.commit_oid == base_commit_oid ? :left : :right,
              line: positioning.line - 1,
              subject_type: :line,
              positioning:,
            )
          when Positions::Multiline
            Arguments.new(
              diff_base_commit_id:,
              diff_start_commit_id:,
              diff_end_commit_id:,
              path: positioning.end_path,
              side: positioning.end_commit_oid == base_commit_oid ? :left : :right,
              start_side: positioning.start_commit_oid == base_commit_oid ? :left : :right,
              line: positioning.end_line - 1,
              start_line: positioning.start_line - 1,
              subject_type: :line,
              positioning:,
            )
          when Positions::Indeterminate, Positions::Errored
            CommentPosition::Errors::Parameter.new(position: "indeterminate")
          end
        end
      end
    end
  end
end
