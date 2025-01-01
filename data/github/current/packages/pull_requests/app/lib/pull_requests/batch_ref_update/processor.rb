# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    class Processor

      sig { params(command: ICommand, requests: T::Array[Request]).void }
      def initialize(command:, requests:)
        @command = command
        @requests = requests
      end

      sig { returns(Result) }
      def call
        if @requests.empty?
          return Result.new(outcome: Result::Outcome::NoRequests)
        end

        begin
          mark_requests_as_processing
        rescue ICommand::CommandFailed => exception
          return Result.error(exception:)
        end

        # Dispatch failure requests for all ineligible requests.
        ineligible_requests.each do |request|
          dispatch_failure_job(request:, reason: request.reason)
        end

        # Attempt to perform the ref update, if there are any to perform.
        if result = update_refs(requests: eligible_requests)
          # If the request had a low level exception, track that.
          if exception = result.exception
            Failbot.report(exception)
          end

          result.requests.each do |request, outcome|
            case outcome
            when GitSystems::BatchWriteRefs::Outcome::Success
              # TODO: anything to do to mark as successful? logging?
            when GitSystems::BatchWriteRefs::Outcome::Failed
              case reason = outcome.reason
              when PullRequests::GitSystems::BatchWriteRefs::FailureReason::BranchRule
                # Will never work due to branch rules. Discard this request.
              when PullRequests::GitSystems::BatchWriteRefs::FailureReason::RefUpdateFailed
                # TODO: This signals an individual failure. It should be more granular, but for now until we flush out the
                # batch interface it's fine.
                dispatch_failure_job(request:, reason: Enums::Failures::GitFailure)
              else T.absurd(reason)
              end
            when GitSystems::BatchWriteRefs::Outcome::Error
              dispatch_failure_job(request:, reason: Enums::Failures::GitError)
            when GitSystems::BatchWriteRefs::Outcome::Pending
              # mark as pending? maybe combine with failed
              dispatch_failure_job(request:, reason: Enums::Failures::PendingRefUpdate)
            else
              T.absurd(outcome)
            end
          end
        end

        delete_processing_requests

        Result.new(outcome: Result::Outcome::Success)
      end

      protected

      sig { void }
      def mark_requests_as_processing
        result = ICommand::Result.with_retry do
          @command.mark_requests_as_processing!(requests: @requests)
        end

        case result
        when ICommand::Result::Error
          raise result.as_exception
        end
      end

      sig do
        params(
          requests: T::Array[Request::Eligible]
        ).returns(T.nilable(ICommand::Result::UpdateRefs))
      end
      def update_refs(requests:)
        return if requests.empty?

        # The internals of update_refs! handles automatic retrying.
        @command.update_refs!(requests:)
      end

      sig { void }
      def delete_processing_requests
        result = ICommand::Result.with_retry do
          @command.delete_processing_requests!(requests: @requests)
        end

        case result
        when ICommand::Result::Error
          Failbot.report(result.exception) if result.exception
        end
      end

      sig { params(request: Request, reason: Enums::Failures).void }
      def dispatch_failure_job(request:, reason:)
        ICommand::Result.with_retry do
          @command.dispatch_request_failure!(request:, reason:)
        end
      end

      private

      sig { returns(T::Array[Request::Eligible]) }
      def eligible_requests
        @requests.filter_map { |request| request if request.is_a?(Request::Eligible) }
      end

      sig { returns(T::Array[Request::Ineligible]) }
      def ineligible_requests
        @requests.filter_map { |request| request if request.is_a?(Request::Ineligible) }
      end
    end
  end
end
