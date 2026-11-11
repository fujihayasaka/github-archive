# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    class RemoveEntry < Base
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

          # When the entry is part of a stack, also remove all descendant entries
          # to match the decision engine's removal behavior.
          if PullRequests::Stacks.enabled?(@repository)
            entries_to_remove = entries_with_stack_descendants(entry)
          else
            entries_to_remove = [entry]
          end

          command = command_without_status_check_models

          destroyed_webhook_payloads = entries_to_remove.filter_map do |queue_entry|
            WebHook::Destroyed.for(entry: queue_entry, reason: WebHook::Destroyed::Reason::Dequeued)
          rescue WebHook::MissingDataError
            # This will be raised if the entry does not have an associated
            # merge commit, etc. In this context -- where the entry is being
            # removed manually -- this is not a problem, and we can just skip
            # sending the Web hook.
            nil
          end

          begin
            reason = MergeQueues::Entry::RemovalReason::Manual

            remove_result = ICommand::Result.with_retry do
              command.remove!(entries_to_remove, actor:, reason:)
            end

            case remove_result
            when ICommand::Result::Error
              raise remove_result.as_exception
            when ICommand::Result::Success
              destroyed_webhook_payloads.each { |payload| dispatch_webhook(command, payload) }
              entries_to_remove.each do |queue_entry|
                dispatch_webhook(command, MergeQueues::WebHook::Dequeued.for_model(entry: queue_entry, reason:, actor:))
              end

              notify_websockets!(entries_to_remove)
              request_execution!
            else
              T.absurd(remove_result)
            end
          rescue => exception
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

      # Returns the entry and all stack descendants as MergeQueueEntry models,
      # mirroring the decision engine's `EntryList#with_stack` behavior.
      sig { params(entry: MergeQueueEntry).returns(T::Array[MergeQueueEntry]) }
      def entries_with_stack_descendants(entry)
        entry_list = factory.to_entry_list
        domain_entry = entry_list.find { |e| e.merge_queue_entry_id == entry.id }

        return [entry] if domain_entry.nil?

        domain_entries = entry_list.with_stack(domain_entry)

        return [entry] if domain_entries.size <= 1

        models_by_id = factory.merge_queue_entry_models.index_by(&:id)
        domain_entries.filter_map { |e| models_by_id[e.merge_queue_entry_id] }
      end

      sig { params(command: ICommand, payload: T.nilable(WebHook)).void }
      def dispatch_webhook(command, payload)
        return if payload.nil?
        ICommand::Result.with_retry { command.dispatch_webhook!(payload) }
      end
    end
  end
end
