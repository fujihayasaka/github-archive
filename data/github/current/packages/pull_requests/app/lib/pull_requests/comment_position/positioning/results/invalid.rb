# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Results
        # Result builder for invalid/failed positions.
        # Receives a Locations::State and derives state from it.
        class Invalid < T::Struct
          const :input, Positioner::Inputs::Types
          const :source_range, Types::CommitRange
          const :target_range, Types::CommitRange
          const :state, Locations::State
          const :start_state, T.nilable(Locations::State), default: nil
          const :error, T.nilable(CommentPosition::Errors), default: nil

          sig { returns(T::Boolean) }
          def retargeted? = source_range != target_range

          # Generate a Result value compatible with the previous Positioner implementation.
          sig { returns(T.any(Positioner::Result, CommentPosition::Errors)) }
          def to_legacy_result
            # Check struct's own error (set by request validation, e.g., multiline path mismatch)
            # These are always hard errors regardless of creation vs repositioning.
            if (error = self.error)
              return error
            end

            if input.creation?
              # Check state.error (set by processor/command, e.g., only_changed_files rejection)
              if (state_error = state.error)
                return state_error
              end

              # ContentTooLarge is always a hard error for creation inputs.
              if outcome == Enums::Outcome::ContentTooLarge
                return CommentPosition::Errors::DiffEntryTooBig.new(path: path || "")
              end

              # Path-level failures: Whether to error depends on whether the source
              # resolution found the path in a diff.
              # - Source found path (Current/Repositioned): path was valid at source but
              #   removed at target → Indeterminate (outdated), not an error.
              # - Source did NOT find path (OutsideDiff/Unknown): path was never validated
              #   in any diff. For creation, this is a hard error — the path doesn't exist.
              #   OutsideDiff means the file wasn't in the source diff, and blob validation
              #   couldn't run because retarget already set the target to Invalid.
              if [Enums::Outcome::PathNotFound,
                  Enums::Outcome::PathRemoved,
                  Enums::Outcome::DiffNotLoaded].include?(outcome)
                source_outcome = source_context&.outcome
                source_found_path = source_outcome == Enums::Outcome::Current ||
                  source_outcome == Enums::Outcome::Repositioned
                unless retargeted? && source_found_path
                  return CommentPosition::Errors.from_outcome(outcome:, path:, line:, position:)
                end
              end

              # Line-level failures for non-retargeted creation are hard errors.
              # For retargeted creation, the line existed at the source range but was
              # removed at target → produce Indeterminate (outdated), not an error.
              unless retargeted?

                if input_location.is_a?(Locations::Invalid)
                  case outcome
                  when Enums::Outcome::LineRemoved
                    return CommentPosition::Errors.from_outcome(outcome:, path:, line:, position:)
                  end
                end

                # Fallback: return an error for any remaining known failure outcome
                if outcome == Enums::Outcome::LineRemoved
                  return CommentPosition::Errors.from_outcome(outcome:, path:, line:, position:)
                end
              end
            end

            # For repositioning cases where source was valid but target is invalid,
            # return Result with Indeterminate + previous_positioning
            Positioner::Result.new(
              positioning:,
              previous_positioning:,
              original_positioning: nil,
              immutable_columns:,
              diff_columns:,
              blob_columns:,
            )
          end

          private

          sig { returns(Enums::Outcome) }
          def outcome
            # First check if start_state has an Invalid blob (multiline where start failed)
            case start_location = start_state&.location
            when Locations::Invalid
              return start_location.outcome
            end

            # Otherwise check the primary state
            case location = state.location
            when Locations::Invalid
              location.outcome
            else
              Enums::Outcome::Unknown
            end
          end

          sig { returns(Types::ResolvedLocation) }
          def input_location = state.input_location

          sig { returns(T.nilable(Locations::Context)) }
          def source_context = state.source_context

          sig { returns(T.nilable(String)) }
          def path
            case input = self.input
            when Positioner::Inputs::DiffRelative, Positioner::Inputs::Blobs
              input.path
            when Positioner::Inputs::ThreadColumns
              input.path || input.blob_path
            when Positioner::Inputs::Positioning
              # Extract path from Positioning input's positioning
              case positioning = input.positioning
              when Positions::Line, Positions::File
                positioning.path
              when Positions::Multiline
                positioning.end_path
              else
                nil
              end
            else
              T.absurd(input)
            end
          end

          sig { returns(T.nilable(Integer)) }
          def position
            case input = self.input
            when Positioner::Inputs::DiffRelative, Positioner::Inputs::ThreadColumns
              input.position
            else
              nil
            end
          end

          sig { returns(T.nilable(Integer)) }
          def line
            case input = self.input
            when Positioner::Inputs::Blobs
              input.line
            when Positioner::Inputs::ThreadColumns
              input.blob_position&.next
            else
              nil
            end
          end

          sig { returns(Positions::Indeterminate) }
          def positioning
            base_commit_oid, head_commit_oid = target_range

            Positions::Indeterminate.new(
              reason: indeterminate_reason,
              base_commit_oid:,
              head_commit_oid:,
            )
          end

          sig { returns(Symbol) }
          def indeterminate_reason
            case outcome
            when Enums::Outcome::LineRemoved
              :cannot_reposition_line
            when Enums::Outcome::PathRemoved, Enums::Outcome::PathNotFound, Enums::Outcome::DiffNotLoaded
              :cannot_resolve_path
            when Enums::Outcome::ContentTooLarge
              :blob_contents_too_large
            when Enums::Outcome::MalformedInput
              :unexpected_blob_pattern
            else
              :unknown_error
            end
          end

          sig { returns(T.nilable(Positions)) }
          def previous_positioning
            return nil unless retargeted?

            case location = input_location
            when Locations::File, Locations::Line
              location.to_positioning
            end
          end

          sig { returns(T.nilable(Positioner::Columns::Immutable)) }
          def immutable_columns
            base_commit_oid, head_commit_oid = source_range

            case location = input_location
            when Locations::File, Locations::Line
              Positioner::Columns::Immutable.new(
                original_commit_id: head_commit_oid,
                original_base_commit_id: base_commit_oid,
                original_start_commit_id: base_commit_oid,
                original_end_commit_id: head_commit_oid,
                original_position: source_context&.position,
                start_position_offset:,
                subject_type: location.is_a?(Locations::File) ? Enums::SubjectType::File : Enums::SubjectType::Line,
                compressed_diff_hunk: nil,
                left_blob: location.targeting_base?,
              )
            when Locations::Invalid
              nil
            else
              T.absurd(location)
            end
          end

          sig { returns(T.nilable(Integer)) }
          def start_position_offset
            # Only compute offset for multiline cases where start_state exists
            start = start_state
            return nil unless start

            end_position = source_context&.position
            start_position = start.source_context&.position
            return nil unless end_position && start_position

            end_position - start_position
          end

          sig { returns(Positioner::Columns::DiffOutdated) }
          def diff_columns
            path = case location = input_location
            when Locations::File, Locations::Line
              location.path
            when Locations::Invalid
              location.path
            else
              T.absurd(location)
            end

            _, source_head_oid = source_range
            _, target_head_oid = target_range

            # For outdated (retargeted), commit_id should be the source head commit
            # For creation failures, commit_id should be target head commit
            Positioner::Columns::DiffOutdated.new(
              path:,
              commit_id: retargeted? ? source_head_oid : target_head_oid
            )
          end

          sig { returns(T.nilable(Positioner::Columns::Blobs)) }
          def blob_columns
            case location = input_location
            when Locations::File
              Positioner::Columns::BlobFile.new(
                blob_path: location.path,
                blob_commit_oid: location.commit_oid,
              )
            when Locations::Line
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
end
