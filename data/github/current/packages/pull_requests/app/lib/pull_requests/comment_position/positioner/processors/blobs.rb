# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Processors
        # Processes legacy blob positioning format inputs into consistent positional data.
        #
        # This processor handles the traditional blob-based comment positioning used by legacy APIs,
        # converting blob coordinates (line numbers, file paths, commit OIDs) into modern Position
        # objects while maintaining backward compatibility. This could easily support outside
        # the diff positioning.
        #
        # Behavior:
        #   - Validates that the target blob exists within the diff range
        #   - Enforces diff-relative positioning requirements from legacy behavior
        #   - Converts blob coordinates to both diff-relative and blob-relative column formats
        #   - Handles all file, single-line, and multiline comment positioning
        #
        # Limitations:
        #   - Requires diff positioning validation (no outside-the-diff comments)
        #   - Maintains legacy validation constraints for backward compatibility
        class Blobs
          sig { returns(Inputs::Blobs) }
          attr_reader :input

          sig { params(input: Inputs::Blobs, command: Command).void }
          def initialize(input:, command:)
            @input = input
            @command = command
          end

          sig { void }
          def prepare
            @command.add_path_to_diff_batch(base_commit_oid:, head_commit_oid:, path: input.path)
          end

          sig { returns(Values) }
          def call
            # Build blob column data directly from input parameters.
            blob_columns = begin
              case subject_type = @input.subject_type
              when Enums::SubjectType::Line
                # Validate that blob position is provided for line comments.
                return CommentPosition::Errors::Line.new unless blob_position = @input.blob_position

                Columns::BlobLine.new(blob_position:, blob_path:, blob_commit_oid:)
              when Enums::SubjectType::File
                Columns::BlobFile.new(blob_path:, blob_commit_oid:)
              else T.absurd(subject_type)
              end
            end

            # Resolve diff positioning to validate blob exists within the diff range.
            diff_positioning = @command.diff_positioning_for(
              start_line: @input.start_line,
              end_line: @input.end_line,
              path: @input.path,
              start_side:, end_side:,
              base_commit_oid:, head_commit_oid:,
            )

            # Enforce legacy constraint: blob must exist in diff (no outside-the-diff comments).
            if diff_positioning.is_a?(CommentPosition::Errors)
              return diff_positioning
            end

            # Convert blob coordinates to Position objects based on comment type.
            positioning = begin
              case blob_columns
              when Columns::BlobFile
                Positions::File.new(
                  path: blob_path,
                  commit_oid: blob_commit_oid,
                  base_commit_oid:, head_commit_oid:,
                )
              when Columns::BlobLine
                if start_line = @input.start_line
                  # Multiline comment: requires both start and end positioning.
                  Positions::Multiline.new(
                    end_commit_oid: blob_commit_oid,
                    end_path: blob_path,
                    end_line: blob_columns.line,
                    start_commit_oid: @input.start_commit_oid,
                    start_path: start_side.left? ? diff_positioning.left_path : diff_positioning.right_path,
                    start_line:,
                    base_commit_oid:, head_commit_oid:,
                  )
                else
                  # Single-line comment: only end positioning needed.
                  Positions::Line.new(
                    line: blob_columns.line,
                    commit_oid: blob_columns.blob_commit_oid,
                    path: blob_columns.blob_path,
                    base_commit_oid:, head_commit_oid:,
                  )
                end
              end
            end

            # Generate diff-relative column data for database persistence.
            diff_columns = begin
              position = diff_positioning.position
              start_position_offset = diff_positioning.start_position_offset
              path = blob_columns.blob_path

              case positioning
              when Positions::Multiline
                if position != nil && start_position_offset != nil
                  Columns::DiffLine.new(outdated: false, path:, commit_id:, position:)
                else
                  # Both start and end diff positions are required for multiline comments.
                  return Errors::Line.new
                end
              when Positions::Line
                if position != nil
                  Columns::DiffLine.new(outdated: false, path:, commit_id:, position:)
                else
                  # End diff position is required for line comments.
                  return Errors::Line.new
                end
              when Positions::File
                Columns::DiffFile.new(outdated: false, path:, commit_id:)
              else T.absurd(positioning)
              end
            end

            # Create immutable column data for historical tracking and repositioning.
            immutable_columns = begin
              compressed_diff_hunk = @command.diff_hunk_for(
                base_commit_oid:, head_commit_oid:, path:, position:
              )

              Columns::Immutable.new(
                original_commit_id: commit_id,
                original_position: position,
                original_base_commit_id: base_commit_oid,
                original_start_commit_id: base_commit_oid,
                original_end_commit_id: head_commit_oid,
                subject_type: subject_type,
                start_position_offset:,
                left_blob: end_side.left?,
                compressed_diff_hunk:,
              )
            end

            Result.new(
              positioning:,
              original_positioning: positioning,
              diff_columns:, blob_columns:, immutable_columns:,
            )
          end

          private

          sig { returns(String) }
          def base_commit_oid = @input.base_commit_oid

          sig { returns(String) }
          def head_commit_oid = @input.head_commit_oid

          # For diff-relative positioning, commit_id always refers to the head commit.
          alias commit_id head_commit_oid

          sig { returns(Enums::Side) }
          def end_side = @input.side

          sig { returns(T.nilable(Integer)) }
          def start_line = @input.start_line

          sig { returns(Enums::Side) }
          def start_side = @input.start_side

          sig { returns(String) }
          def blob_path = @input.blob_path

          sig { returns(String) }
          def blob_commit_oid = @input.blob_commit_oid
        end
      end
    end
  end
end
