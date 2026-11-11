# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Results
        # Result builder for file-level positions.
        # Receives a Locations::State containing all location lifecycle data.
        class File < T::Struct
          const :input, Positioner::Inputs::Types
          const :state, Locations::State
          const :source_range, Types::CommitRange
          const :target_range, Types::CommitRange
          const :location, Locations::File

          sig { returns(Enums::Side) }
          def side
            location.targeting_base? ? Enums::Side::Left : Enums::Side::Right
          end

          sig { returns(String) }
          def commit_oid = location.commit_oid

          sig { returns(String) }
          def path = location.path

          sig { returns(T.any(Positioner::Result, CommentPosition::Errors)) }
          def to_legacy_result
            # Only return errors for creation inputs (Blobs, DiffRelative)
            # For repositioning (ThreadColumns), always return a Result
            if input.creation?
              if error = state.error
                return error
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

          sig { returns(Positions) }
          def positioning
            base_commit_oid, head_commit_oid = target_range
            context = state.destination_context

            # If destination couldn't be resolved and isn't outside the diff, return Indeterminate.
            # Outside-diff comments are valid - they just don't have a diff position.
            unless context&.resolved? || context&.outside_diff?
              return Positions::Indeterminate.new(
                reason: :cannot_resolve_position,
                base_commit_oid:,
                head_commit_oid:,
              )
            end

            location.to_positioning
          end

          sig { returns(T.nilable(Positions)) }
          def previous_positioning
            return nil if source_range == target_range

            case location = state.input_location
            when Locations::File
              location.to_positioning
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
            when Locations::File
              Positions::File.new(
                path: source_location.path,
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
              original_position: nil,
              original_base_commit_id: base_commit_oid,
              original_start_commit_id: base_commit_oid,
              original_end_commit_id: head_commit_oid,
              start_position_offset: nil,
              subject_type: Enums::SubjectType::File,
              compressed_diff_hunk: nil,
              left_blob: location.targeting_base?,
            )
          end

          sig { returns(Positioner::Columns::DiffFile) }
          def diff_columns
            # For file-level, outdated is based on whether destination context is resolved
            # not on position (files don't have positions)
            _, head_commit_oid = target_range

            Positioner::Columns::DiffFile.new(
              path: location.path,
              outdated: !state.destination_context&.resolved?,
              commit_id: head_commit_oid,
            )
          end

          sig { returns(Positioner::Columns::BlobFile) }
          def blob_columns
            # For ThreadColumns, preserve original blob columns from input
            case input = self.input
            when Positioner::Inputs::ThreadColumns
              if (blob_path = input.blob_path) && (blob_commit_oid = input.blob_commit_oid)
                return Positioner::Columns::BlobFile.new(blob_path:, blob_commit_oid:)
              end
            end

            # Default: compute from location
            Positioner::Columns::BlobFile.new(
              blob_path: location.path,
              blob_commit_oid: location.commit_oid
            )
          end
        end
      end
    end
  end
end
