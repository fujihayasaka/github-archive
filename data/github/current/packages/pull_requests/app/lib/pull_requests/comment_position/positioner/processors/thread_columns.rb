# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Processors
        # Converts existing PullRequestReviewThread database records into consistent positional format.
        #
        # This processor transforms stored database column values into Position objects, optimizing
        # for cases where positional data is already available and avoiding unnecessary git operations.
        #
        # Behavior:
        #   - Early returns if latest_positioning is already available, skipping all git operations
        #   - Translates database column values to Position objects without requiring git calls
        #   - Only calls git when processing multiline comments where start_position_offset requires
        #     resolving the actual line number in the file blob from diff data
        #   - Handles both single-line and multiline comments with different resolution strategies
        #   - Falls back to blob-based positioning when diff data is unavailable or outdated
        #
        # Performance optimizations:
        #   - Skips diff loading when blob data is sufficient for positioning
        #   - Reuses existing positioning data when available
        #   - Minimizes git operations by leveraging cached database values
        class ThreadColumns
          include GitHub::Memoizer

          sig { returns(Inputs::ThreadColumns) }
          attr_reader :input

          sig { params(input: Inputs::ThreadColumns, command: Command).void }
          def initialize(input:, command:)
            @input = input
            @command = command
          end

          sig { void }
          def prepare
            # Only load diff data when blob data is insufficient for positioning. This guard is duplicated
            # in the call method to prevent unnecessary diff loading during batch preparation.
            # Note: Sorbet type narrowing requires this duplication to be somewhat verbose.
            if @input.start_position_offset != nil || blob_columns.nil?
              case diff_columns = self.diff_columns
              when Columns::DiffLine, Columns::DiffFile
                @command.add_path_to_diff_batch(
                  path: diff_columns.path,
                  base_commit_oid:, head_commit_oid:
                )
              end
            end

            # Resolve original positioning if we don't have one.
            if @input.original_positioning.nil? && path = @input.path
              if immutable_columns = self.immutable_columns
                @command.add_path_to_diff_batch(
                  base_commit_oid: immutable_columns.original_start_commit_id,
                  head_commit_oid: immutable_columns.original_end_commit_id,
                  path:
                )
              end
            end
          end

          sig { returns(Values) }
          def call
            # If we don't have a valid path the entire thread is invalid/errored. This shouldn't be possible but the
            # database schema allows it.
            path = @input.path
            return Errors::Path.new(path:) if path.nil? || path.blank?

            diff_columns = self.diff_columns
            blob_columns = self.blob_columns
            start_position_offset = @input.start_position_offset

            original_positioning = begin
              # Attempt to reuse the database value if we can.
              database_value = case value = @input.original_positioning
              when Positions::Line, Positions::Multiline, Positions::File, Positions::Indeterminate
                value
              when Positions::Errored
                nil
              end

              if database_value
                database_value
              elsif immutable_columns = self.immutable_columns
                # When we don't have a valid database value,
                original_base_commit_oid = immutable_columns.original_start_commit_id
                original_head_commit_oid = immutable_columns.original_end_commit_id
                original_position = immutable_columns.original_position

                # We're a file level comment, we just need to determine the path name.
                computed_positioning = if @input.subject_type.file? || original_position.nil?
                  positioning_for_file(
                    base_commit_oid: original_base_commit_oid,
                    head_commit_oid: original_head_commit_oid,
                    path:,
                  )
                else
                  positioning_from_diff_positions(
                    base_commit_oid: original_base_commit_oid,
                    head_commit_oid: original_head_commit_oid,
                    position: original_position,
                    path:, start_position_offset:,
                  )
                end

                case computed_positioning
                when Positions::Errored
                  nil
                else
                  computed_positioning
                end
              end
            end

            # Resolve the positioning, this is effectively latest_positioning.
            positioning = begin
              if eligible_positioning = eligible_positioning_column_value(original_positioning:)
                eligible_positioning
              elsif start_position_offset != nil || blob_columns.nil?
                # Generate Position structure from diff-relative column values. We must use the diff if the blob columns
                # are invalid _or_ the comment is mutliline as we only store the start_position_offset and not the start_line.
                case diff_columns
                when Columns::DiffLine
                  positioning_from_diff_positions(
                    path: diff_columns.path,
                    position: diff_columns.position,
                    start_position_offset:, base_commit_oid:, head_commit_oid:,
                  )
                # File comments with diff-relative positioning aren't valid for repositioning.
                when Columns::DiffFile     then indeterminate(:missing_positional_data)
                when Columns::DiffOutdated then indeterminate(:outdated)
                else T.absurd(diff_columns)
                end
              else
                # The blob_* fields are only updated in synchronization process when a force push occurs and the tracked
                # commit OID is no longer in the "rev_list" of the PR's comparison.
                if @input.left_blob
                  blob_base_commit_oid = blob_columns.blob_commit_oid
                  blob_head_commit_oid = head_commit_oid
                else
                  blob_base_commit_oid = base_commit_oid
                  blob_head_commit_oid = blob_columns.blob_commit_oid
                end

                case blob_columns
                when Columns::BlobFile
                  Positions::File.new(
                    path: blob_columns.blob_path,
                    commit_oid: blob_columns.blob_commit_oid,
                    base_commit_oid: blob_base_commit_oid,
                    head_commit_oid: blob_head_commit_oid,
                  )
                when Columns::BlobLine
                  Positions::Line.new(
                    line: blob_columns.blob_position.next,
                    path: blob_columns.blob_path,
                    commit_oid: blob_columns.blob_commit_oid,
                    base_commit_oid:, head_commit_oid:
                  )
                else T.absurd(blob_columns)
                end
              end
            end

            Result.new(positioning:, original_positioning:, diff_columns:, blob_columns:, immutable_columns:)
          end

          private

          sig do
            params(
              path: String,
              position: Integer,
              start_position_offset: T.nilable(Integer),
              base_commit_oid: String,
              head_commit_oid: String,
            ).returns(T.any(Positions::Line, Positions::Multiline, Positions::Indeterminate, Positions::Errored))
          end
          def positioning_from_diff_positions(path:, position:, start_position_offset:, base_commit_oid:, head_commit_oid:)
            case blob_positioning =
              @command.blob_positioning_for(path:, position:, start_position_offset:, base_commit_oid:, head_commit_oid:)
            when Errors::Path             then return indeterminate(:cannot_resolve_path)
            when Errors::Position         then return indeterminate(:cannot_resolve_position)
            when Errors::StartPosition    then return indeterminate(:cannot_resolve_start_position)
            when Errors::DiffNotLoaded    then return indeterminate(:cannot_resolve_diff)
            when Errors::DiffEntryTooBig  then return indeterminate(:diff_entry_too_big)
            when Errors::DiffNotValid     then return indeterminate(:cannot_resolve_commit_range)
            when Errors::GitUnavailable   then return Positions::Errored.new(exception: nil, base_commit_oid:, head_commit_oid:)
            end

            line = end_line = blob_positioning.end_line
            path = end_path = blob_positioning.end_path
            commit_oid = end_commit_oid = blob_positioning.end_commit_oid
            start_line = blob_positioning.start_line
            start_path = blob_positioning.start_path
            start_commit_oid = blob_positioning.start_commit_oid

            if start_position_offset.nil?
              Positions::Line.new(line:, path:, commit_oid:, base_commit_oid:, head_commit_oid:)
            elsif start_line.nil?
              indeterminate(:cannot_resolve_start_line)
            elsif start_path.nil?
              indeterminate(:cannot_resolve_start_path)
            elsif start_commit_oid.nil?
              indeterminate(:cannot_resolve_start_commit_oid)
            else
              Positions::Multiline.new(end_line:, end_path:, end_commit_oid:, start_line:, start_path:, start_commit_oid:, base_commit_oid:, head_commit_oid:)
            end
          end

          sig do
            params(
              path: String,
              base_commit_oid: String,
              head_commit_oid: String,
            ).returns(T.any(Positions::File, Positions::Indeterminate, Positions::Errored))
          end
          def positioning_for_file(path:, base_commit_oid:, head_commit_oid:)
            case diff_positioning = @command.diff_positioning_for(
              start_line: nil,
              start_side: Enums::Side::Right,
              end_line: nil,
              end_side: @input.side,
              base_commit_oid:, head_commit_oid:, path:,
            )
            when Errors::Path             then return indeterminate(:cannot_resolve_path)
            when Errors::DiffNotLoaded    then return indeterminate(:cannot_resolve_diff)
            when Errors::DiffEntryTooBig  then return indeterminate(:diff_entry_too_big)
            when Errors::DiffNotValid     then return indeterminate(:cannot_resolve_commit_range)
            when Errors::GitUnavailable   then return Positions::Errored.new(exception: nil, base_commit_oid:, head_commit_oid:)
            end

            Positions::File.new(
              path: (@input.left_blob ? diff_positioning.left_path : diff_positioning.right_path),
              commit_oid: (@input.left_blob ? base_commit_oid : head_commit_oid),
              base_commit_oid:, head_commit_oid:,
            )
          end

          sig { params(original_positioning: T.nilable(Positions)).returns(T.nilable(Positions)) }
          def eligible_positioning_column_value(original_positioning:)
            positions = [
              @input.latest_positioning,
              original_positioning
            ].compact

            # Skip if we don't have any positions.
            return if positions.empty?

            # Determine if there's a position that matches the current commit range.
            positioning = positions.find do |position|
              position.base_commit_oid == @input.base_commit_oid &&
                position.head_commit_oid == @input.head_commit_oid
            end

            return positioning if positioning

            # Next look for any valid positioning to eventually attempt to reposition to the requested pair.
            positioning = positions.find do |position|
              case position
              when Positions::File, Positions::Line, Positions::Multiline
                position
              when Positions::Indeterminate, Positions::Errored
                nil # Not valid for positioning/repositioning.
              else T.absurd(position)
              end
            end

            return positioning if positioning

            # Finally just resolve the first position we might have. If we have a position, utilize it as the other
            # column values are computed from these.
            positions.first
          end

          sig { returns(String) }
          def base_commit_oid
            if @input.left_blob && blob_commit_oid = @input.blob_commit_oid
              # This targets the right side of the diff that the previous positional behavior would use.
              blob_commit_oid
            else
              # Fallback to the pull_request.base_sha.
              @input.base_commit_oid
            end
          end

          sig { returns(String) }
          def head_commit_oid
            if commit_id = @input.commit_id
              # The commit_id is always the most recently synchronized head_sha.
              commit_id
            else
              # Fallback to the pull_request.head_sha.
              @input.head_commit_oid
            end
          end

          sig { returns(Columns::Diffs) }
          memoize def diff_columns
            path = @input.path
            commit_id = @input.commit_id
            outdated = @input.outdated
            position = @input.position
            start_position_offset = @input.start_position_offset

            if outdated || path.nil? || commit_id.nil?
              Columns::DiffOutdated.new(path:, commit_id:)
            elsif @input.subject_type.file?
              Columns::DiffFile.new(path:, commit_id:, outdated:)
            elsif position != nil
              Columns::DiffLine.new(path:, commit_id:, outdated:, position:)
            else
              Columns::DiffOutdated.new(path:, commit_id:)
            end
          end

          sig { returns(T.nilable(Columns::Blobs)) }
          memoize def blob_columns
            blob_path = @input.blob_path
            blob_commit_oid = @input.blob_commit_oid

            if blob_path.nil? || blob_commit_oid.nil?
              nil
            elsif @input.subject_type.file?
              Columns::BlobFile.new(blob_path:, blob_commit_oid:)
            elsif blob_position = @input.blob_position
              Columns::BlobLine.new(blob_commit_oid:, blob_position:, blob_path:)
            end
          end

          sig { returns(T.nilable(Columns::Immutable)) }
          def immutable_columns
            return unless original_commit_id = @input.original_commit_id
            return unless original_base_commit_id = @input.original_base_commit_id
            return unless original_start_commit_id = @input.original_start_commit_id
            return unless original_end_commit_id = @input.original_end_commit_id

            Columns::Immutable.new(
              original_position: @input.original_position,
              start_position_offset: @input.start_position_offset,
              subject_type: @input.subject_type,
              compressed_diff_hunk: @input.compressed_diff_hunk,
              left_blob: @input.left_blob,
              original_commit_id:, original_base_commit_id:, original_start_commit_id:, original_end_commit_id:,
            )
          end

          sig { params(reason: Symbol).returns(Positions::Indeterminate) }
          def indeterminate(reason) = Positions::Indeterminate.new(reason:, base_commit_oid:, head_commit_oid:)
        end
      end
    end
  end
end
