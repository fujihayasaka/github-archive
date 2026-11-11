# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      # Base module for positioning result types.
      #
      # == Purpose
      #
      # Results represent the final output of the positioning pipeline. They contain:
      # - The resolved location (where the comment should appear)
      # - Context about how resolution occurred (match type, outcome, etc.)
      # - Methods to convert to external formats (Positions, Columns, legacy Result)
      #
      # == Result Types
      #
      # - **Results::Line**: Single-line comment resolved successfully
      # - **Results::Multiline**: Multi-line comment (both start and end resolved)
      # - **Results::File**: File-level comment (no specific line)
      # - **Results::Invalid**: Resolution failed, contains error details
      #
      # == Conversion Methods
      #
      # Results can be converted to multiple formats:
      #
      # 1. **to_result**: Returns Positioner::Result for legacy API compatibility.
      #    Wraps the Positions struct with success/error status.
      #
      # 2. **to_positions** (on concrete types): Creates a Positions struct for storage.
      #    This is the canonical representation stored in the database.
      #
      # 3. **to_columns** (on concrete types): Creates concrete column structs representing
      #    the various permutations column states.
      #
      # == Indeterminate Handling
      #
      # When resolution fails, we create a Positions::Indeterminate with a reason
      # symbol. The indeterminate_from_outcome helper maps Outcome enums to these
      # legacy reason symbols for backwards compatibility.
      module Results
        extend T::Helpers

        abstract!

        # Converts this result to the legacy Positioner::Result format.
        # Returns either a successful Result wrapping a Positions struct,
        # or a CommentPosition::Errors object for failures.
        sig { abstract.returns(T.any(Positioner::Result, CommentPosition::Errors)) }
        def to_result; end

        # The base commit OID of the target range (left side of diff).
        sig { abstract.returns(String) }
        def target_base_commit_oid; end

        # The head commit OID of the target range (right side of diff).
        sig { abstract.returns(String) }
        def target_head_commit_oid; end

        # Creates an Indeterminate position for the target range with the given reason.
        # Used when resolution fails and we need to signal why.
        sig { params(reason: Symbol).returns(Positions::Indeterminate) }
        def indeterminate(reason) = Positions::Indeterminate.new(reason:, base_commit_oid: target_base_commit_oid, head_commit_oid: target_head_commit_oid)

        # Converts an Outcome to an Indeterminate position if it's a failure.
        # Returns nil for success outcomes (no indeterminate needed).
        #
        # This maps our precise Outcome values to the legacy reason symbols
        # expected by external APIs.
        sig { params(outcome: Enums::Outcome).returns(T.nilable(Positions::Indeterminate)) }
        def indeterminate_from_outcome(outcome)
          reason = case outcome
          when Enums::Outcome::Current, Enums::Outcome::Repositioned, Enums::Outcome::OutsideDiff
            nil
          when Enums::Outcome::DiffNotLoaded, Enums::Outcome::PathRemoved, Enums::Outcome::PathNotFound
            :cannot_resolve_path
          when Enums::Outcome::LineRemoved
            :cannot_reposition_line
          when Enums::Outcome::ContentTooLarge
            :blob_contents_too_large
          when Enums::Outcome::Unknown
            :unknown_error
          end

          reason ? indeterminate(reason) : nil
        end
      end
    end
  end
end
