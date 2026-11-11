# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    # Clear out the Merge Queue.
    #
    # Called by MergeQueueClearQueueJob
    class Clear < Base
      sig { params(actor: User, clear_locked_entries: T::Boolean).void }
      def call(actor, clear_locked_entries: false)
        stats_start_time = GitHub::Dogstats.monotonic_time
        GitHub.logger.with_named_tags(
          "code.function": "clear!",
          "code.namespace": "MergeQueues::Service",
          "gh.repo.id": @repository.id,
          "gh.merge_queue.branch": @branch,
          "gh.actor.id": actor.id
        ) do
          if @merge_queue.nil?
            raise ActiveRecord::RecordNotFound
          end

          command = command_without_status_check_models

          begin
            merge_queue_entries =
              if !clear_locked_entries
                factory.merge_queue_entry_models.reject { |entry| entry.locked? }
              else
                factory.merge_queue_entry_models
              end
            reason = MergeQueues::Entry::RemovalReason::QueueCleared

            remove_result = ICommand::Result.with_retry do
              command.remove!(
                merge_queue_entries,
                actor:,
                reason:,
              )
            end

            case remove_result
            when ICommand::Result::Error
              raise remove_result.as_exception
            when ICommand::Result::Success
              notify_websockets!(merge_queue_entries)
              request_execution!
              @merge_queue.instrument_clear(actor)

              merge_queue_entries.each do |entry|
                next unless pull_request = entry.pull_request

                command.dispatch_webhook!(MergeQueues::WebHook::Dequeued.for_model(entry:, reason:, actor:))
              end
            else
              T.absurd(remove_result)
            end
          rescue => exception # rubocop:todo Lint/RescueException
            # Exception is captured so that it will be present in the ensure block
            raise
          ensure
            result = exception.nil? ? "success" : "error"
            GitHub.dogstats.distribution_timing_since(
              "merge_queue.clear.time",
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
end
