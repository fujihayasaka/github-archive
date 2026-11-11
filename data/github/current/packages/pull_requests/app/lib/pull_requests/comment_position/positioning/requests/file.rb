# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Requests
        # Request for file-level positions (comments attached to a file, not a line).
        #
        # == Structure
        #
        # File comments have no line number - they're attached to the file as a whole.
        #
        # == Processing
        #
        # File requests go through a simpler pipeline than Line requests:
        # - No line-level reposition needed (just path tracking for renames)
        # - No blob validation needed (no line number to validate)
        # - Diff resolution only checks if the file is in the diff
        class File < T::Struct
          const :input, Positioner::Inputs::Types
          const :target_range, Types::CommitRange
          const :state, Locations::State
          const :needs_diff_hunk, T::Boolean, default: false

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
          # - **File**: Expected case. Creates a valid File result.
          # - **Invalid**: Resolution failed (e.g., file not found). Propagates failure.
          # - **Line**: Unexpected for a File request. Returns Invalid.
          sig { returns(T.any(Results::File, Results::Invalid)) }
          def to_result
            case location = state.location
            when Locations::File
              Results::File.new(input:, state:, location:, source_range:, target_range:)
            when Locations::Invalid
              # Only set error for creation (not retargeted). For repositioning,
              # Invalid location means the file can't be found → outdated, not error.
              retargeted = source_range != target_range
              error = if input.creation? && !retargeted
                CommentPosition::Errors.from_outcome(
                  outcome: location.outcome,
                  path: location.path,
                )
              end

              Results::Invalid.new(input:, source_range:, target_range:, state:, error:)
            when Locations::Line
              # A File request should never resolve to a Line location.
              # This indicates a bug in the factory or resolution logic.
              Results::Invalid.new(
                input:, source_range:, target_range:, state:,
                error: CommentPosition::Errors::Unknown.new,
              )
            else
              T.absurd(location)
            end
          end
        end
      end
    end
  end
end
