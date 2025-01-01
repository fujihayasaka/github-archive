# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      class Service
        include GitHub::Memoizer

        Collection = T.type_alias { T::Hash[Positions, Results] }
        Result = T.type_alias { T.any(GH::Result::Ok[Collection], GH::Result::Error[String]) }

        sig do
          params(
            repository: Repository,
            positions: T::Array[Positions],
            base_commit_oid: String,
            head_commit_oid: String
          ).void
        end
        def initialize(repository:, positions:, base_commit_oid:, head_commit_oid:)
          @repository = repository
          @positions = positions
          @base_commit_oid = base_commit_oid
          @head_commit_oid = head_commit_oid
        end

        sig { returns(Result) }
        def call
          results = T.let({}, Collection)
          requests = T.let([], T::Array[T.any(Requests::File, Requests::Line, Requests::Multiline)])

          # Determine the Request type for the given Position type. These classes are responsible for breaking down
          # the various positional pieces in to distinct Blob objects.
          @positions.each do |position|
            case position
            when Positions::File
              requests << Requests::File.new(position:, base_commit_oid:, head_commit_oid:)
            when Positions::Line
              requests << Requests::Line.new(position:, base_commit_oid:, head_commit_oid:)
            when Positions::Multiline
              requests << Requests::Multiline.new(position:, base_commit_oid:, head_commit_oid:)
            when Positions::Indeterminate, Positions::Errored
              # These positions can never be repositioned.
              results[position] = Results::Ineligible.new(position:, base_commit_oid:, head_commit_oid:)
            else T.absurd(position)
            end
          end

          requests.each do |request|
            if request.up_to_date?
              # Mark the request as already up to date.
              results[request.position] = request.to_result(request.blobs)
            else
              # Add each blob to the batch to be repositioned.
              request.blobs.each { request(_1) if _1.out_of_date? }
            end
          end

          begin
            diff_positions.execute
          rescue => exception # rubocop:todo Lint/RescueException
            Failbot.report(exception)
            return GH::Result::Error.new(exception.message)
          end

          requests.each do |request|
            # Skip updating already up to date requests.
            next if results.key?(request.position)

            # Load the new blob state or reuse the old one.
            blobs = request.blobs.map { _1.out_of_date? ? fetch(_1) : _1 }

            # Generate the final result for the given request.
            results[request.position] = request.to_result(blobs)
          end

          GH::Result::Ok[Collection].new(results)
        end

        private

        # Service object that deals with batch reading the GetDiffPositions Spokes RPC.
        sig { returns(GitSystems::BatchReadDiffPositions) }
        memoize def diff_positions = GitSystems::BatchReadDiffPositions.new

        # Add the blob to the batch repositioning request.
        sig { params(blob: Blob).void }
        def request(blob)
          diff_positions.request(
            repository: @repository,
            target_commit_oid: blob.target_commit_oid,
            source_commit_oid: blob.commit_oid,
            line: blob.line,
            path: T.must(blob.path),
          )
        end

        # The Spokes API will return a -1 when the targeted line cannot be repositioned.
        REMOVED_LINE = -1

        # Read and determine the new Blob object from the batched request.
        sig { params(blob: Blob).returns(Blob) }
        def fetch(blob)
          commit_oid = blob.target_commit_oid

          # Read the RPC response from Spokes.
          spokes_state, path, line = diff_positions.read(
            repository: @repository,
            target_commit_oid: commit_oid,
            source_commit_oid: blob.commit_oid,
            path: T.must(blob.path),
            line: blob.line,
          )

          # Convert the various Spokes state outcomes to the Blob representation of state.
          state = case spokes_state
          when SpokesAPI::Types::DiffPositionState::Success
            if line == REMOVED_LINE
              Blob::State::RemovedLine # Call was successful, but the line no longer exists in the target tree.
            else
              Blob::State::Repositioned
            end
          when SpokesAPI::Types::DiffPositionState::InvalidPath # The requested source path cannot be resolved from the source tree.
            Blob::State::InvalidPath
          when SpokesAPI::Types::DiffPositionState::RemovedPath # The requested target path was deleted in the target tree.
            Blob::State::RemovedPath
          when SpokesAPI::Types::DiffPositionState::ContentTooLarge # API limits on blob sizes prevent repositioning.
            Blob::State::ContentTooLarge
          when SpokesAPI::Types::DiffPositionState::Unknown # Something bad happened and we could not properly parse the outcome.
            Blob::State::Unknown
          else
            Blob::State::NotRequested # The RPC call for repositioning never fired.
          end

          blob.with(state:, commit_oid:, path:, line:)
        end

        sig { returns(String) }
        attr_reader :base_commit_oid

        sig { returns(String) }
        attr_reader :head_commit_oid
      end
    end
  end
end
