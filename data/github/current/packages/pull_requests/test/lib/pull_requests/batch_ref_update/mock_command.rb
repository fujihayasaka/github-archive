# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module BatchRefUpdate
    # Enables mocking out side effects requested by the processor. Mock results can be given to the initializer
    # as an array of results, allowing sequential calls with different outcomes.
    class MockCommand
      include ICommand

      module Assertions
        include Logging::Commands::Factories
        extend T::Helpers

        requires_ancestor { GitHub::TestCase }

        sig { params(command: Logging::Commands, actions: T::Array[T.any(T::Array[Logging::Commands::Action], Logging::Commands::Action)]).void }
        def assert_actions_performed(command, actions)
          assert_equal actions.flatten, command.actions
        end
      end

      sig do
        params(
          mark_as_processing: T::Array[ICommand::GenericResult],
          update_refs: T::Array[ICommand::Result::UpdateRefs],
          delete_processing_requests: T::Array[ICommand::GenericResult]
        ).void
      end
      def initialize(mark_as_processing: [], update_refs: [], delete_processing_requests: [])
        @mark_as_processing = mark_as_processing
        @update_refs = update_refs
        @delete_processing_requests = delete_processing_requests
      end

      sig { returns(Logging::Commands) }
      def as_logger
        Logging::Commands.new(self)
      end

      sig { override.params(requests: T::Array[Request]).returns(ICommand::GenericResult) }
      def delete_processing_requests!(requests:)
        @delete_processing_requests.pop || ICommand::Result::Success.new
      end

      sig { override.params(request: Request, reason: Enums::Failures).returns(ICommand::GenericResult) }
      def dispatch_request_failure!(request:, reason:)
        ICommand::Result::Success.new
      end

      sig { override.params(requests: T::Array[Request]).returns(ICommand::GenericResult) }
      def mark_requests_as_processing!(requests:)
        @mark_as_processing.pop || ICommand::Result::Success.new
      end

      sig do
        override.params(
          requests: T::Array[Request::Eligible]
        ).returns(ICommand::Result::UpdateRefs)
      end
      def update_refs!(requests:)
        @update_refs.pop || ICommand::Result::UpdateRefs.new(
          requests: requests.map { [_1, GitSystems::BatchWriteRefs::Outcome::Success.new] }.to_h
        )
      end
    end
  end
end
