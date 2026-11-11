# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Loaders
        module Results
          # Represents the result of repositioning a comment's line reference across commits.
          # Contains the new path/line if successful, or an error indicating why repositioning failed.
          class Reposition < T::Struct
            # Type alias for the subset of Outcome values that represent reposition errors
            Errors = T.type_alias { T.any(Enums::Outcome::PathRemoved, Enums::Outcome::LineRemoved) }

            const :success, T::Boolean
            const :path, T.nilable(String)
            const :line, T.nilable(Integer)
            const :error, T.nilable(Errors)

            alias success? success

            sig { returns(T::Boolean) }
            def failed? = !success

            sig { returns(Enums::Outcome) }
            def to_outcome
              error == Enums::Outcome::PathRemoved ? Enums::Outcome::PathRemoved : Enums::Outcome::LineRemoved
            end

            sig { params(path: String, line: T.nilable(Integer)).returns(Reposition) }
            def self.success(path:, line: nil) = new(success: true, path:, line:)

            sig { returns(Reposition) }
            def self.path_removed = new(success: false, error: Enums::Outcome::PathRemoved)

            sig { returns(Reposition) }
            def self.line_removed = new(success: false, error: Enums::Outcome::LineRemoved)
          end
        end
      end
    end
  end
end
