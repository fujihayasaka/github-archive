# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Loaders
        # Batches repositioning requests and executes them through the Repositioner
        # service to minimize expensive repositioning calculations.
        #
        # The Repositioning loader handles:
        # - Collecting position update requests for later batch processing
        # - Managing the relationship between input objects and their positions
        # - Executing batched repositioning through the Repositioner service
        # - Handling service errors with appropriate fallback positions
        # - Providing iteration over repositioned results
        #
        # Ensures all requests receive a valid position result through either successful
        # repositioning or error handling with fallback positions.
        class Repositioning
          # Initialize the repositioning loader with repository and commit context.
          # Sets up internal collections for tracking requests and caching results.
          sig { params(repository: Repository, base_commit_oid: String, head_commit_oid: String).void }
          def initialize(repository:, base_commit_oid:, head_commit_oid:)
            @repository = repository
            @base_commit_oid = base_commit_oid
            @head_commit_oid = head_commit_oid
            @requests = T.let({}, T::Hash[Inputs::Types, Positions])
            @results = T.let({}, T::Hash[Positions, T.nilable(Positions)])
          end

          # Add a position repositioning request to the batch for later processing.
          sig { params(input: Inputs::Types, position: Positions).void }
          def add_to_batch(input, position) = @requests[input] = position

          # Iterate over all repositioning requests, yielding input and repositioned position pairs.
          # Triggers batch loading if not already performed and provides fallback positions
          # for any requests that could not be successfully repositioned.
          sig { params(block: T.proc.params(input: Inputs::Types, positioning: Positions).void).void }
          def each(&block)
            load_batch!

            @requests.each do |input, previous_position|
              positioning = @results[previous_position] ||
                Positions::Indeterminate.new(reason: :could_not_reposition, base_commit_oid:, head_commit_oid:)

              yield input, positioning
            end
          end

          # Check if all positioning requests have been processed.
          sig { returns(T::Boolean) }
          def loaded? = @requests.each_value.all? { @results[_1].present? }

          private

          sig { returns(String) }
          attr_reader :base_commit_oid, :head_commit_oid

          # Execute batched repositioning for all pending requests.
          # Calls the Repositioner service with collected positions and handles both
          # successful results and error conditions with appropriate fallback positions.
          sig { void }
          def load_batch!
            # Find positions that haven't been processed yet to avoid duplicate work
            positions = @requests.each_value.filter_map { _1 if @results[_1].nil? }

            # Don't bother calling the service if theres nothing to position.
            return if positions.blank?

            # Execute the repositioning service with all pending positions
            result = Repositioner::Service.new(
              repository: @repository,
              positions:,
              base_commit_oid: @base_commit_oid,
              head_commit_oid: @head_commit_oid,
            ).call

            case result
            when GH::Result::Ok
              # Store successful repositioning results, converting to position objects
              result.value.each { @results[_1] = _2.to_position }
            when GH::Result::Error
              # Handle service errors by providing error positions for all requests
              position = Positions::Errored.new(exception: result.exception, base_commit_oid:, head_commit_oid:)
              positions.each { @results[_1] = position }
            else T.absurd(result)
            end
          end
        end
      end
    end
  end
end
