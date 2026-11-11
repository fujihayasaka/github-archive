# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Processors
        # Validates Position objects and delegates to repositioning logic for comment creation.
        #
        # This processor handles direct Position object inputs, typically from APIs that provide
        # complete positional data. It validates the positioning data and delegates most processing
        # to the Repositioning processor while handling the creation-specific aspects.
        #
        # Behavior:
        #   - Validates that blob paths exist at specified commit OIDs before processing
        #   - Handles file, single-line, and multiline positioning validation
        #   - Delegates column generation to Repositioning processor for consistency
        #   - Ensures original_positioning is set correctly for new comment creation
        #   - Delegates to Repositioning processor for core logic to maintain consistency
        #
        class Positioning
          sig { returns(Inputs::Positioning) }
          attr_reader :input

          sig { params(input: Inputs::Positioning, command: Command, only_changed_files: T::Boolean).void }
          def initialize(input:, command:, only_changed_files:)
            @input = input
            @command = command
            @only_changed_files = only_changed_files
            @delegate = T.let(Repositioning.new(input:, command:), Repositioning)
          end

          sig { void }
          def prepare
            # Queue blob existence validation for all positioning types.
            case positioning = @input.positioning
            when Positions::File, Positions::Line
              if comment_only_on_changed_files?
                @command.add_path_to_diff_batch(
                  base_commit_oid:, head_commit_oid:,
                  path: positioning.path
                )
              end

              @command.add_path_to_blob_and_lines(
                commit_oid: positioning.commit_oid,
                path: positioning.path,
                line: positioning.is_a?(Positions::Line) ? positioning.line : nil
              )
            when Positions::Multiline
              @command.add_path_to_blob_and_lines(
                commit_oid: positioning.start_commit_oid,
                path: positioning.start_path,
                line: positioning.start_line
              )

              @command.add_path_to_blob_and_lines(
                commit_oid: positioning.end_commit_oid,
                path: positioning.end_path,
                line: positioning.end_line
              )

              @command.add_to_diff_positions_batch(
                base_commit_oid:, head_commit_oid:,
                start_commit_oid: positioning.start_commit_oid,
                start_path: positioning.start_path,
                end_commit_oid: positioning.end_commit_oid,
                end_path: positioning.end_path,
              )

              if comment_only_on_changed_files?
                @command.add_paths_to_diff_batch(
                  base_commit_oid:, head_commit_oid:,
                  paths: [positioning.start_path, positioning.end_path]
                )
              end
            when Positions::Errored, Positions::Indeterminate
              # Skip preparation for invalid positioning data.
            else T.absurd(positioning)
            end

            # Delegate preparation to repositioning processor for diff/blob loading.
            @delegate.prepare
          end

          sig { returns(Values) }
          def call
            # Early return as this is never valid for positioning.
            case positioning = @input.positioning
            when Positions::Errored, Positions::Indeterminate
              return CommentPosition::Errors::Parameter.new(positioning: positioning.type)
            end

            validations = begin
              case positioning
              when Positions::File, Positions::Line
                [
                  resolve_valid_blob_path_and_line_numbers(
                    commit_oid: positioning.commit_oid,
                    path: positioning.path,
                    line: positioning.is_a?(Positions::Line) ? positioning.line : nil
                  ),

                  resolve_valid_path_in_diff(
                    path: positioning.path,
                    commit_oid: positioning.commit_oid,
                  )
                ]
              when Positions::Multiline
                [
                  resolve_valid_blob_path_and_line_numbers(
                    commit_oid: positioning.start_commit_oid,
                    path: positioning.start_path,
                    line: positioning.start_line
                  ),

                  resolve_valid_blob_path_and_line_numbers(
                    commit_oid: positioning.end_commit_oid,
                    path: positioning.end_path,
                    line: positioning.end_line
                  ),

                  @command.resolve_same_blob(
                    base_commit_oid:, head_commit_oid:,
                    start_commit_oid: positioning.start_commit_oid,
                    start_path: positioning.start_path,
                    end_commit_oid: positioning.end_commit_oid,
                    end_path: positioning.end_path,
                  ),

                  resolve_valid_path_in_diff(
                    path: positioning.end_path,
                    commit_oid: positioning.end_commit_oid
                  )
                ]
              else T.absurd(positioning)
              end
            end

            # If we've got an error returned, return that value through as to halt the positioning.
            if error = Array.wrap(validations).find { _1.is_a?(Errors) }
              return error
            end

            # The behavior between new Positioning versus Repositioning is nearly identical, so delegate in to that code path
            # for the rest of processing a Position.
            result = @delegate.call

            diff_columns = result.diff_columns
            blob_columns = result.blob_columns
            immutable_columns = result.immutable_columns

            # In the scenario of any of these columns being blank, this is invalid for creation. Return a generic error.
            if diff_columns.nil? || blob_columns.nil? || immutable_columns.nil?
              GitHub.logger.error({
                "gh.pull_requests.feature": "comment_position.positioning",
                "gh.pull_requests.comment_positions.input": @input.serialize,
                "gh.pull_requests.comment_positions.diff_columns": diff_columns&.serialize || "null",
                "gh.pull_requests.comment_positions.blob_columns": blob_columns&.serialize || "null",
                "gh.pull_requests.comment_positions.immutable_columns": immutable_columns&.serialize || "null",
              })

              return Errors::Unknown.new
            end

            # Override original_positioning for creation context - this is new comment creation
            # so the current positioning becomes the original positioning.
            Result.new(
              original_positioning: positioning,
              positioning:, diff_columns:, blob_columns:, immutable_columns:,
            )
          end

          private

          sig { returns(String) }
          def base_commit_oid = @input.positioning.base_commit_oid

          sig { returns(String) }
          def head_commit_oid = @input.positioning.head_commit_oid

          sig { params(path: String, commit_oid: String).returns(T.nilable(Command::DiffContainsPathResult)) }
          def resolve_valid_path_in_diff(path:, commit_oid:)
            return unless comment_only_on_changed_files?
            @command.diff_contains_path?(base_commit_oid:, head_commit_oid:, path:, commit_oid:)
          end

          sig { params(commit_oid: String, path: String, line: T.nilable(Integer)).returns(Command::ResolveBlobAndLinesResult) }
          def resolve_valid_blob_path_and_line_numbers(commit_oid:, path:, line: nil)
            @command.resolve_blob_and_lines(commit_oid:, path:, line:)
          end

          sig { returns(T::Boolean) }
          def comment_only_on_changed_files? = @only_changed_files
        end
      end
    end
  end
end
