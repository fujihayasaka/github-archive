# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Results
        # Result builder for multiline positions.
        # Receives two Locations::State instances for end and start locations.
        class Multiline < T::Struct
          const :input, Positioner::Inputs::Types
          const :source_range, Types::CommitRange
          const :target_range, Types::CommitRange
          const :end_state, Locations::State
          const :start_state, Locations::State
          const :end_location, Locations::Line
          const :start_location, Locations::Line
          const :compressed_diff_hunk, T.nilable(String), default: nil

          sig { returns(T::Boolean) }
          def retargeted? = source_range != target_range

          sig { returns(T.nilable(Integer)) }
          def end_position = end_state.destination_context&.position

          sig { returns(T.nilable(Integer)) }
          def end_line_on_head
            context = end_state.destination_context
            # For resolved lines, use head_line from context
            # For lines outside diff, also use head_line (which should be set to the line number)
            return context.head_line if context&.head_line
            # Fallback for lines targeting head with no context
            end_location.targeting_base? ? nil : end_location.line
          end

          sig { returns(T::Boolean) }
          def end_line_on_context?
            context = end_state.destination_context
            return true if context.nil? || context.outside_diff?
            context.line_type == Enums::LineType::Context
          end

          sig { returns(T::Boolean) }
          def end_line_on_context = end_line_on_context?

          sig { returns(T::Boolean) }
          def end_line_outside_diff?
            context = end_state.destination_context
            context.nil? || context.outside_diff? || !context.resolved?
          end

          sig { returns(T::Boolean) }
          def end_line_outside_diff = end_line_outside_diff?

          sig { returns(Enums::Side) }
          def end_side = end_location.targeting_base? ? Enums::Side::Left : Enums::Side::Right

          sig { returns(String) }
          def end_commit_oid = end_location.commit_oid

          sig { returns(T.nilable(Integer)) }
          def end_hunk = end_state.destination_context&.hunk

          sig { returns(String) }
          def end_path = end_location.path

          # Start position methods
          sig { returns(T.nilable(Integer)) }
          def start_position = start_state.destination_context&.position

          sig { returns(T.nilable(Integer)) }
          def start_line_on_head
            context = start_state.destination_context

            if line = context&.head_line
              # For resolved lines, use head_line from context
              # For lines outside diff, also use head_line (which should be set to the line number)
              line
            elsif start_location.targeting_base?
              # Fallback for lines targeting head with no context
              nil
            else
              start_location.line
            end
          end

          sig { returns(T::Boolean) }
          def start_line_on_context?
            context = start_state.destination_context

            if context.nil? || context.outside_diff?
              true
            else
              context.line_type == Enums::LineType::Context
            end
          end

          sig { returns(T::Boolean) }
          def start_line_on_context = start_line_on_context?

          sig { returns(T::Boolean) }
          def start_line_outside_diff?
            context = start_state.destination_context
            context.nil? || context.outside_diff? || !context.resolved?
          end

          sig { returns(T::Boolean) }
          def start_line_outside_diff = start_line_outside_diff?

          sig { returns(Enums::Side) }
          def start_side = start_location.targeting_base? ? Enums::Side::Left : Enums::Side::Right

          sig { returns(String) }
          def start_commit_oid = start_location.commit_oid

          sig { returns(T.nilable(Integer)) }
          def start_hunk = start_state.destination_context&.hunk

          sig { returns(String) }
          def start_path = start_location.path

          # Multiline-specific methods
          sig { returns(T::Boolean) }
          def spans_multiple_hunks?
            start_hunk = self.start_hunk
            end_hunk = self.end_hunk

            if start_hunk.nil? && end_hunk.nil?
              # If both are outside diff (nil hunk), they don't span multiple hunks
              false
            elsif start_hunk.nil? || end_hunk.nil?
              # If one is in a hunk and one is outside, they span the boundary
              true
            else
              # If both are in hunks, check if they're in the same hunk
              start_hunk != end_hunk
            end
          end

          sig { returns(T.any(Positioner::Result, CommentPosition::Errors)) }
          def to_legacy_result
            # Only return errors for creation inputs (Blobs, DiffRelative)
            # For repositioning (ThreadColumns), always return a Result
            if input.creation?
              if (error = end_state.error || start_state.error)
                return error
              end

              # Positioning inputs provide exact coordinates. Even when the diff is too
              # large (ContentTooLarge) or the line was removed during retarget, the
              # coordinates are still valid. The result will be outdated/indeterminate
              # rather than an error. Only Blobs and DiffRelative inputs need failure
              # checks because their coordinates depend on diff resolution.
              unless input.is_a?(Positioner::Inputs::Positioning)
                if error = end_state.source_context&.to_error(path: end_location.path, line: end_location.line)
                  return error
                end

                if error = start_state.source_context&.to_error(path: start_location.path, line: start_location.line)
                  return error
                end
              end

              # Validate that start_position_offset is non-negative.
              # A negative offset means startLine has a higher diff position than line,
              # which indicates an invalid range (e.g., startLine > line on the same side,
              # or the lines span hunks in an incompatible order).
              start_position_offset = self.start_position_offset

              if start_position_offset && start_position_offset < 0
                return CommentPosition::Errors::StartPosition.new(position: start_location.line)
              end
            end

            Positioner::Result.new(positioning:, previous_positioning:, original_positioning:, immutable_columns:, diff_columns:, blob_columns:)
          end

          private

          sig { returns(Positioner::Columns::Diffs) }
          def diff_columns
            path = end_state.destination_context&.head_path || end_location.path
            position = end_state.destination_context&.position
            commit_id = target_range[1]

            # Rule 1: Previously outdated stays outdated forever
            if previously_outdated?
              return Positioner::Columns::DiffOutdated.new(path:, commit_id:)
            end

            start_position_offset = self.start_position_offset
            start_position_offset_was = previous_start_position_offset

            # Rule 2: For multiline, start_position_offset changing transitions to outdated
            if start_position_offset_was && start_position_offset_was != start_position_offset
              return Positioner::Columns::DiffOutdated.new(path:, commit_id:)
            end

            # Rule 3: Must have valid position and start_position_offset
            if position && start_position_offset
              Positioner::Columns::DiffLine.new(path:, position:, commit_id:, outdated: false)
            else
              Positioner::Columns::DiffOutdated.new(path:, commit_id:)
            end
          end

          sig { returns(Positions) }
          def positioning
            base_commit_oid, head_commit_oid = target_range

            # If destination couldn't be resolved and isn't outside the diff, return Indeterminate.
            # Outside-diff comments are valid - they just don't have a diff position.
            # They still need a proper Multiline positioning for storage and context injection.
            end_context = end_state.destination_context
            start_context = start_state.destination_context

            end_valid = end_context&.resolved? || end_context&.outside_diff?
            start_valid = start_context&.resolved? || start_context&.outside_diff?

            unless end_valid && start_valid
              return Positions::Indeterminate.new(
                reason: :cannot_resolve_position,
                base_commit_oid:,
                head_commit_oid:,
              )
            end

            Positions::Multiline.new(
              end_path: end_location.path,
              end_line: end_location.line,
              end_commit_oid: end_location.commit_oid,
              start_path: start_location.path,
              start_line: start_location.line,
              start_commit_oid: start_location.commit_oid,
              base_commit_oid:,
              head_commit_oid:,
            )
          end

          sig { returns(Positioner::Columns::BlobLine) }
          def blob_columns
            Positioner::Columns::BlobLine.new(
              blob_position: end_location.line.pred,
              blob_path: end_location.path,
              blob_commit_oid: end_location.commit_oid,
            )
          end

          sig { returns(T.nilable(Positions)) }
          def previous_positioning
            base_commit_oid, head_commit_oid = source_range
            start_location = start_state.input_location
            end_location = end_state.input_location

            return unless retargeted?
            return unless start_location.is_a?(Locations::Line)
            return unless end_location.is_a?(Locations::Line)

            Positions::Multiline.new(
              end_path: end_location.path,
              end_line: end_location.line,
              end_commit_oid: end_location.commit_oid,
              start_path: start_location.path,
              start_line: start_location.line,
              start_commit_oid: start_location.commit_oid,
              base_commit_oid:,
              head_commit_oid:,
            )
          end

          sig { returns(Positioner::Columns::Immutable) }
          def immutable_columns
            base_commit_oid, head_commit_oid = source_range

            Positioner::Columns::Immutable.new(
              original_commit_id: head_commit_oid,
              original_position: end_state.source_context&.position,
              original_base_commit_id: base_commit_oid,
              original_start_commit_id: base_commit_oid,
              original_end_commit_id: head_commit_oid,
              start_position_offset: previous_start_position_offset || start_position_offset,
              compressed_diff_hunk: compressed_diff_hunk || input_compressed_diff_hunk,
              left_blob: end_location.targeting_base?,
              subject_type: Positioner::Enums::SubjectType::Line,
            )
          end

          sig { returns(Positions) }
          def original_positioning
            case input = self.input
            when Positioner::Inputs::ThreadColumns
              original_positioning = input.original_positioning
              return original_positioning if original_positioning
            end

            start_source = start_state.input_location
            end_source = end_state.input_location
            original_base, original_head = source_range

            if start_source.is_a?(Locations::Line) && end_source.is_a?(Locations::Line)
              Positions::Multiline.new(
                start_path: start_source.path,
                start_line: start_source.line,
                start_commit_oid: start_source.targeting_base? ? original_base : original_head,
                end_path: end_source.path,
                end_line: end_source.line,
                end_commit_oid: end_source.targeting_base? ? original_base : original_head,
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

          sig { returns(T.nilable(String)) }
          def input_compressed_diff_hunk
            case input = self.input
            when Positioner::Inputs::ThreadColumns
              input.compressed_diff_hunk
            end
          end

          sig { returns(T::Boolean) }
          def previously_outdated?
            case input = self.input
            when Positioner::Inputs::ThreadColumns
              input.outdated
            else
              false
            end
          end

          sig { returns(T.nilable(Integer)) }
          def previous_start_position_offset
            case input = self.input
            when Positioner::Inputs::ThreadColumns
              input.start_position_offset
            end
          end

          sig { returns(T.nilable(Integer)) }
          def start_position_offset
            start_position = start_state.destination_context&.position
            end_position = end_state.destination_context&.position

            if start_position && end_position
              end_position - start_position
            end
          end
        end
      end
    end
  end
end
