# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      # This class executes end-to-end repositioning for positional inputs from various sources
      # (APIs, UIs, existing database values), converting between data types and returning
      # positional values for persistence or API rendering.
      #
      # Processing Flow:
      #   1. Collect inputs and determine appropriate Processor classes
      #   2. Perform batch loading of git data relevant to each input type
      #   3. Execute Processors, generating Position data structures and PullRequestReviewThread columns
      #   4. Reposition Position data structures using the Repositioner when needed
      #   5. For repositioned inputs, create new Processor instances with updated positioning
      #   6. Perform additional batch loading of git data as necessary
      #   7. Execute final Processors to generate up-to-date PullRequestReviewThread columns
      #
      # Performance Optimizations:
      #   - position_only: When true, skips legacy column generation in the final positioning pass,
      #     reducing GitRPC calls when only positional data is needed
      #   - diffs: Pre-loaded diff data can be provided to avoid redundant GitRPC calls for diff
      #     retrieval, enabling efficient reuse of already-fetched git data
      #   - Batch loading: Groups git operations to minimize GitRPC round trips
      #
      class Service
        include GitHub::Memoizer

        sig do
          params(
            repository: Repository,
            inputs: T::Array[Inputs::Types],
            base_commit_oid: String,
            head_commit_oid: String,
            diffs: T::Array[GitHub::Diff],
            position_only: T::Boolean,
          ).void
        end
        def initialize(repository:, inputs:, base_commit_oid:, head_commit_oid:, diffs: [], position_only: false)
          @repository = repository
          @inputs = inputs
          @base_commit_oid = base_commit_oid
          @head_commit_oid = head_commit_oid
          @position_only = position_only
          @diffs = diffs
        end

        sig { returns(T::Hash[Inputs::Types, Values]) }
        def call
          results = T.let({}, T::Hash[Inputs::Types, Values])
          processors = T.let([], T::Array[Processors::Types])

          # Create and prepare processors for initial input processing.
          @inputs.each do |input|
            processor = case input
            when Inputs::DiffRelative  then Processors::DiffRelative.new(input:, command:)
            when Inputs::Blobs         then Processors::Blobs.new(input:, command:)
            when Inputs::ThreadColumns then Processors::ThreadColumns.new(input:, command:)
            when Inputs::Positioning   then Processors::Positioning.new(input:, command:)
            else T.absurd(input)
            end

            processors << processor.tap(&:prepare)
          end

          # Load all queued git data in batch.
          command.batch_load_data!

          # Process inputs and identify candidates for repositioning.
          processors.each do |processor|
            input = processor.input
            result = results[input] = processor.call

            # Skip repositioning for invalid results.
            next if result.is_a?(CommentPosition::Errors)

            # Skip repositioning if already targeting the correct commit range.
            next if result.base_commit_oid == base_commit_oid && result.head_commit_oid == head_commit_oid

            command.add_to_repositioning_batch(input:, positioning: result.positioning)
          end

          if command.nothing_to_reposition?
            # No repositioning needed - return initial results.
            return results
          else
            # Clear processors for repositioning phase.
            processors.clear
          end

          # Create repositioning processors for each position that needs updating.
          command.each_repositioned_position do |input, positioning|
            case previous_result = results[input]
            when Result
              if @position_only
                # Optimization: Skip column generation when only positioning data is needed.
                results[input] = Result.new(
                  positioning:,
                  previous_positioning: previous_result.positioning,
                  original_positioning: previous_result.original_positioning
                )
              else
                # Create repositioning processor to generate updated column data.
                processors << Processors::Repositioning.new(
                  command:, previous_result:,
                  input: Inputs::Positioning.new(
                    positioning:,
                    identifier: input.identifier
                  ),
                ).tap(&:prepare)
              end
            end
          end

          # Complete repositioning if there are processors to run.
          if processors.empty?
            return results
          else
            command.batch_load_data!
          end

          # Execute repositioning processors and update results.
          processors.each do |processor|
            if previous_input = results.each_key.find { _1.identifier == processor.input.identifier }
              results[previous_input] = processor.call
            end
          end

          results
        end

        private

        # Target commit range for positioning operations.
        sig { returns(String) }
        attr_reader :base_commit_oid, :head_commit_oid

        # Coordinates git operations and batch loading across processors.
        sig { returns(Command) }
        memoize def command
          Command.new(repository: @repository, diffs: @diffs, base_commit_oid:, head_commit_oid:)
        end
      end
    end
  end
end
