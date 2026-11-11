# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      # Main entry point for the Positioning subsystem.
      #
      # == Purpose
      #
      # Service is the public interface for resolving comment positions. It:
      # 1. Creates a Command (encapsulates all I/O operations)
      # 2. Creates a Processor (executes the positioning pipeline)
      # 3. Returns results mapped back to inputs
      #
      # == Architecture
      #
      # The separation between Service, Command, and Processor enables:
      #
      # - **Testability**: Command can be mocked to avoid git I/O in tests
      # - **Batching**: Command batches all I/O for efficiency
      # - **Policy separation**: Processor handles business logic, Command handles I/O
      #
      # == Parameters
      #
      # - **repository**: The Repository to resolve positions in
      # - **inputs**: Array of Positioner::Inputs::Types to process
      # - **target_base_commit_oid/target_head_commit_oid**: The commit range to resolve to
      # - **diffs**: Pre-loaded diffs (optional, avoids redundant loading)
      # - **only_changed_files**: If true, reject positions outside the diff
      #
      # Called by CommentPosition::Positioner when cotd_engine_v2 is enabled.
      class Service
        sig do
          params(
            repository: Repository,
            inputs: T::Array[Positioner::Inputs::Types],
            target_base_commit_oid: String,
            target_head_commit_oid: String,
            diffs: T::Array[GitHub::Diff],
            only_changed_files: T::Boolean,
          ).void
        end
        def initialize(repository:, inputs:, target_base_commit_oid:, target_head_commit_oid:, diffs: [], only_changed_files: false)
          @repository = repository
          @inputs = inputs
          @target_base_commit_oid = target_base_commit_oid
          @target_head_commit_oid = target_head_commit_oid
          @diffs = diffs
          @only_changed_files = only_changed_files
        end

        # Executes the positioning pipeline and returns results.
        #
        # Returns a hash mapping each input to its result. Results are either:
        # - Types::Result (Line, Multiline, File, Invalid) for successful processing
        # - CommentPosition::Errors for unprocessable inputs
        #
        # The order of results matches the order of inputs.
        sig { returns(T::Hash[Positioner::Inputs::Types, T.any(Types::Result, CommentPosition::Errors)]) }
        def call
          # Command encapsulates all I/O operations (git, diffs, blobs).
          # It batches requests for efficiency and provides a clean interface
          # for the Processor.
          command = Command.new(
            repository: @repository,
            target_range: [@target_base_commit_oid, @target_head_commit_oid],
            diffs: @diffs,
          )

          # Processor executes the positioning pipeline:
          # 1. Build requests from inputs
          # 2. Queue I/O through Command
          # 3. Resolve locations
          # 4. Build results
          processor = Processor.new(
            inputs: @inputs,
            command:,
            only_changed_files: @only_changed_files,
          )

          results = processor.call

          # Map results back to inputs by index to return the expected hash format
          @inputs.each_with_index.each_with_object({}) do |(input, index), hash|
            hash[input] = results[index]
          end
        end
      end
    end
  end
end
