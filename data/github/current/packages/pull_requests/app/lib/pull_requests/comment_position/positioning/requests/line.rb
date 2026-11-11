# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Requests
        # Request for single-line positions.
        #
        # == Structure
        #
        # A line comment has one state that tracks the location through the pipeline.
        # The state contains both the input location and the resolved location after
        # processing.
        #
        # == Input Variations
        #
        # This request type handles multiple input location types:
        # - **Line**: Direct line number reference (e.g., "line 42 of file.rb")
        # - **Position**: Legacy diff-relative position (e.g., "position 15 in the diff")
        #
        # Both resolve to a Line location in the result. Position inputs go through
        # diff resolution to convert the position offset into actual line numbers.
        class Line < T::Struct
          const :input, Positioner::Inputs::Types
          const :target_range, Types::CommitRange
          const :state, Locations::State
          const :needs_diff_hunk, T::Boolean, default: true

          # Compressed diff hunk string (mutable - set by processor)
          prop :compressed_diff_hunk, T.nilable(String), default: nil

          sig { returns(Types::CommitRange) }
          def source_range = state.source_range

          sig { returns(T::Array[Locations::State]) }
          def states = [state]

          sig { returns(T.nilable(Locations::State)) }
          def end_state = state

          sig { returns(T::Boolean) }
          def needs_diff_hunk? = needs_diff_hunk

          # Converts the request to a final result after location resolution.
          #
          # The resolved location type determines the result:
          # - **Line**: Expected case. Creates a valid Line result.
          # - **File**: Unexpected for a Line request. Returns Invalid.
          # - **Invalid**: Resolution failed. Propagates the failure with full context.
          sig { returns(T.any(Results::Line, Results::Invalid)) }
          def to_result
            case location = state.location
            when Locations::Line
              Results::Line.new(input:, state:, location:, source_range:, target_range:, compressed_diff_hunk:)
            when Locations::File
              # A Line request should never resolve to a File location.
              # This indicates a bug in the factory or resolution logic.
              Results::Invalid.new(input:, source_range:, target_range:, state:, error: CommentPosition::Errors::Unknown.new)
            when Locations::Invalid
              # Resolution failed. Extract the original position from input if available
              # to provide better error context (e.g., "position 15 not found").
              case input = self.input
              when Positioner::Inputs::DiffRelative
                position = input.position
              end

              # Determine if this is a source validation failure or target retargeting failure.
              # - Source validation failure: Always error
              #   - input_location is Invalid (diff resolution failed)
              #   - state.error is set (blob validation failed after diff resolution)
              #   - input is Blobs without retargeting (REST API creation - direct validation)
              # - Target retargeting failure (source is valid, target is Invalid): Indeterminate
              #   - The original position was valid but couldn't be tracked to target
              blobs_creation = input.is_a?(Positioner::Inputs::Blobs) && source_range == target_range
              if state.input_location.is_a?(Locations::Invalid) || state.error || blobs_creation
                # Source validation failed - always error
                # Use the pre-set error if available (from blob validation), otherwise build from outcome
                error = state.error || CommentPosition::Errors.from_outcome(
                  outcome: location.outcome,
                  path: location.path,
                  line: location.line,
                  position:,
                )
              end

              Results::Invalid.new(input:, source_range:, target_range:, state:, error:)
            else
              T.absurd(location)
            end
          end
        end
      end
    end
  end
end
