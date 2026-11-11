# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Loaders
        module Results
          # Represents the result of validating that a file path exists and a line number is in range.
          # Contains the blob's line count if found, or an error indicating why validation failed.
          class Blob < T::Struct
            # Type alias for the subset of Outcome values that represent blob validation errors
            Errors = T.type_alias { T.any(Enums::Outcome::PathNotFound, Enums::Outcome::LineRemoved) }

            const :valid, T::Boolean
            const :line_count, T.nilable(Integer)
            const :error, T.nilable(Errors)

            alias valid? valid

            sig { returns(T::Boolean) }
            def invalid? = !valid?

            sig { returns(Enums::Outcome) }
            def to_outcome = error == Enums::Outcome::PathNotFound ? Enums::Outcome::PathNotFound : Enums::Outcome::LineRemoved

            sig { params(line_count: T.nilable(Integer)).returns(Blob) }
            def self.valid(line_count: nil) = new(valid: true, line_count:)

            sig { returns(Blob) }
            def self.path_not_found = new(valid: false, error: Enums::Outcome::PathNotFound)

            sig { params(line_count: T.nilable(Integer)).returns(Blob) }
            def self.line_out_of_range(line_count: nil) = new(valid: false, line_count:, error: Enums::Outcome::LineRemoved)
          end
        end
      end
    end
  end
end
