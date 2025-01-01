# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Processors
        # Processes diff-relative positioning inputs for comment creation.
        #
        # This processor handles the legacy diff-based comment positioning where comments
        # are specified by their position within a diff hunk. It converts diff positions
        # into Position objects and associated column data.
        #
        # Behavior:
        #   - Accepts diff position (line number within diff) and resolves to blob coordinates
        #   - Only supports single-line comments (no multiline support for diff positioning)
        #   - Converts diff position to both blob-relative and diff-relative column formats
        #   - Validates that the diff position exists within the loaded diff data
        #   - Generates all necessary column data for database persistence
        #
        # Limitations:
        #   - Restricted to line-type positioning only (no file or multiline comments)
        #   - Requires valid diff data to be loaded for position resolution
        class DiffRelative
          sig { returns(Inputs::DiffRelative) }
          attr_reader :input

          sig { override.params(input: Inputs::DiffRelative, command: Command).void }
          def initialize(input:, command:)
            @input = input
            @command = command
          end

          sig { void }
          def prepare
            @command.add_path_to_diff_batch(base_commit_oid:, head_commit_oid:, path:)
          end

          sig { returns(Values) }
          def call
            # Resolve blob positioning from the diff position.
            blob_positioning = @command.blob_positioning_for(
              base_commit_oid:, head_commit_oid:, path:, position:,
              start_position_offset: nil
            )

            # Return error if diff position cannot be resolved to valid blob lines.
            if blob_positioning.is_a?(CommentPosition::Errors)
              return blob_positioning
            end

            # Diff positioning always results in single-line comments only.
            positioning = Positions::Line.new(
              line: blob_positioning.end_line,
              path: blob_positioning.end_path,
              commit_oid: blob_positioning.end_commit_oid,
              base_commit_oid:,
              head_commit_oid:,
            )

            compressed_diff_hunk = @command.diff_hunk_for(
              base_commit_oid:, head_commit_oid:, path:, position:
            )

            Result.new(
              positioning:,
              original_positioning: positioning,

              blob_columns: Columns::BlobLine.new(
                blob_position: positioning.line.pred,
                blob_path: positioning.path,
                blob_commit_oid: positioning.commit_oid
              ),

              diff_columns: Columns::DiffLine.new(
                path:,
                position:,
                outdated: false,
                commit_id:,
              ),

              immutable_columns: Columns::Immutable.new(
                original_commit_id: commit_id,
                original_position: position,
                original_base_commit_id: base_commit_oid,
                original_start_commit_id: base_commit_oid,
                original_end_commit_id: head_commit_oid,
                subject_type: Enums::SubjectType::Line,
                start_position_offset: nil,
                compressed_diff_hunk:,
                left_blob: blob_positioning.left_blob,
              ),
            )
          end

          private

          sig { returns(String) }
          def base_commit_oid = input.base_commit_oid

          sig { returns(String) }
          def head_commit_oid = input.head_commit_oid

          # For diff-relative positioning, commit_id always refers to the head commit.
          alias commit_id head_commit_oid

          sig { returns(String) }
          def path = input.path

          sig { returns(Integer) }
          def position = input.position
        end
      end
    end
  end
end
