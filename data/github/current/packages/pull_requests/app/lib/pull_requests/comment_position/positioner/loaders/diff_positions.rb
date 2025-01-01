# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Loaders
        # Efficiently manages diff position loading by wrapping GitSystems::BatchReadDiffPositions
        # to provide a consistent interface with other loaders in the comment positioning system.
        #
        # The DiffPositions loader handles:
        # - Batching requests for diff position resolution to minimize expensive service calls
        # - Providing a simplified interface for adding items to the batch
        # - Executing the batch when all items have been added
        # - Fetching results after the batch has been executed
        class DiffPositions
          sig { params(repository: Repository).void }
          def initialize(repository:)
            @repository = repository
            @batch = T.let(GitSystems::BatchReadDiffPositions.new, GitSystems::BatchReadDiffPositions)
          end

          # Add an item to the batch for later processing.
          sig do
            params(
              target_commit_oid: String,
              source_commit_oid: String,
              source_path: String
            ).void
          end
          def add_to_batch(target_commit_oid:, source_commit_oid:, source_path:)
            @batch.request(
              repository: @repository,
              path: source_path,
              line: nil,
              target_commit_oid:,
              source_commit_oid:,
            )
          end

          sig { void }
          def load_batch!
            @batch.execute
          end

          # Fetch the result for a specific item after the batch has been executed.
          sig do
            params(
              target_commit_oid: String,
              source_commit_oid: String,
              source_path: String,
            ).returns(T.nilable(String))
          end
          def fetch(target_commit_oid:, source_commit_oid:, source_path:)
            state, path, line = @batch.read(
              repository: @repository,
              path: source_path,
              line: nil,
              target_commit_oid:,
              source_commit_oid:,
            )

            path
          end

          # Feature flag rollout to prevent this from causing potential regressions in scenarios where git can't resolve
          # paths appropriately.
          sig { returns(T::Boolean) }
          def enabled?
            FeatureFlag.vexi.enabled?(:cotd_validate_multiline_paths, @repository, @repository.owner, default: false)
          end
        end
      end
    end
  end
end
