# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Loaders
        module Results
          # Represents a resolved position within a diff, containing line coordinates on both sides
          # (base and head), the match type, and the outcome of the resolution attempt.
          class Diff < T::Struct
            # Type alias for the subset of Outcome values that can occur in diff resolution
            Outcomes = T.type_alias do
              T.any(
                # Success states
                Enums::Outcome::Current,
                Enums::Outcome::OutsideDiff,
                Enums::Outcome::Unknown,
                # Failure states
                Enums::Outcome::DiffNotLoaded,
                Enums::Outcome::DiffInvalid,
                Enums::Outcome::GitUnavailable,
                Enums::Outcome::ContentTooLarge,
                Enums::Outcome::LineRemoved,
                Enums::Outcome::PathRemoved,
              )
            end

            const :match_type, Enums::MatchType
            const :position, T.nilable(Integer)
            const :base_line, T.nilable(Integer)
            const :base_path, T.nilable(String)
            const :head_line, T.nilable(Integer)
            const :head_path, T.nilable(String)
            const :hunk, T.nilable(Integer)

            # Nil when not resolved (e.g., outside diff or failed).
            const :line_type, T.nilable(Enums::LineType)

            const :outcome, Outcomes, default: Enums::Outcome::Unknown

            sig { returns(T::Boolean) }
            def not_in_diff? = match_type == Enums::MatchType::NotInDiff

            sig { returns(T::Boolean) }
            def closest_match? = match_type == Enums::MatchType::Closest

            # A diff result is only "failed" if we couldn't match the path at all (NotResolved).
            # NotInDiff with a failure outcome (e.g., ContentTooLarge) means we matched the path
            # but couldn't get position details - this is not a hard failure, just incomplete data.
            sig { returns(T::Boolean) }
            def failed? = match_type == Enums::MatchType::NotResolved

            sig { returns(T::Boolean) }
            def resolved? = match_type == Enums::MatchType::Exact

            sig do
              params(
                position: T.nilable(Integer),
                base_line: T.nilable(Integer),
                base_path: T.nilable(String),
                head_line: T.nilable(Integer),
                head_path: T.nilable(String),
                hunk: T.nilable(Integer),
                line_type: T.nilable(Enums::LineType),
              ).returns(Diff)
            end
            def self.exact(position: nil, base_line: nil, base_path: nil, head_line: nil, head_path: nil, hunk: nil, line_type: nil)
              new(
                position:, base_line:, base_path:, head_line:, head_path:, hunk:, line_type:,
                match_type: Enums::MatchType::Exact,
                outcome: Enums::Outcome::Current,
              )
            end

            sig { params(outcome: Outcomes).returns(Diff) }
            def self.failure(outcome:) = new(match_type: Enums::MatchType::NotResolved, outcome:)
          end
        end
      end
    end
  end
end
