# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Requests
        # Request for multi-line positions (comments spanning multiple lines).
        #
        # == Structure
        #
        # A multiline comment has two locations:
        # - **end_state**: The ending (anchor) line. This is the "primary" position and
        #   is used for most operations. The end line is stored first because comments
        #   are typically anchored to their end position in the UI.
        # - **start_state**: The starting line of the range. Combined with end, defines
        #   the highlighted span.
        #
        # Both states track the same location through the positioning pipeline independently,
        # because the lines may shift differently (e.g., if code was inserted between them).
        #
        # == Validation
        #
        # Before converting to a result, we validate that both locations resolved to the
        # same file (blob). A multiline comment cannot span multiple files - if the paths
        # diverge after resolution, the comment is invalid.
        class Multiline < T::Struct
          const :input, Positioner::Inputs::Types
          const :target_range, Types::CommitRange
          const :end_state, Locations::State
          const :start_state, Locations::State
          const :needs_diff_hunk, T::Boolean, default: true

          # Compressed diff hunk string (mutable - set by processor)
          prop :compressed_diff_hunk, T.nilable(String), default: nil

          sig { returns(Types::CommitRange) }
          def source_range = end_state.source_range

          sig { returns(T::Array[Locations::State]) }
          def states = [end_state, start_state]

          sig { returns(T::Boolean) }
          def needs_diff_hunk? = needs_diff_hunk

          # Converts the request to a final result after location resolution.
          #
          # Validation order:
          # 1. Check that both locations resolved to the same file (blob validation)
          # 2. Check that both locations are valid Line objects
          #
          # If either check fails, we return Invalid with the appropriate error.
          # Error priority: blob mismatch first (more specific), then location invalidity.
          sig { returns(T.any(Results::Multiline, Results::Invalid)) }
          def to_result
            # Validate multiline spans same blob BEFORE checking individual locations.
            # This catches the case where both locations are valid Lines but point to
            # different files (e.g., file was renamed and lines diverged).
            if (blob_error = determine_different_blob_error)
              # For creation (source == target), path mismatch is always an error.
              # For repositioning, path mismatch means paths diverged during retargeting,
              # which should be Indeterminate (no hard error).
              retargeted = source_range != target_range

              return Results::Invalid.new(
                input:, source_range:, target_range:, start_state:,
                state: end_state,
                error: (blob_error unless retargeted),
              )
            end

            end_location = end_state.location
            start_location = start_state.location

            # Both locations must resolve to Line for a valid multiline result.
            # File locations don't make sense for multiline (no line numbers).
            # Invalid locations indicate resolution failure.
            if end_location.is_a?(Locations::Line) && start_location.is_a?(Locations::Line)
              Results::Multiline.new(input:, end_state:, start_state:, end_location:, start_location:, source_range:, target_range:, compressed_diff_hunk:)
            else
              end_input = end_state.input_location
              start_input = start_state.input_location
              retargeted = source_range != target_range

              # Derive error from whichever location failed. Prefer end_location error
              # since it's the primary anchor point.
              # Only set error for:
              # 1. Source validation failure (input was invalid from the start)
              # 2. Creation inputs (Blobs) where target failed
              # For repositioning (ThreadColumns with retargeting), target failure → no error, just Indeterminate
              error = if end_input.is_a?(Locations::Invalid)
                # Source input was invalid - always an error
                CommentPosition::Errors.from_outcome(outcome: end_input.outcome, path: end_input.path, line: end_input.line)
              elsif start_input.is_a?(Locations::Invalid)
                # Source input was invalid - always an error
                CommentPosition::Errors.from_outcome(outcome: start_input.outcome, path: start_input.path, line: start_input.line)
              elsif input.creation? && !retargeted
                # Creation - target failure is an error
                if end_location.is_a?(Locations::Invalid)
                  CommentPosition::Errors.from_outcome(outcome: end_location.outcome, path: end_location.path, line: end_location.line)
                elsif start_location.is_a?(Locations::Invalid)
                  CommentPosition::Errors.from_outcome(outcome: start_location.outcome, path: start_location.path, line: start_location.line)
                end
              end

              Results::Invalid.new(
                input:, source_range:, target_range:, start_state:, error:,
                state: end_state,
              )
            end
          end

          private

          # Validates that start and end locations target the same blob (file).
          #
          # Computes effective path for each location: prefer head_path from context
          # (which reflects file renames), otherwise fall back to the location's path.
          # This matches how Results::Multiline computes the final path for diff_columns.
          #
          # Returns nil if paths match, or a Path error if they don't.
          sig { returns(T.nilable(CommentPosition::Errors::Path)) }
          def determine_different_blob_error
            # Compute effective path for each location (same logic as diff_columns)
            end_path = end_state.destination_context&.head_path || end_state.location.path
            start_path = start_state.destination_context&.head_path || start_state.location.path

            return nil if end_path == start_path

            # Paths don't match - different blobs
            CommentPosition::Errors::Path.new(path: "cannot span multiple files")
          end
        end
      end
    end
  end
end
