# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Locations
        class Context < T::Struct
          # Immutable result from Resolver representing the outcome of a diff line query.
          # Contains all diff-derived values needed for positioning and column generation.
          # Context is embedded in Location structs - the location itself holds path/line/commit_oid.

          const :match_type, Enums::MatchType
          const :position, T.nilable(Integer)
          const :base_line, T.nilable(Integer)
          const :base_path, T.nilable(String)
          const :head_line, T.nilable(Integer)
          const :head_path, T.nilable(String)
          const :hunk, T.nilable(Integer)
          const :line_type, Enums::LineType, default: Enums::LineType::Context

          # Error Info - unified outcome captures both state and failure reason
          const :outcome, Enums::Outcome, default: Enums::Outcome::Unknown
          const :failed_from, T.nilable(Symbol), default: nil

          sig { returns(T::Boolean) }
          def resolved? = match_type == Enums::MatchType::Exact

          sig { returns(T::Boolean) }
          def exact_match? = match_type == Enums::MatchType::Exact

          sig { returns(T::Boolean) }
          def outside_diff? = match_type == Enums::MatchType::NotInDiff

          # Returns true if this context has an outcome indicating a terminal failure
          # that should prevent comment creation (path not found, line removed, etc.)
          sig { returns(T::Boolean) }
          def failure_outcome?
            [
              Enums::Outcome::PathNotFound,
              Enums::Outcome::PathRemoved,
              Enums::Outcome::LineRemoved,
              Enums::Outcome::ContentTooLarge,
              Enums::Outcome::DiffNotLoaded,
              Enums::Outcome::DiffInvalid,
              Enums::Outcome::GitUnavailable,
            ].include?(outcome)
          end

          # Determines if this context represents a left-side (deletion) position.
          # For Position-resolved contexts, uses the explicit from_deletion flag.
          # For Line/File contexts, returns nil (side is determined by location's commit_oid).
          sig { returns(T.nilable(T::Boolean)) }
          def targeting_base? = resolved? ? line_type == Enums::LineType::Deletion : nil

          # Converts this context's failure outcome to a CommentPosition::Errors instance.
          # Returns nil if the context does not represent a failure.
          sig { params(path: String, line: T.nilable(Integer)).returns(T.nilable(CommentPosition::Errors)) }
          def to_error(path:, line: nil)
            return nil unless failure_outcome?

            CommentPosition::Errors.from_outcome(outcome:, path:, line:)
          end

          # Factory method for creating an unresolved/default context
          sig { params(outcome: Enums::Outcome).returns(Locations::Context) }
          def self.unresolved(outcome: Enums::Outcome::Unknown)
            new(match_type: Enums::MatchType::NotResolved, outcome:)
          end

          # Factory method for creating a failed context
          sig { params(outcome: Enums::Outcome, failed_from: T.nilable(Symbol)).returns(Locations::Context) }
          def self.failure(outcome:, failed_from: nil)
            new(match_type: Enums::MatchType::NotResolved, outcome:, failed_from:)
          end
        end
      end
    end
  end
end
