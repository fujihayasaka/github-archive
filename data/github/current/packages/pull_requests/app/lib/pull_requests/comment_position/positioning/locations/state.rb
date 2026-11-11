# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Locations
        # Tracks a location's evolution through the processor pipeline.
        # This is the sole mutable unit - the processor transforms State instances,
        # and Results consume the final state.
        #
        # Lifecycle:
        #   input (Phase 0) → source (Phase 1: Normalize) → target (Phase 2-3: Retarget + Reprocess)
        #
        # Each location carries its own context - set during resolution.
        # Context flows through the locations themselves, not as separate props.
        class State < T::Struct
          # Commit ranges (immutable context) - [base_oid, head_oid]
          const :source_range, [String, String]  # where location came from
          const :target_range, [String, String]  # where location needs to go

          # Phase 0: Input - the original coordinates (immutable)
          # Can include Position (diff-relative) which must be resolved in Phase 1
          const :input, Types::UnresolvedLocation  # File, Line, Position, or Invalid

          # Phase 1: Source - resolved at source range (after Normalize)
          # Position is eliminated here - only File, Line, or Invalid remain
          prop :source, T.nilable(Types::ResolvedLocation), default: nil

          # Phase 2-3: Target - resolved at target range (after Retarget + Reprocess)
          # Location now carries its own context
          prop :target, T.nilable(Types::ResolvedLocation), default: nil

          # Error detected during resolution (e.g., path not in diff for only_changed_files mode)
          # Mutable: set during resolution if an error condition is detected
          prop :error, T.nilable(CommentPosition::Errors), default: nil

          # The final resolved location (for positioning)
          sig { returns(Types::ResolvedLocation) }
          def location
            target || source || resolved_input
          end

          # The input location after Phase 1 resolution (for previous_positioning)
          # Returns source if available, otherwise converts input to ResolvedLocation
          sig { returns(Types::ResolvedLocation) }
          def input_location
            source || resolved_input
          end

          # Converts UnresolvedLocation to ResolvedLocation
          # Position without resolution becomes Invalid
          sig { returns(Types::ResolvedLocation) }
          def resolved_input
            case input = self.input
            when Locations::File, Locations::Line, Locations::Invalid
              input
            when Locations::Position
              # Position without resolution is Invalid - should not happen after Phase 1
              Locations::Invalid.new(
                outcome: Enums::Outcome::LineRemoved,
                path: input.path,
                commit_oid: input.commit_range[1], # Use head commit
                commit_range: input.commit_range,
              )
            else
              T.absurd(input)
            end
          end

          # Is the location up to date (targeting commit matches between source and target range)?
          # A location only targets one side of the range (base or head via commit_oid).
          # We only need to retarget if that specific commit differs between ranges.
          sig { returns(T::Boolean) }
          def up_to_date?
            case location = source || input
            when Locations::Line, Locations::File
              if location.targeting_base?
                source_range[0] == target_range[0]
              else
                source_range[1] == target_range[1]
              end
            when Locations::Position
              # Position needs full range match since it's diff-relative
              source_range == target_range
            when Locations::Invalid
              true # Invalid locations don't need retargeting
            else
              T.absurd(location)
            end
          end

          # Can this location be repositioned (valid source/input and not already failed)?
          sig { returns(T::Boolean) }
          def repositionable?
            case location = (source || input)
            when Locations::File, Locations::Line, Locations::Position
              true
            when Locations::Invalid
              false
            else
              T.absurd(location)
            end
          end

          # Get the path from the final location
          sig { returns(T.nilable(String)) }
          def path = location.path

          # Is this location valid (not Invalid)?
          sig { returns(T::Boolean) }
          def valid? = !location.is_a?(Locations::Invalid)

          # Get the source context from source location (for backward compatibility)
          sig { returns(T.nilable(Locations::Context)) }
          def source_context = source&.context

          # Get the destination context from the final location (for backward compatibility)
          sig { returns(T.nilable(Locations::Context)) }
          def destination_context = location.context
        end
      end
    end
  end
end
