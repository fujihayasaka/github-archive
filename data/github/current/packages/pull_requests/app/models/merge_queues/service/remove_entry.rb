# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    class RemoveEntry < Base
      extend T::Sig

      sig { params(entry: MergeQueueEntry, actor: User).void }
      def call(entry:, actor:)
        stats_start_time = GitHub::Dogstats.monotonic_time
        GitHub.logger.with_named_tags(
          "code.namespace": "MergeQueues::Service::RemoveEntry",
          "code.function": "call",
          "gh.repo.id": @repository.id,
          "gh.merge_queue.branch": @branch,
          "gh.merge_queue.entry.id": entry.id,
          "gh.actor.id": actor.id
        ) do
          if @merge_queue.nil?
            raise ActiveRecord::RecordNotFound
          end

          # We do not want to compute state here because we're dependent on the last run of the DecisionEngine.
          next_group = Group.find_next(configuration:, entries: factory.merge_queue_entry_models)

          if next_group.locked? && next_group.entries.include?(entry)
            raise Errors::GroupLocked.new("Can't remove MergeQueueEntry that has a locked descendent")
          end

          command = command_without_status_check_models

          destroyed_webhook_payload = begin
            WebHook::Destroyed.for(entry:, reason: WebHook::Destroyed::Reason::Dequeued)
          rescue WebHook::Destroyed::MissingDataError
            # This will be raised if the entry does not have an associated
            # merge commit, etc. In this context -- where the entry is being
            # removed manually -- this is not a problem, and we can just skip
            # sending the Web hook.
            nil
          end

          begin
            reason = MergeQueues::Entry::RemovalReason::Manual

            remove_result = ICommand::Result.with_retry do
              command.remove!([entry], actor:, reason:)
            end

            case remove_result
            when ICommand::Result::Error
              raise remove_result.as_exception
            when ICommand::Result::Success
              dispatch_webhook(command, destroyed_webhook_payload)
              dispatch_webhook(command, MergeQueues::WebHook::Dequeued.for_model(entry:, reason:, actor:))

              notify_websockets!([entry])
              request_execution!
            else
              T.absurd(remove_result)
            end
          rescue => exception # rubocop:todo Lint/GenericRescue
            # Exception is captured so that it will be present in the ensure block
            raise
          ensure
            result = exception.nil? ? "success" : "error"
            GitHub.dogstats.distribution_timing_since(
              "merge_queue.dequeue.time",
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

      private

      sig { params(command: ICommand, payload: T.nilable(WebHook)).void }
      def dispatch_webhook(command, payload)
        return if payload.nil?
        ICommand::Result.with_retry { command.dispatch_webhook!(payload) }
      end
    end
  end
end
