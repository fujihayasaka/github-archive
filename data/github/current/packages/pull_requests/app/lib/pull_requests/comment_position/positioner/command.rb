# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      # Command class that encapsulates side effects into a collection of single-purpose
      # methods that interact with external services while maintaining a strong boundary
      # between business logic and the rest of the domain.
      #
      # This class follows the command/query pattern, where each method is designed to
      # do one thing and do it very well. The Command provides a clean interface for:
      #
      # - Loading and validating diffs, blobs, and position data
      # - Converting between diff positions and blob positions
      # - Batching requests to minimize external service calls
      # - Generating diff hunks for position context
      #
      # The Command acts as the primary interface for external interactions within the
      # comment positioning system, ensuring that all side effects are contained and
      # controlled through well-defined method boundaries.
      class Command
        module Results
          class DiffPositioning < T::Struct
            const :position, T.nilable(Integer)
            const :start_position_offset, T.nilable(Integer)
            const :left_path, String
            const :right_path, String
          end

          class BlobPositioning < T::Struct
            const :start_line, T.nilable(Integer)
            const :start_path, T.nilable(String)
            const :start_commit_oid, T.nilable(String)
            const :start_side, T.nilable(Enums::Side)
            const :end_line, Integer
            const :end_path, String
            const :end_commit_oid, String
            const :end_side, Enums::Side

            sig { returns(T::Boolean) }
            def left_blob = end_side.left?
          end
        end

        sig { params(repository: Repository, base_commit_oid: String, head_commit_oid: String, diffs: T::Array[GitHub::Diff]).void }
        def initialize(repository:, base_commit_oid:, head_commit_oid:, diffs: [])
          @diffs = T.let(Loaders::Diffs.new(repository:, diffs:), Loaders::Diffs)
          @blobs_and_lines = T.let(Loaders::BlobsAndLines.new(repository:), Loaders::BlobsAndLines)
          @repositioning = T.let(Loaders::Repositioning.new(repository:, base_commit_oid:, head_commit_oid:), Loaders::Repositioning)
          @diff_positions = T.let(Loaders::DiffPositions.new(repository:), Loaders::DiffPositions)
        end

        # Adds a file path to the diff loading batch for later batch processing.
        sig { params(base_commit_oid: String, head_commit_oid: String, path: String).void }
        def add_path_to_diff_batch(base_commit_oid:, head_commit_oid:, path:)
          @diffs.add_to_batch(base_commit_oid:, head_commit_oid:, path:)
        end

        # Adds a blob path to the validation batch to check if the file and line exist at the given commit.
        sig { params(commit_oid: String, path: String, line: T.nilable(Integer)).void }
        def add_path_to_blob_and_lines(commit_oid:, path:, line:)
          @blobs_and_lines.add_to_batch(commit_oid:, path:, line:)
        end

        # Adds a position to the repositioning batch for later processing.
        sig { params(input: Inputs::Types, positioning: Positions).void }
        def add_to_repositioning_batch(input:, positioning:)
          @repositioning.add_to_batch(input, positioning)
        end

        # Adds an item to the diff positions batch for later processing.
        sig do
          params(
            base_commit_oid: String,
            head_commit_oid: String,
            start_path: String,
            start_commit_oid: String,
            end_path: String,
            end_commit_oid: String,
          ).void
        end
        def add_to_diff_positions_batch(base_commit_oid:, head_commit_oid:, start_path:, start_commit_oid:, end_path:, end_commit_oid:)
          return unless @diff_positions.enabled?

          # Early return if start and end commits match - no repositioning needed
          return if start_commit_oid == end_commit_oid

          # Paths match, this is already valid.
          return if start_path == end_path

          # Determine which path is targeting the head_commit_oid.
          if start_commit_oid == head_commit_oid
            source_path = start_path
          else
            source_path = end_path
          end

          # Since we're always checking head => base, hard code the source/target values.
          @diff_positions.add_to_batch(
            target_commit_oid: base_commit_oid,
            source_commit_oid: head_commit_oid,
            source_path:
          )
        end

        # Determine if the blob is the same across a commit range. Multiline comments have to store a copy of the path
        # for each side of the position. In order to validate that the path names resolve the same blob/object, we must
        # call the Repositioning code and translate from head_commit_oid => base_commit_oid. This is an optimization to remove
        # the need to deal with deletions.
        sig do
          params(
            base_commit_oid: String,
            head_commit_oid: String,
            start_path: String,
            start_commit_oid: String,
            end_path: String,
            end_commit_oid: String,
          ).returns(T.nilable(Errors::Path))
        end
        def resolve_same_blob(base_commit_oid:, head_commit_oid:, start_path:, start_commit_oid:, end_path:, end_commit_oid:)
          # Feature flagged guard to support disabling this if it causes any issues.
          return unless @diff_positions.enabled?

          # Early return if start and end commits match - no repositioning needed
          return nil if start_commit_oid == end_commit_oid

          # Paths match, this is already valid.
          return nil if start_path == end_path

          # Resolve the head/target based on which side is targeting the head_commit_oid.
          if start_commit_oid == head_commit_oid
            source_path = start_path
            target_path = end_path
          else
            source_path = end_path
            target_path = start_path
          end

          # Since we're always checking head => base, hard code the source/target values.
          resolved_path = @diff_positions.fetch(
            target_commit_oid: base_commit_oid,
            source_commit_oid: head_commit_oid,
            source_path:
          )

          # Validate that the head path matches the repositioned target path.
          if resolved_path != target_path
            Errors::Path.new(path: "cannot span multiple blobs")
          end
        end

        # Validates if a blob file and line exist at the specified commit.
        # Returns true if valid, or an error object if the path or line is invalid.
        sig { params(commit_oid: String, path: String, line: T.nilable(Integer)).returns(T.any(TrueClass, Errors::Line, Errors::Path)) }
        def resolve_blob_and_lines(commit_oid:, path:, line: nil)
          @blobs_and_lines.resolve(commit_oid:, path:, line:)
        end

        # Executes all batched data loading operations. Must be called before resolving positions.
        sig { void }
        def batch_load_data!
          @blobs_and_lines.load_batch!
          @diffs.load_batch!
        end

        # Determines if there are any pending positions not yet repositioned in the batch.
        sig { returns(T::Boolean) }
        def nothing_to_reposition? = @repositioning.loaded?

        # Iterates over each repositioned input in the batch.
        sig { params(block: T.proc.params(input: Inputs::Types, positioning: Positions).void).void }
        def each_repositioned_position(&block)
          @repositioning.each(&block)
        end

        # Converts blob line numbers and paths to diff hunk positions.
        # Returns positioning data or an error if the conversion fails.
        sig do
          params(
            base_commit_oid: String,
            head_commit_oid: String,
            path: String,
            start_line: T.nilable(Integer),
            start_side: Enums::Side,
            end_line: T.nilable(Integer),
            end_side: Enums::Side
          ).returns(T.any(
            Results::DiffPositioning,
            Errors::DiffNotLoaded,
            Errors::DiffEntryTooBig,
            Errors::Path,
            Loaders::Diffs::GitErrors,
          ))
        end
        def diff_positioning_for(base_commit_oid:, head_commit_oid:, path:, start_line:, start_side:, end_line:, end_side:)
          case entry = @diffs.entry_for(base_commit_oid:, head_commit_oid:, path:)
          when Errors::DiffNotLoaded, Errors::Path, Errors::DiffNotValid, Errors::GitUnavailable
            return entry
          end

          left_path = entry.a_path || entry.b_path
          right_path = entry.b_path || left_path

          # File level comments can skip the next steps.
          if end_line.nil?
            return Results::DiffPositioning.new(position: nil, start_position_offset: nil, left_path:, right_path:)
          end

          if entry.too_big?
            return Errors::DiffEntryTooBig.new(path: path)
          end

          position = T.let(
            entry.position_for(end_line.pred, end_side.left?),
            T.nilable(Integer)
          )

          if start_line
            start_position = T.let(
              entry.position_for(start_line.pred, start_side.left?),
              T.nilable(Integer)
            )
          end

          start_position_offset = if position && start_position
            position - start_position
          end

          Results::DiffPositioning.new(position:, start_position_offset:, left_path:, right_path:)
        end

        # Converts diff-based positions to blob positioning with 1-indexed line numbers.
        # Returns positioning data or an error if the conversion fails.
        sig do
          params(
            base_commit_oid: String,
            head_commit_oid: String,
            path: String,
            position: Integer,
            start_position_offset: T.nilable(Integer)
          ).returns(T.any(
            Results::BlobPositioning,
            Errors::DiffNotLoaded,
            Errors::DiffEntryTooBig,
            Errors::Path,
            Errors::Position,
            Errors::StartPosition,
            Loaders::Diffs::GitErrors,
          ))
        end
        def blob_positioning_for(base_commit_oid:, head_commit_oid:, path:, position:, start_position_offset: nil)
          case entry = @diffs.entry_for(base_commit_oid:, head_commit_oid:, path:)
          when Errors::DiffNotLoaded, Errors::Path, Errors::DiffNotValid, Errors::GitUnavailable
            return entry
          end

          if entry.too_big?
            return Errors::DiffEntryTooBig.new(path: path)
          end

          if start_position_offset.present?
            start_position = position - start_position_offset
          end

          start_diff_line = T.let(nil, T.nilable(GitHub::Diff::Line))
          end_diff_line = T.let(nil, T.nilable(GitHub::Diff::Line))

          entry.each_line do |line|
            line = T.let(line, GitHub::Diff::Line)

            if start_position && line.position == start_position
              start_diff_line = line
            end

            if line.position == position
              end_diff_line = line

              break
            end

            break if line.position > position
          end

          if end_diff_line.nil?
            return Errors::Position.new(position:)
          end

          if start_position_offset != nil && start_diff_line.nil?
            return Errors::StartPosition.new(position: start_position)
          end

          if start_diff_line
            if start_diff_line.addition? || end_diff_line.context?
              start_commit_oid = head_commit_oid
              start_path = entry.b_path || entry.a_path
              start_line = start_diff_line.right
              start_side = Enums::Side::Right
            else
              start_commit_oid = base_commit_oid
              start_path = entry.a_path || entry.b_path
              start_line = start_diff_line.left
              start_side = Enums::Side::Left
            end
          end

          if end_diff_line.addition? || end_diff_line.context?
            end_commit_oid = head_commit_oid
            end_path = entry.b_path || entry.a_path
            end_line = end_diff_line.right
            end_side = Enums::Side::Right
          else
            end_commit_oid = base_commit_oid
            end_path = entry.a_path || entry.b_path
            end_line = end_diff_line.left
            end_side = Enums:: Side::Left
          end

          Results::BlobPositioning.new(
            start_line:, start_path:, start_commit_oid:, start_side:,
            end_line:, end_path:, end_commit_oid:, end_side:,
          )
        end

        # Extract a compressed diff hunk containing the context around a specific position.
        # Returns the diff hunk as a string starting from the nearest hunk header (@@ line).
        # Returns nil if the position is nil or the diff entry cannot be found.
        # Read the "compressed diff hunk" for the path and position.
        sig do
          params(
            base_commit_oid: String,
            head_commit_oid: String,
            path: String,
            position: T.nilable(Integer)
          ).returns(T.nilable(String))
        end
        def diff_hunk_for(base_commit_oid:, head_commit_oid:, path:, position:)
          return nil if position.nil?

          entry = @diffs.entry_for(base_commit_oid:, head_commit_oid:, path:)
          return nil if entry.is_a?(Errors)

          # Borrowed from: PullRequestReviewComment::AbstractPositionData
          excerpt = []
          diff_lines = entry.lines

          position.downto(0).each do |index|
            line = diff_lines[index]
            excerpt.unshift(line)
            break if line[0] == "@"
          end

          excerpt.join("\n")
        end
      end
    end
  end
end
