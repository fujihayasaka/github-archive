# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    # Attempt to lock the best MergeQueueEntry reading from the back of the queue to the front.
    #
    # This is for backwards compatability with the already existing GraphQL mutations. We will be
    # revisiting the public API and this is a "temporary" shim.
    #
    # This behavior is what is currently feature flagged and only enabled for github/github and concorde-mg.
    #
    # Called by Platform::Mutations::LockMergeQueue
    class LockBestEntry < Base
      extend T::Sig

      sig { params(actor: User).returns(T.nilable(MergeQueueEntry)) }
      def call(actor:)
        stats_start_time = GitHub::Dogstats.monotonic_time
        GitHub.logger.with_named_tags(
          "code.namespace": "MergeQueues::Service",
          "code.function": "lock_best_entry!",
          "gh.repo.id": @repository.id,
          "gh.merge_queue.branch": @branch,
          "gh.actor.id": actor.id
        ) do
          if @merge_queue.nil?
            raise ActiveRecord::RecordNotFound
          end

          next_group = Group.find_next(configuration:, entries: factory.merge_queue_entry_models)

          if next_group.locked?
            return next_group.head_entry!
          end

          begin
            case next_group_state = next_group.state
            when Group::State::Mergeable
              models = next_group.entries

              if models.last&.head_sha
                MergeQueueEntry.where(id: models.map(&:id)).update_all(locked: true)
                notify_websockets!(models)
                request_execution!
                return models.last
              end
            when Group::State::Empty
              raise Errors::NoLockableGroup.new("No mergeable group found for #{@merge_queue.branch}")
            when Group::State::MinimumSizeNotMet
              raise Errors::MinimumGroupSizeNotMet.new("Minimum group size of #{configuration.min_merge_entries_size} not met for branch #{@merge_queue.branch}")
            else
              T.absurd(next_group_state)
            end
          rescue => exception # rubocop:todo Lint/GenericRescue
            # Exception is captured so that it will be present in the ensure block
            raise
          ensure
            result = exception.nil? ? "success" : "error"
            GitHub.dogstats.distribution_timing_since(
              "merge_queue.lock.time",
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
