# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # This class is the core "business logic" of batch merge commit creation. It contains no external dependencies,
    # and delegates to the relevant objects for Side Effects.
    class Processor
      extend T::Sig

      sig do
        params(
          command: ICommand,
          configuration: Configuration,
          requests: T::Array[Request],
          invalid_requests: T::Array[Request::Invalid]
        ).void
      end
      def initialize(command:, configuration:, requests:, invalid_requests:)
        @command = command
        @configuration = configuration
        @valid_requests = requests
        @invalid_requests = invalid_requests
      end

      sig { void }
      def call
        # Lock the database records so that additional requests can be appended to the end.
        transition_batch_to_processing!

        # If we have a valid merge commit, but we're missing the `mergeable: true` value, just update those already valid
        # records and skip generating unnecessary merge commits.
        transition_up_to_date_and_indeterminate_requests_to_mergeable!

        @valid_requests.each do |request|
          generate_merge_commit!(request)
          generate_rebase_commit!(request)
        end

        perform_ref_update!

        @valid_requests.each do |request|
          update_pull_request!(request:)
          dispatch_mergeability_event!(request:)
        end

        delete_processing_requests!

        # iterate over any Request that hasn't yet been marked as processed and mark them as processed
        # before their timing stats are logged. All Request::Invalid entries should already have been
        # marked as processed when they were initialized
        @valid_requests.each do |request|
          mark_request_end_processing_time(request)
        end
      end

      protected

      sig { void }
      def transition_batch_to_processing!
        return if pull_request_ids.blank?

        case result = @command.transition_to_processing!(pull_request_ids:)
        when ICommand::Result::Error
          # We've failed to write to the database for some reason and we can't recover.
          raise result.as_exception
        end
      end

      sig { void }
      def transition_up_to_date_and_indeterminate_requests_to_mergeable!
        @invalid_requests.filter { _1.reason == Request::Invalid::Reason::IndeterminateAndUpToDate }.each do |request|
          case result = @command.transition_invalid_request_to_mergeable!(pull_request_id: request.pull_request_id)
          when ICommand::Result::Error
            Failbot.report(result.as_exception)
          end
        end
      end

      sig { params(request: Request).void }
      def generate_merge_commit!(request)
        result = with_retry do
          @command.create_merge_commit!(
            pull_request_id: request.pull_request_id,
            base_sha: request.base_ref_sha,
            head_sha: request.head_ref_sha,
          )
        end

        request.merge_commit = result

        case result
        when ICommand::Result::Error
          # An unknown error occurred, report this to exception tracking.
          mark_request_end_processing_time(request)
          Failbot.report(result.as_exception)
        end
      end

      sig { params(request: Request).void }
      def generate_rebase_commit!(request)
        if @configuration.skip_rebase
          request.rebase_commit = Request::Commits::Skipped.new
          return
        end

        # We have to have a merge commit to create a rebase commit.
        case merge_commit = request.merge_commit
        when Request::Commits::Pending,
             Request::Commits::Skipped,
             GitSystems::Commit::Conflict,
             GitSystems::Commit::Failed,
             GitSystems::Errors,
             ICommand::Result::Error,
             ICommand::Result::Timeout
          request.rebase_commit = Request::Commits::Skipped.new
          return
        end

        case result = with_retry do
          @command.create_rebase_commit!(
            pull_request_id: request.pull_request_id,
            base_sha: request.base_ref_sha,
            merge_commit_sha: merge_commit.sha,
            timeout: @configuration.rebase_timeout
          )
        end
        when ICommand::Result::Timeout

        when ICommand::Result::Error
          # An unknown error occurred, report this to exception tracking.
          mark_request_end_processing_time(request)
          Failbot.report(result.as_exception)
        end

        request.rebase_commit = result
      end

      sig { void }
      def perform_ref_update!
        updates = T.let([], T::Array[ICommand::RefUpdate])
        requests = T.let(Set.new, T::Set[Request])

        @valid_requests.each do |request|
          pull_request_id = request.pull_request_id

          # TODO: handle more merge and rebase commit types
          case merge_commit = request.merge_commit
          when PullRequests::GitSystems::Commit::Created
            updates << ICommand::RefUpdate.new(
              name: request.merge_ref_name,
              sha: merge_commit.sha,
              pull_request_id:
            )

            requests << request
          else
            next
          end

          case rebase_commit = request.rebase_commit
          when PullRequests::GitSystems::Commit::Created
            updates << ICommand::RefUpdate.new(
              name: request.rebase_ref_name,
              sha: rebase_commit.sha,
              pull_request_id:
            )

            requests << request
          else
            updates << ICommand::RefUpdate.new(
              name: request.rebase_ref_name,
              sha: GitHub::NULL_OID,
              pull_request_id:
            )

            requests << request
          end
        end

        return if updates.empty?

        case result = with_retry { @command.update_refs!(updates:) }
        when ICommand::Result::Error
          requests.map { |request| request.processed_at = Time.now }
          raise result.as_exception
        end

        requests.map { |request| request.update_ref_result = result }
      end

      sig { params(request: Request).void }
      def update_pull_request!(request:)
        # TODO: This should take in to account rebase commit specific errors.
        result = case commit = request.merge_commit
        when GitSystems::Commit::Created
          request.current_mergeability = Request::Mergeability::Mergeable

          with_retry do
            @command.mark_pull_request_as_mergeable!(
              pull_request_id: request.pull_request_id,
              merge_commit_sha: commit.sha
            )
          end
        when GitSystems::Commit::Conflict
          request.current_mergeability = Request::Mergeability::Conflict
          with_retry { @command.mark_pull_request_as_unmergeable!(pull_request_id: request.pull_request_id) }
        else
          request.current_mergeability = Request::Mergeability::Indeterminate
          nil
        end

        return if result.is_a?(ICommand::Result::Success)

        # We've failed to update the Pull Request model, treat it as "cleared."
        if result.is_a?(ICommand::Result::Error)
          Failbot.report(result.as_exception)
        end

        case result = with_retry { @command.clear_mergeability!(pull_request_id: request.pull_request_id) }
        when ICommand::Result::Error
          Failbot.report(result.as_exception)
        end

        mark_request_end_processing_time(request)
      end

      sig { params(request: Request).void }
      def dispatch_mergeability_event!(request:)
        mergeability = request.current_mergeability

        # Don't dispatch if we've failed to properly generate a new merge commit.
        return if mergeability == Request::Mergeability::Indeterminate

        # Don't dispatch notifications if we've already done it previously.
        return if mergeability == request.previous_mergeability

        @command.dispatch_mergeability_event!(pull_request_id: request.pull_request_id)
      end

      sig { void }
      def delete_processing_requests!
        return if pull_request_ids.blank?

        case result = @command.delete_processing_requests!(pull_request_ids:)
        when ICommand::Result::Success
        when ICommand::Result::Error
          Failbot.report(result.as_exception)
        end
      end

      private

      sig { returns(T::Array[Integer]) }
      def pull_request_ids
        @valid_requests.map(&:pull_request_id).concat(@invalid_requests.map(&:pull_request_id))
      end

      sig { params(request: T.any(Request, Request::Invalid)).void  }
      def mark_request_end_processing_time(request)
        unless request.processed_at
          request.processed_at = Time.now
        end
      end

      # Call the block up until max_attempts number of times. Retrying only occurs when the Error object returned
      # permits retrying.
      sig do
        type_parameters(:T).params(
          max_attempts: Integer,
          block: T.proc.returns(T.type_parameter(:T))
        ).returns(T.type_parameter(:T))
      end
      def with_retry(max_attempts = 3, &block)
        ICommand::Result.with_retry(max_attempts, &block)
      end
    end
  end
end
