# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    class Enqueue < Base
      sig do
        params(
          queue: MergeQueue,
          pull_request: PullRequest,
          actor: User,
          solo: T::Boolean,
          jump_queue: T::Boolean,
        ).returns(MergeQueueEntry)
      end
      def call(queue:, pull_request:, actor:, solo: false, jump_queue: false)
        stats_start_time = GitHub::Dogstats.monotonic_time

        position = queue.entries.count + 1

        entry = MergeQueueEntry.new(
          queue:,
          pull_request:,
          enqueuer: actor,
          author: pull_request.user,
          solo:,
          jump_queue:,
          position:,
          state: MergeQueues::Entry::State::Queued::VALUE,
          enqueued_rule_suite_id: nil,
          enqueued_head_sha: pull_request.head_sha,
        )
        validate_queue_has_space(entry:)
        create_enqueued_rule_suite(entry:, actor:)

        begin
          entry.save!
        rescue ActiveRecord::RecordInvalid
          entry.enqueued_rule_suite&.destroy!
          raise
        end

        request_execution!

        record_stats(entry:)

        queue.notify_subscribers(pull_request:)

        GitHub.instrument("pull_request.enqueued",
          pull_request_id: pull_request.id,
          actor_id: actor.id,
        )

        entry
      ensure
        GitHub.dogstats.distribution_timing_since("merge_queue.enqueue.time", stats_start_time)
        if jump_queue
          queue.instrument_pull_request_queue_jump(pull_request:, enqueuer: actor)
        end
      end

      # Enqueue multiple PRs in a single transaction. Entries are saved
      # atomically — if any save fails the entire batch is rolled back.
      # Post-save side effects (execution request, stats, notifications)
      # run only after the transaction commits successfully.
      sig do
        params(
          queue: MergeQueue,
          pull_requests: T::Array[PullRequest],
          actor: T.untyped,
        ).returns(T::Array[MergeQueueEntry])
      end
      def call_many(queue:, pull_requests:, actor:)
        stats_start_time = GitHub::Dogstats.monotonic_time
        entries = T.let([], T::Array[MergeQueueEntry])

        MergeQueueEntry.transaction do
          base_position = queue.entries.count

          pull_requests.each_with_index do |pull_request, index|
            entry = MergeQueueEntry.new(
              queue:,
              pull_request:,
              enqueuer: actor,
              author: pull_request.user,
              solo: false,
              jump_queue: false,
              position: base_position + index + 1,
              state: MergeQueues::Entry::State::Queued::VALUE,
              enqueued_rule_suite_id: nil,
              enqueued_head_sha: pull_request.head_sha,
            )
            validate_queue_has_space(entry:)
            # TODO: Implement stacks-aware rule suite evaluation for stacked PRs.
            entry.save!
            entries << entry
          end
        end

        # Post-transaction side effects — only run if the transaction committed.
        request_execution!

        entries.each do |entry|
          record_stats(entry:)
          pull_request = T.must(entry.pull_request)
          queue.notify_subscribers(pull_request:)
          GitHub.instrument("pull_request.enqueued",
            pull_request_id: pull_request.id,
            actor_id: actor.id,
          )
        end

        entries
      ensure
        GitHub.dogstats.distribution_timing_since("merge_queue.enqueue_many.time", stats_start_time)
      end

      private

      sig { params(entry: MergeQueueEntry).void }
      def validate_queue_has_space(entry:)
        # This check is prone to race conditions if two elements were enqueued
        # at the exact same time. This guard is more to prevent abuse than a
        # technical limit so we're not worried if they are able to create a
        # few extra entries.
        return if entry.position <= MergeQueue::MAX_QUEUE_ENTRIES

        GitHub.logger.info(
          "merge queue full",
          "code.namespace": "MergeQueues::Service::Enqueue",
          "code.function": "call",
          "gh.merge_queue.id": entry.queue&.id,
          "gh.merge_queue.pull_request.id": entry.pull_request_id
        )

        entry.errors.add(:base, "The merge queue is full. Try again after merging or removing items from the queue")
        raise ActiveRecord::RecordInvalid.new(entry)
      end

      sig { params(entry: MergeQueueEntry, actor: User).void }
      def create_enqueued_rule_suite(entry:, actor:)
        pull_request = T.must(entry.pull_request)
        queue = T.must(entry.queue)

        create_suite_result = MergeQueueEntry.create_enqueued_rule_suite(
          queue:,
          pull_request:,
          enqueuer: actor,
        )

        case create_suite_result
        when String
          # create_enqueued_rule_suite returned error message
          entry.validate
          entry.errors.add(:pull_request, create_suite_result)
          raise ActiveRecord::RecordInvalid.new(entry)
        when RuleEngine::RuleSuite
          entry.enqueued_rule_suite = create_suite_result
        end
      end

      sig { params(entry: MergeQueueEntry).void }
      def record_stats(entry:)
        stat = entry.stat || entry.build_stat
        stat.update!(
          queue: entry.queue,
          enqueued_at: Time.current,
          enqueued_in_position: entry.position,
        )
      end
    end
  end
end
