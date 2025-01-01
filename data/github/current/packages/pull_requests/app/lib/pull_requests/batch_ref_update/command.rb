# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    # This class contains a collection of methods that are designed to "do only one thing, and do it very well." It acts
    # like an "adapter pattern" for the rest of the dependencies. It deals with the intracies of various persistence layers
    # and converts those in to Result objects describing the outcome.
    class Command
      include ICommand

      sig { params(repository: Repository).void }
      def initialize(repository:)
        @repository = repository
      end

      sig { override.params(requests: T::Array[Request]).returns(GenericResult) }
      def mark_requests_as_processing!(requests:)
        # TODO: Implement me.
        ICommand::Result::Success.new
      end

      sig { override.params(requests: T::Array[Request]).returns(GenericResult) }
      def delete_processing_requests!(requests:)
        # TODO: Implement me.
        ICommand::Result::Success.new
      end

      sig { override.params(requests: T::Array[Request::Eligible]).returns(ICommand::Result::UpdateRefs) }
      def update_refs!(requests:)
        # TODO: Bot actor for these ref updates.
        batch = GitSystems::BatchWriteRefs::Service.new(repository: @repository, actor: User.ghost)

        # Append all the eligible requests to the batch.
        requests.each do |request|
          batch.add(ref_name: request.ref_name, before_oid: request.before_sha, after_oid: request.after_sha)
        end

        result = batch.call

        # Map the results back to the requests.
        requests_and_outcomes = requests.map do |request|
          outcome = result.requests.find { _1.ref_name == request.ref_name }&.outcome
          [request, outcome || GitSystems::BatchWriteRefs::Outcome::Pending.new]
        end.to_h

        ICommand::Result::UpdateRefs.new(
          exception: result.exception,
          requests: requests_and_outcomes
        )
      end

      sig { override.params(request: Request, reason: Enums::Failures).returns(GenericResult) }
      def dispatch_request_failure!(request:, reason:)
        # TODO: Implement me.
        ICommand::Result::Success.new
      end
    end
  end
end
