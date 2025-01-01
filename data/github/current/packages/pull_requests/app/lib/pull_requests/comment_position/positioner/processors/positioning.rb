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

          sig { params(input: Inputs::Positioning, command: Command).void }
          def initialize(input:, command:)
            @input = input
            @command = command
            @delegate = T.let(Repositioning.new(input:, command:), Repositioning)
          end

          sig { void }
          def prepare
            # Queue blob existence validation for all positioning types.
            case positioning = @input.positioning
            when Positions::File
              @command.add_path_to_blob_and_lines(
                commit_oid: positioning.commit_oid,
                path: positioning.path,
                line: nil
              )
            when Positions::Line
              @command.add_path_to_blob_and_lines(
                commit_oid: positioning.commit_oid,
                path: positioning.path,
                line: positioning.line
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

              if positioning.start_path != positioning.end_path
                @command.add_to_diff_positions_batch(
                  base_commit_oid: positioning.base_commit_oid,
                  head_commit_oid: positioning.head_commit_oid,
                  start_commit_oid: positioning.start_commit_oid,
                  start_path: positioning.start_path,
                  end_commit_oid: positioning.end_commit_oid,
                  end_path: positioning.end_path,
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
            # Invoke the validations and determine if any of the positional types are invalid for creation.
            validations = begin
              case positioning = @input.positioning
              when Positions::File
                @command.resolve_blob_and_lines(
                  commit_oid: positioning.commit_oid,
                  path: positioning.path,
                  line: nil,
                )
              when Positions::Line
                @command.resolve_blob_and_lines(
                  commit_oid: positioning.commit_oid,
                  path: positioning.path,
                  line: positioning.line
                )
              when Positions::Multiline
                [
                  @command.resolve_blob_and_lines(
                    commit_oid: positioning.start_commit_oid,
                    path: positioning.start_path,
                    line: positioning.start_line
                  ),
                  @command.resolve_blob_and_lines(
                    commit_oid: positioning.end_commit_oid,
                    path: positioning.end_path,
                    line: positioning.end_line
                  ),
                  @command.resolve_same_blob(
                    base_commit_oid: positioning.base_commit_oid,
                    head_commit_oid: positioning.head_commit_oid,
                    start_commit_oid: positioning.start_commit_oid,
                    start_path: positioning.start_path,
                    end_commit_oid: positioning.end_commit_oid,
                    end_path: positioning.end_path,
                  )
                ]
              when Positions::Indeterminate, Positions::Errored
                CommentPosition::Errors::Parameter.new(positioning: positioning.type)
              end
            end

            # If we've got an error returned, return that value through as to halt the positioning.
            if error = Array.wrap(validations).find { _1.is_a?(Errors) }
              return error
            end

            # Delegate processing to Repositioning processor.
            result = @delegate.call

            # Override original_positioning for creation context - this is new comment creation
            # so the current positioning becomes the original positioning.
            Result.new(
              positioning:,
              original_positioning: positioning,
              diff_columns: result.diff_columns,
              blob_columns: result.blob_columns,
              immutable_columns: result.immutable_columns,
            )
          end
        end
      end
    end
  end
end
