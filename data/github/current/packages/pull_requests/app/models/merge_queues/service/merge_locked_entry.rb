# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Attempt to merge the already locked entry.
  #
  # This is for backwards compatability with the already existing GraphQL mutations. We will be
  # revisiting the public API and this is a "temporary" shim.
  #
  # Called by Platform::Mutations::MergeLockedMergeGroup
  class Service::MergeLockedEntry < Service::Base
    module Result
      extend T::Helpers

      interface!
      sealed!

      requires_ancestor { Object }

      class Success
        include Result
      end

      class NoLockedEntryError
        include Result
      end

      class FailedToAcquireMutex
        include Result
      end

      class MergeError < T::Struct
        include Result

        const :message, String
      end
    end

    sig { params(actor: User).returns(Result) }
    def call(actor:)
      stats_start_time = GitHub::Dogstats.monotonic_time
      GitHub.logger.with_named_tags(
        "code.namespace": "MergeQueues::Service::MergeLockedEntry",
        "code.function": "call",
        "gh.repo.id": @repository.id,
        "gh.merge_queue.id": @merge_queue&.id,
        "gh.actor.id": actor.id
      ) do
        if @merge_queue.nil?
          raise ActiveRecord::RecordNotFound
        end

        next_group = Group.find_next(configuration:, entries: factory.merge_queue_entry_models)
        unless next_group.locked?
          return Result::NoLockedEntryError.new
        end

        command = command_without_status_check_models

        begin
          merge_result = with_merge_mutex do
            Merger.new(command:).merge!(
              next_group,
              actor:,
              merge_method: configuration.merge_method,
              merge_action: :api_merge_queue_merge
            )
          end

          case merge_result
          when ICommand::Result::BranchProtectionError
            # We are currently depending on this for tracking Branch Rule Configurations blocking merge queue.
            # TODO: Should attempt to scrub branch name.
            Failbot.report(merge_result.exception)
            return Result::MergeError.new(message: merge_result.message)
          when ICommand::Result::Error
            request_execution!
            raise merge_result.as_exception
          end

          entry = next_group.head_entry!
          notify_websockets!([entry])
          request_execution!

          Result::Success.new
        rescue GitHub::Redis::Mutex::LockError => exception
          Result::FailedToAcquireMutex.new
        rescue => exception # rubocop:disable Lint/RescueException
          # Exception is captured so that it will be present in the ensure block
          raise
        ensure
          result = exception.nil? ? "success" : "error"
          GitHub.dogstats.distribution_timing_since(
            "merge_queue.merge_locked.time",
            stats_start_time,
            tags: ["single_job", result],
          )
          GitHub.logger.info(
            result,
            "gh.merge_queue.configuration": configuration_for_logs,
            "exception.message": exception,
          )
        end
      end
    end
  end
end
