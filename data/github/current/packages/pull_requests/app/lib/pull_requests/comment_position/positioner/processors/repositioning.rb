# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Processors
        # Converts Position objects into database column values for PullRequestReviewThread records.
        #
        # This processor handles the core logic of translating Position objects into the various
        # column formats needed for database persistence and API responses. It's used both for
        # new comment creation and repositioning existing comments to new commit ranges.
        #
        # Behavior:
        #   - Converts Position objects to diff-relative, blob-relative, and immutable column formats
        #   - Handles outdated positioning by preserving previous values when appropriate
        #
        class Repositioning
          include GitHub::Memoizer

          sig { returns(Inputs::Positioning) }
          attr_reader :input

          sig do
            params(
              input: Inputs::Positioning,
              command: Command,
              previous_result: T.nilable(Result),
            ).void
          end
          def initialize(input:, command:, previous_result: nil)
            @input = input
            @command = command
            @previous_result = previous_result
          end

          sig { void }
          def prepare
            # Queue diff loading for valid positioning types only.
            case positioning = @input.positioning
            when Positions::Indeterminate, Positions::Errored
              # Skip preparation for invalid positioning data.
            when Positions::Line, Positions::File
              @command.add_path_to_diff_batch(base_commit_oid:, head_commit_oid:, path: positioning.path)
            when Positions::Multiline
              @command.add_path_to_diff_batch(base_commit_oid:, head_commit_oid:, path: positioning.start_path)
              @command.add_path_to_diff_batch(base_commit_oid:, head_commit_oid:, path: positioning.end_path)
            else T.absurd(positioning)
            end
          end

          sig { returns(Result) }
          def call
            # Handle invalid positioning by preserving previous state or returning minimal result.
            case positioning = @input.positioning
            when Positions::Indeterminate, Positions::Errored
              if @previous_result
                return Result.new(
                  positioning:,
                  original_positioning:,
                  diff_columns: previous_diff_columns&.as_outdated,
                  immutable_columns: previous_immutable_columns,
                  blob_columns: @previous_result.blob_columns,
                )
              else
                return Result.new(positioning:)
              end
            end

            # Generate diff-relative column data with outdated handling.
            diff_columns = begin
              diff_positioning = @command.diff_positioning_for(
                path:, start_side:, start_line:, end_line:, end_side:,
                base_commit_oid:, head_commit_oid:,
              )

              # When outdated, preserve previous values during repositioning to maintain consistency.
              case diff_positioning
              when CommentPosition::Errors::DiffNotLoaded   then nil
              when CommentPosition::Errors::DiffEntryTooBig then nil
              when CommentPosition::Errors::GitUnavailable  then nil
              when CommentPosition::Errors::DiffNotValid    then diff_outdated_columns
              when CommentPosition::Errors::Path            then diff_outdated_columns
              else
                if previous_diff_columns&.outdated
                  previous_diff_columns
                else
                  position = diff_positioning.position

                  case @input.positioning
                  when Positions::File
                    Columns::DiffFile.new(outdated: false, path:, commit_id:)
                  when Positions::Line
                    if position.nil?
                      diff_outdated_columns
                    else
                      Columns::DiffLine.new(outdated: false, position:, commit_id:, path:)
                    end
                  when Positions::Multiline
                    start_position_offset = diff_positioning.start_position_offset

                    if columns = @previous_result && @previous_result.immutable_columns
                      # Always marked as "outdated" if the start_position_offset ever changes.
                      start_position_offset_changed = columns.start_position_offset != start_position_offset
                    end

                    if start_position_offset.nil? || position.nil? || start_position_offset_changed
                      diff_outdated_columns
                    else
                      Columns::DiffLine.new(outdated: false, position:, path:, commit_id:)
                    end
                  else
                    diff_outdated_columns
                  end
                end
              end
            end

            # Reuse existing immutable columns or generate new ones for historical tracking.
            immutable_columns = previous_immutable_columns || begin
              compressed_diff_hunk = @command.diff_hunk_for(
                base_commit_oid:, head_commit_oid:, path:, position:
              )

              Columns::Immutable.new(
                original_commit_id: commit_id,
                original_position: position,
                original_base_commit_id: base_commit_oid,
                original_start_commit_id: base_commit_oid,
                original_end_commit_id: head_commit_oid,
                left_blob: end_side.left?,
                subject_type:,
                start_position_offset:,
                compressed_diff_hunk:,
              )
            end

            blob_columns = begin
              if blob_position = end_line&.pred
                Columns::BlobLine.new(blob_position:, blob_path:, blob_commit_oid:)
              else
                Columns::BlobFile.new(blob_path:, blob_commit_oid:)
              end
            end

            Result.new(
              positioning:,
              original_positioning:,
              blob_columns:, diff_columns:, immutable_columns:,
            )
          end

          private

          sig { returns(String) }
          def base_commit_oid = @input.positioning.base_commit_oid

          sig { returns(String) }
          def head_commit_oid = @input.positioning.head_commit_oid

          # For diff-relative positioning, commit_id always references the head commit.
          sig { returns(String) }
          def commit_id = head_commit_oid

          sig { returns(Enums::Side) }
          def start_side = start_commit_oid == base_commit_oid ? Enums::Side::Left : Enums::Side::Right

          sig { returns(Enums::Side) }
          def end_side = end_commit_oid == base_commit_oid ? Enums::Side::Left : Enums::Side::Right

          sig { returns(T.any(Positions::File, Positions::Line, Positions::Multiline)) }
          def positioning
            case positioning = @input.positioning
            when Positions::Errored, Positions::Indeterminate
              # Ensure type safety - this method should only be called after validation.
              raise "unsupported type: #{positioning.inspect}"
            else
              positioning
            end
          end

          sig { returns(T.nilable(Integer)) }
          def start_line
            case positioning = self.positioning
            when Positions::Multiline
              positioning.start_line
            when Positions::File, Positions::Line
              nil
            else T.absurd(positioning)
            end
          end

          sig { returns(T.nilable(Integer)) }
          def end_line
            case positioning = self.positioning
            when Positions::Line
              positioning.line
            when Positions::Multiline
              positioning.end_line
            when Positions::File
              nil
            else T.absurd(positioning)
            end
          end

          sig { returns(T.nilable(String)) }
          def start_commit_oid
            case positioning = self.positioning
            when Positions::Multiline
              positioning.start_commit_oid
            when Positions::File, Positions::Line
              nil
            else T.absurd(positioning)
            end
          end

          sig { returns(String) }
          def end_commit_oid
            case positioning = self.positioning
            when Positions::Line, Positions::File
              positioning.commit_oid
            when Positions::Multiline
              positioning.end_commit_oid
            else T.absurd(positioning)
            end
          end

          alias blob_commit_oid end_commit_oid

          sig { returns(Enums::SubjectType) }
          def subject_type
            case positioning = self.positioning
            when Positions::Line, Positions::Multiline
              Enums::SubjectType::Line
            when Positions::File
              Enums::SubjectType::File
            else T.absurd(positioning)
            end
          end

          sig { returns(String) }
          def path
            case positioning = self.positioning
            when Positions::Line, Positions::File
              positioning.path
            when Positions::Multiline
              positioning.end_path
            else T.absurd(positioning)
            end
          end

          alias blob_path path

          sig { returns(T.nilable(Positions)) }
          def original_positioning = @previous_result&.original_positioning

          sig { returns(T.nilable(Columns::Diffs)) }
          def previous_diff_columns = @previous_result&.diff_columns

          sig { returns(T.nilable(Columns::Immutable)) }
          def previous_immutable_columns = @previous_result&.immutable_columns

          sig { returns(Columns::DiffOutdated) }
          memoize def diff_outdated_columns

            Columns::DiffOutdated.new(
              commit_id: previous_diff_columns&.commit_id || commit_id,
              path: previous_diff_columns&.path || path,
            )
          end
        end
      end
    end
  end
end
