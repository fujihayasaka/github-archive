# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Results
        # Result builder for line-level positions.
        # Receives a Locations::State containing all location lifecycle data.
        class Line < T::Struct
          const :input, Positioner::Inputs::Types
          const :source_range, Types::CommitRange
          const :target_range, Types::CommitRange
          const :state, Locations::State
          const :location, Locations::Line
          const :compressed_diff_hunk, T.nilable(String), default: nil

          sig { returns(Types::ResolvedLocation) }
          def input_location = state.input_location

          sig { returns(T.nilable(Locations::Context)) }
          def source_context = state.source_context

          sig { returns(T.nilable(Locations::Context)) }
          def destination_context = state.destination_context

          sig { returns(T::Boolean) }
          def retargeted? = source_range != target_range

          sig { returns(T.nilable(Integer)) }
          def position = destination_context&.position

          sig { returns(T.nilable(Integer)) }
          def line_on_head
            context = destination_context
            # For resolved lines, use head_line from context
            # For lines outside diff, also use head_line (which should be set to the line number)
            return context.head_line if context&.head_line
            # Fallback for lines targeting head with no context
            location.targeting_base? ? nil : location.line
          end

          sig { returns(T::Boolean) }
          def line_on_context?
            context = destination_context
            return true if context.nil? || context.outside_diff?
            context.line_type == Enums::LineType::Context
          end

          sig { returns(T::Boolean) }
          def line_on_context = line_on_context?

          sig { returns(T::Boolean) }
          def line_outside_diff?
            context = destination_context
            context.nil? || context.outside_diff? || !context.resolved?
          end

          sig { returns(T::Boolean) }
          def line_outside_diff = line_outside_diff?

          sig { returns(Enums::Side) }
          def side
            location.targeting_base? ? Enums::Side::Left : Enums::Side::Right
          end

          sig { returns(String) }
          def commit_oid = location.commit_oid

          sig { returns(T.nilable(Integer)) }
          def hunk = destination_context&.hunk

          sig { returns(String) }
          def path = location.path

          # Generate a Result value compatible with the previous Positioner implementation.
          sig { returns(T.any(Positioner::Result, CommentPosition::Errors)) }
          def to_legacy_result
            # Only return errors for creation inputs (Blobs, DiffRelative)
            # For repositioning (ThreadColumns), always return a Result
            if input.creation?
              if error = state.error
                return error
              end

              # Positioning inputs provide exact coordinates. Even when the diff is too
              # large (ContentTooLarge) or the line was removed during retarget, the
              # coordinates are still valid. The result will be outdated/indeterminate
              # rather than an error. Only Blobs and DiffRelative inputs need failure
              # checks because their coordinates depend on diff resolution.
              unless input.is_a?(Positioner::Inputs::Positioning)
                if (error = source_context&.to_error(path:, line: location.line))
                  return error
                elsif blobs_validation_failed?
                  return CommentPosition::Errors::Path.new(path:)
                end
              end
            end

            Positioner::Result.new(
              positioning:,
              previous_positioning:,
              original_positioning:,
              immutable_columns:,
              diff_columns:,
              blob_columns:,
            )
          end

          private

          # Check if blob validation failed for a Blobs input outside the diff.
          # For Blobs input (REST API creation), lines outside the diff require blob validation
          # to verify the path/line exists. If we're outside the diff but the context is not
          # fully resolved with valid line data, treat it as a validation failure.
          sig { returns(T::Boolean) }
          def blobs_validation_failed?
            context = destination_context || source_context
            return false if context.nil?

            # If we're outside the diff, the path must have been validated via blobs.
            # A valid blob validation would either:
            # 1. Set state.error (for invalid paths) - caught earlier in to_legacy_result
            # 2. Provide valid line numbers in context
            # If we're outside the diff with no valid line in context, validation didn't run.
            return false unless context.outside_diff?

            # For lines outside the diff, we expect the context to have line data from blob validation.
            # If head_line is nil (for right-side comments) or base_line is nil (for left-side),
            # the path/line wasn't validated successfully.
            if location.targeting_base?
              context.base_line.nil?
            else
              context.head_line.nil?
            end
          end

          sig { returns(Positions) }
          def positioning
            base_commit_oid, head_commit_oid = target_range
            context = destination_context

            # If destination couldn't be resolved and isn't outside the diff, return Indeterminate.
            # Outside-diff comments are valid - they just don't have a diff position.
            # They still need a proper Line positioning for storage and context injection.
            unless context&.resolved? || context&.outside_diff?
              return Positions::Indeterminate.new(
                reason: :cannot_resolve_position,
                base_commit_oid:,
                head_commit_oid:,
              )
            end

            # For ThreadColumns, use stored positioning if it matches target range
            # This preserves object identity for equality comparisons
            stored = stored_positioning
            if stored.is_a?(Positions::Line)
              stored
            else
              location.to_positioning
            end
          end

          # Returns stored positioning from ThreadColumns input if it matches target range
          sig { returns(T.nilable(Positions)) }
          def stored_positioning
            target_base_oid, target_head_oid = target_range

            case input_value = input
            when Positioner::Inputs::ThreadColumns
              [input_value.latest_positioning, input_value.original_positioning].compact.find do |pos|
                pos.base_commit_oid == target_base_oid && pos.head_commit_oid == target_head_oid
              end
            end
          end

          sig { returns(T.any(Positioner::Columns::DiffLine, Positioner::Columns::DiffOutdated)) }
          def diff_columns
            context = destination_context
            path = context&.head_path || location.path
            position = context&.position
            commit_id = target_range[1]

            # If the input was previously outdated, it stays outdated forever.
            # Once a comment becomes outdated, it cannot be "un-outdated".
            if input_previously_outdated?
              return Positioner::Columns::DiffOutdated.new(path:, commit_id:)
            end

            if position
              Positioner::Columns::DiffLine.new(path:, position:, commit_id:, outdated: false)
            else
              Positioner::Columns::DiffOutdated.new(path:, commit_id:)
            end
          end

          sig { returns(T::Boolean) }
          def input_previously_outdated?
            case input_value = input
            when Positioner::Inputs::ThreadColumns
              input_value.outdated
            else
              false
            end
          end

          sig { returns(T.nilable(Positions)) }
          def previous_positioning
            if retargeted?
              case location = input_location
              when Locations::Line
                location.to_positioning
              when Locations::File, Locations::Invalid
                nil
              else
                T.absurd(location)
              end
            end
          end

          sig { returns(Positions) }
          def original_positioning
            case input = self.input
            when Positioner::Inputs::ThreadColumns
              original_positioning = input.original_positioning
              return original_positioning if original_positioning
            end

            source_location = state.input_location
            original_base, original_head = source_range

            case source_location
            when Locations::Line
              Positions::Line.new(
                path: source_location.path,
                line: source_location.line,
                commit_oid: source_location.targeting_base? ? original_base : original_head,
                base_commit_oid: original_base,
                head_commit_oid: original_head,
              )
            else
              Positions::Indeterminate.new(
                reason: :cannot_compute_original_positioning,
                base_commit_oid: original_base,
                head_commit_oid: original_head,
              )
            end
          end

          sig { returns(Positioner::Columns::Immutable) }
          def immutable_columns
            base_commit_oid, head_commit_oid = source_range

            Positioner::Columns::Immutable.new(
              original_commit_id: head_commit_oid,
              original_position: source_context&.position,
              original_base_commit_id: base_commit_oid,
              original_start_commit_id: base_commit_oid,
              original_end_commit_id: head_commit_oid,
              subject_type: Positioner::Enums::SubjectType::Line,
              left_blob: location.targeting_base?,
              start_position_offset: nil,
              compressed_diff_hunk: compressed_diff_hunk || previous_compressed_diff_hunk,
            )
          end

          sig { returns(T.nilable(String)) }
          def previous_compressed_diff_hunk
            case input = self.input
            when Positioner::Inputs::ThreadColumns
              input.compressed_diff_hunk
            end
          end

          sig { returns(Positioner::Columns::BlobLine) }
          def blob_columns
            Positioner::Columns::BlobLine.new(
              blob_position: location.line.pred,
              blob_path: location.path,
              blob_commit_oid: location.commit_oid,
            )
          end
        end
      end
    end
  end
end
